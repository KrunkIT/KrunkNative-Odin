#+build windows

package main

import "core:testing"
import win "core:sys/windows"
import glfw "vendor:glfw"
import shared "../shared"

when ODIN_TEST {
	g_mouse_test_scroll: f64
	mouse_test_scroll :: proc "c" (window: glfw.WindowHandle, x, y: f64) { g_mouse_test_scroll += y }

	@(test)
	buffered_mouse_preserves_high_rate_motion :: proc(t: ^testing.T) {
		mouse := new(Native_Mouse)
		defer free(mouse)
		// A full second of 8 kHz input, including reversals and no-motion
		// button reports, delivered in the same bounded chunks as the OS API.
		expected_x, expected_y: i64
		for batch in 0..<8 {
			for i in 0..<1000 {
				index := batch * 1000 + i
				report := cast(^win.RAWINPUT)&mouse.buffer[i * size_of(win.RAWINPUT) / size_of(u64)]
				report^ = {}
				report.header = {dwType = win.RIM_TYPEMOUSE, dwSize = size_of(win.RAWINPUT)}
				report.data.mouse.lLastX = i32(index % 17 - 8)
				report.data.mouse.lLastY = i32(index % 13 - 6)
				expected_x += i64(report.data.mouse.lLastX)
				expected_y += i64(report.data.mouse.lLastY)
			}
			data := (cast([^]u8)&mouse.buffer[0])[:size_of(mouse.buffer)]
			testing.expect(t, native_mouse_consume_buffer(mouse, data, 1000), "valid 8 kHz input batches must decode")
		}
		testing.expect(t, mouse.x == expected_x && mouse.y == expected_y, "batching must preserve the exact sum without dropping or duplicating reports")
		testing.expect(t, native_mouse_take_delta(mouse) == (shared.Vec2{f32(expected_x), f32(expected_y)}), "a frame must receive the complete raw delta")
		testing.expect(t, native_mouse_take_delta(mouse) == (shared.Vec2{}), "the next frame must not repeat consumed movement")
		// Relative movement remains raw, even at values beyond 32-bit totals.
		large := win.RAWINPUT{header = {dwType = win.RIM_TYPEMOUSE, dwSize = size_of(win.RAWINPUT)}}
		large.data.mouse.lLastX = max(i32)
		native_mouse_accumulate(mouse, &large)
		native_mouse_accumulate(mouse, &large)
		testing.expect(t, mouse.x == i64(max(i32)) * 2, "accumulation must not wrap at 32 bits")
		native_mouse_reset(mouse)
		testing.expect(t, mouse.x == 0 && mouse.y == 0, "focus/capture transitions must discard stale movement")
	}

	@(test)
	buffered_mouse_handles_record_alignment_and_absolute_devices :: proc(t: ^testing.T) {
		mouse := new(Native_Mouse)
		defer free(mouse)
		data := (cast([^]u8)&mouse.buffer[0])[:size_of(mouse.buffer)]
		// Variable-length HID records have padding before the next mouse record.
		hid := cast(^win.RAWINPUTHEADER)&data[0]
		hid^ = {dwType = win.RIM_TYPEHID, dwSize = size_of(win.RAWINPUTHEADER) + 1}
		offset := (int(hid.dwSize) + 7) & ~int(7)
		report := cast(^win.RAWINPUT)&data[offset]
		report.header = {dwType = win.RIM_TYPEMOUSE, dwSize = size_of(win.RAWINPUT)}
		report.data.mouse.lLastX, report.data.mouse.lLastY = 23, -41
		testing.expect(t, native_mouse_consume_buffer(mouse, data[:offset + size_of(win.RAWINPUT)], 2) && mouse.x == 23 && mouse.y == -41,
			"non-mouse records must not corrupt the next aligned mouse record")
		testing.expect(t, !native_mouse_consume_buffer(mouse, data[:offset + size_of(win.RAWINPUT) - 1], 2), "truncated records must be rejected")
		hid.dwSize = 0
		testing.expect(t, !native_mouse_consume_buffer(mouse, data, 1), "zero-size records must not loop or read outside the buffer")
		native_mouse_reset(mouse)
		report.data.mouse.usFlags = win.MOUSE_MOVE_ABSOLUTE | win.MOUSE_VIRTUAL_DESKTOP
		report.data.mouse.lLastX, report.data.mouse.lLastY = 10000, 20000
		native_mouse_accumulate(mouse, report)
		testing.expect(t, mouse.x == 0 && mouse.y == 0, "the first absolute report must establish a baseline without a camera jump")
		report.data.mouse.lLastX, report.data.mouse.lLastY = 11000, 19000
		native_mouse_accumulate(mouse, report)
		testing.expect(t, mouse.x > 0 && mouse.y < 0, "absolute devices must retain directional movement")
		native_mouse_reset(mouse)
		native_mouse_accumulate(mouse, report)
		testing.expect(t, mouse.x == 0 && mouse.y == 0, "returning from focus loss must rebaseline absolute input")
	}

	@(test)
	buffered_mouse_window_lifecycle :: proc(t: ^testing.T) {
		if !testing.expect(t, bool(glfw.Init())) do return
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		window := glfw.CreateWindow(160, 120, "Mouse input regression", nil, nil)
		if !testing.expect(t, window != nil) do return
		defer glfw.DestroyWindow(window)
		hwnd := glfw.GetWin32Window(window)
		previous := win.GetWindowLongPtrW(hwnd, win.GWLP_WNDPROC)
		if !testing.expect(t, client_mouse_init(window), "the Windows input hook must install") do return
		defer client_mouse_fini()
		testing.expect(t, client_mouse_init(window), "initialization must be safe to repeat without creating a recursive hook")
		testing.expect(t, win.GetWindowLongPtrW(hwnd, win.GWLP_WNDPROC) != previous, "window procedure must be wrapped")
		fallback := shared.Vec2{12, -3}
		testing.expect(t, client_mouse_delta(fallback) == fallback, "menu/unfocused input must retain GLFW cursor movement")
		win.SendMessageW(hwnd, win.WM_LBUTTONDOWN, 0, 0)
		testing.expect(t, glfw.GetMouseButton(window, glfw.MOUSE_BUTTON_LEFT) == glfw.PRESS, "mouse buttons must still reach GLFW")
		win.SendMessageW(hwnd, win.WM_LBUTTONUP, 0, 0)
		testing.expect(t, glfw.GetMouseButton(window, glfw.MOUSE_BUTTON_LEFT) == glfw.RELEASE, "mouse button releases must still reach GLFW")
		g_mouse_test_scroll = 0
		glfw.SetScrollCallback(window, mouse_test_scroll)
		win.SendMessageW(hwnd, win.WM_MOUSEWHEEL, 120 << 16, 0)
		testing.expect(t, g_mouse_test_scroll == 1, "scroll wheel input must still reach GLFW")
		win.SendMessageW(hwnd, win.WM_KEYDOWN, 'W', 0x00110000)
		testing.expect(t, glfw.GetKey(window, glfw.KEY_W) == glfw.PRESS, "keyboard input must still reach GLFW")
		win.SendMessageW(hwnd, win.WM_KEYUP, 'W', 0xC0110000)
		testing.expect(t, glfw.GetKey(window, glfw.KEY_W) == glfw.RELEASE, "keyboard releases must still reach GLFW")
		g_native_mouse.x = 100
		win.SendMessageW(hwnd, win.WM_KILLFOCUS, 0, 0)
		testing.expect(t, g_native_mouse.x == 0 && !g_native_mouse.active, "focus loss must clear queued movement")
		client_poll_events()
		client_mouse_fini()
		testing.expect(t, win.GetWindowLongPtrW(hwnd, win.GWLP_WNDPROC) == previous, "shutdown must restore GLFW's original window procedure")
		testing.expect(t, client_mouse_delta(fallback) == fallback, "fallback must remain usable after shutdown")
	}
}
