#+build windows

package main

import "base:runtime"
import win "core:sys/windows"
import glfw "vendor:glfw"
import shared "../shared"

// GLFW reads one WM_INPUT at a time. Drain queued reports in batches so an
// 8 kHz mouse does not require thousands of window-procedure calls per second.
// GLFW still owns registration, cursor capture, keyboard, buttons and scrolling.
Native_Mouse :: struct {
	window: glfw.WindowHandle,
	hwnd: win.HWND,
	previous_proc: win.WNDPROC,
	active, buffer_failed: bool,
	x, y: i64,
	absolute: [8]struct { device: win.HANDLE, valid: bool, x, y: i64 },
	buffer: [8192]u64, // 64 KiB, aligned for native RAWINPUT records.
}

g_native_mouse: Native_Mouse

native_mouse_reset :: proc(mouse: ^Native_Mouse) {
	mouse.x, mouse.y = 0, 0
	for &device in mouse.absolute { device.valid = false }
}

native_mouse_sync :: proc(mouse: ^Native_Mouse) {
	active := mouse.window != nil &&
		glfw.GetWindowAttrib(mouse.window, glfw.FOCUSED) != 0 &&
		glfw.GetInputMode(mouse.window, glfw.CURSOR) == glfw.CURSOR_DISABLED &&
		glfw.GetInputMode(mouse.window, glfw.RAW_MOUSE_MOTION) != 0
	if active != mouse.active {
		native_mouse_reset(mouse)
		mouse.active = active
	}
}

native_mouse_accumulate :: proc(mouse: ^Native_Mouse, input: ^win.RAWINPUT) {
	if input.header.dwType != win.RIM_TYPEMOUSE { return }
	report := &input.data.mouse
	if report.usFlags & win.MOUSE_MOVE_ABSOLUTE == 0 {
		mouse.x += i64(report.lLastX)
		mouse.y += i64(report.lLastY)
		return
	}
	// Tablets / remote desktops can report normalized absolute coordinates.
	// Track each device separately and establish a baseline without a camera jump.
	width, height := win.GetSystemMetrics(win.SM_CXSCREEN), win.GetSystemMetrics(win.SM_CYSCREEN)
	if report.usFlags & win.MOUSE_VIRTUAL_DESKTOP != 0 {
		width, height = win.GetSystemMetrics(win.SM_CXVIRTUALSCREEN), win.GetSystemMetrics(win.SM_CYVIRTUALSCREEN)
	}
	x := i64(report.lLastX) * i64(width) / 65535
	y := i64(report.lLastY) * i64(height) / 65535
	slot := &mouse.absolute[0]
	for &device in mouse.absolute {
		if device.valid && device.device == input.header.hDevice { slot = &device; break }
		if !device.valid { slot = &device }
	}
	if slot.valid && slot.device == input.header.hDevice {
		mouse.x += x - slot.x
		mouse.y += y - slot.y
	}
	slot^ = {device = input.header.hDevice, valid = true, x = x, y = y}
}

native_mouse_consume_buffer :: proc(mouse: ^Native_Mouse, data: []u8, count: u32) -> bool {
	offset := 0
	for _ in 0..<count {
		if len(data) - offset < size_of(win.RAWINPUTHEADER) { return false }
		input := cast(^win.RAWINPUT)&data[offset]
		size := int(input.header.dwSize)
		if size < size_of(win.RAWINPUTHEADER) || size > len(data) - offset { return false }
		if input.header.dwType == win.RIM_TYPEMOUSE {
			if size < size_of(win.RAWINPUT) { return false }
			native_mouse_accumulate(mouse, input)
		}
		// NEXTRAWINPUTBLOCK aligns to a native pointer on Windows.
		offset += (size + size_of(uintptr) - 1) & ~int(size_of(uintptr) - 1)
	}
	return true
}

native_mouse_drain :: proc(mouse: ^Native_Mouse) {
	if mouse.buffer_failed { return }
	// Bound each batch; new reports are handled by the normal event pump.
	for _ in 0..<4 {
		size := u32(size_of(mouse.buffer))
		count := win.GetRawInputBuffer(cast(^win.RAWINPUT)&mouse.buffer[0], &size, size_of(win.RAWINPUTHEADER))
		if count == 0 { break }
		if count == max(u32) { mouse.buffer_failed = true; break }
		data := (cast([^]u8)&mouse.buffer[0])[:size_of(mouse.buffer)]
		if !native_mouse_consume_buffer(mouse, data, count) { mouse.buffer_failed = true; break }
	}
}

native_mouse_window_proc :: proc "system" (hwnd: win.HWND, message: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
	context = runtime.default_context()
	mouse := &g_native_mouse
	if message == win.WM_INPUT {
		native_mouse_sync(mouse)
		if mouse.active {
			// The WM_INPUT already removed by PeekMessage is not returned by
			// GetRawInputBuffer. Read it exactly once, then drain the queued rest.
			input: win.RAWINPUT
			size := u32(size_of(input))
			read := win.GetRawInputData(win.HRAWINPUT(lparam), win.RID_INPUT, &input, &size, size_of(win.RAWINPUTHEADER))
			if read != max(u32) && read >= size_of(win.RAWINPUT) && input.header.dwType == win.RIM_TYPEMOUSE {
				native_mouse_accumulate(mouse, &input)
				native_mouse_drain(mouse)
				// Required cleanup for the foreground WM_INPUT handle.
				return win.DefWindowProcW(hwnd, message, wparam, lparam)
			}
		}
	}
	if message == win.WM_KILLFOCUS || message == win.WM_SETFOCUS {
		native_mouse_reset(mouse)
		mouse.active = false
	}
	return win.CallWindowProcW(mouse.previous_proc, hwnd, message, wparam, lparam)
}

client_mouse_init :: proc(window: glfw.WindowHandle) -> bool {
	if g_native_mouse.previous_proc != nil { return g_native_mouse.window == window }
	if !bool(glfw.RawMouseMotionSupported()) || size_of(uintptr) != 8 { return false }
	mouse := &g_native_mouse
	mouse.window = window
	mouse.hwnd = glfw.GetWin32Window(window)
	previous := win.SetWindowLongPtrW(mouse.hwnd, win.GWLP_WNDPROC, transmute(win.LONG_PTR)win.WNDPROC(native_mouse_window_proc))
	if previous == 0 { mouse^ = {}; return false }
	mouse.previous_proc = transmute(win.WNDPROC)previous
	return true
}

client_mouse_fini :: proc() {
	mouse := &g_native_mouse
	if mouse.previous_proc != nil {
		win.SetWindowLongPtrW(mouse.hwnd, win.GWLP_WNDPROC, transmute(win.LONG_PTR)mouse.previous_proc)
	}
	mouse^ = {}
}

native_mouse_take_delta :: proc(mouse: ^Native_Mouse) -> shared.Vec2 {
	delta := shared.Vec2{f32(mouse.x), f32(mouse.y)}
	mouse.x, mouse.y = 0, 0
	return delta
}

client_mouse_delta :: proc(fallback: shared.Vec2) -> shared.Vec2 {
	mouse := &g_native_mouse
	if mouse.previous_proc == nil { return fallback }
	native_mouse_sync(mouse)
	if !mouse.active { return fallback }
	return native_mouse_take_delta(mouse)
}

client_poll_events :: proc() {
	mouse := &g_native_mouse
	if mouse.previous_proc != nil {
		native_mouse_sync(mouse)
		if mouse.active { native_mouse_drain(mouse) }
	}
	glfw.PollEvents()
}
