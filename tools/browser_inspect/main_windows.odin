package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import win "core:sys/windows"
import wv "../../src/webview2"

// Standalone inspection host. It never reads .env or the game's token/profile/cache.
window, address: win.HWND
buttons: [3]win.HWND
controller, view: ^wv.COM
done, failed, parent_pipe: bool
initial_url := "https://krunker.io/"
env_handler, controller_handler, navigation_handler, popup_handler: wv.Handler
env_vtable, controller_vtable, navigation_vtable, popup_vtable: [4]rawptr

// Pass options explicitly: runtime versions may ignore process environment flags.
Options :: struct { v: ^[11]rawptr, iid: win.GUID }
options: Options
options_vtable: [11]rawptr
debug_arguments: string
options_query :: proc "system" (this: ^Options, iid: ^win.GUID, out: ^rawptr) -> win.HRESULT {
	context = runtime.default_context()
	if out == nil { return win.HRESULT(-2147467261) }
	out^ = nil
	if iid^ == this.iid || iid^ == win.IUnknown_UUID^ { out^ = this; return 0 }
	return win.HRESULT(-2147467262)
}
options_ref :: proc "system" (this: rawptr) -> u32 { return 1 }
options_string :: proc(value: string, out: ^^u16) -> win.HRESULT {
	if out == nil { return win.HRESULT(-2147467261) }
	wide := win.utf8_to_utf16(value)
	out^ = cast(^u16)win.CoTaskMemAlloc(uint((len(wide)+1)*size_of(u16)))
	if out^ == nil { return win.HRESULT(-2147024882) }
	copy((cast([^]u16)out^)[:len(wide)], wide)
	(cast([^]u16)out^)[len(wide)] = 0
	return 0
}
options_arguments :: proc "system" (this: rawptr, out: ^^u16) -> win.HRESULT {
	context = runtime.default_context()
	return options_string(debug_arguments, out)
}
options_language :: proc "system" (this: rawptr, out: ^^u16) -> win.HRESULT {
	context = runtime.default_context()
	return options_string("", out)
}
options_version :: proc "system" (this: rawptr, out: ^^u16) -> win.HRESULT {
	context = runtime.default_context()
	// CORE_WEBVIEW_TARGET_PRODUCT_VERSION from the pinned SDK's options header.
	return options_string("143.0.3650.58", out)
}
options_put_string :: proc "system" (this: rawptr, value: ^u16) -> win.HRESULT { return win.HRESULT(-2147467263) }
options_sso :: proc "system" (this: rawptr, out: ^win.BOOL) -> win.HRESULT {
	if out == nil { return win.HRESULT(-2147467261) }
	out^ = false
	return 0
}
options_put_sso :: proc "system" (this: rawptr, value: win.BOOL) -> win.HRESULT { return win.HRESULT(-2147467263) }

error :: proc(message: string) {
	fmt.println("[inspector]", message)
	if !parent_pipe { win.MessageBoxW(window, cast(cstring16)raw_data(win.utf8_to_utf16(message)), win.L("Krodin browser inspector"), win.MB_OK | win.MB_ICONERROR) }
	done, failed = true, true
}
navigate :: proc(url: string) {
	if view == nil { return }
	if !(strings.has_prefix(url, "https://") || strings.has_prefix(url, "http://127.0.0.1:") || url == "about:blank") { return }
	(cast(proc "system" (^wv.COM, ^u16) -> win.HRESULT)view.v[5])(view, raw_data(win.utf8_to_utf16(url)))
}
devtools :: proc() {
	if view != nil { (cast(proc "system" (^wv.COM) -> win.HRESULT)view.v[51])(view) }
}
resize :: proc() {
	if window == nil { return }
	bound: win.RECT
	win.GetClientRect(window, &bound)
	if address != nil { win.MoveWindow(address, 8, 8, max(bound.right-310, 80), 25, true) }
	for button, i in buttons { if button != nil { win.MoveWindow(button, max(bound.right-294, 100)+i32(i)*94, 8, 88, 25, true) } }
	if controller != nil {
		bound.top = 42
		(cast(proc "system" (^wv.COM, win.RECT) -> win.HRESULT)controller.v[6])(controller, bound)
	}
}
window_proc :: proc "system" (hwnd: win.HWND, message: u32, w: win.WPARAM, l: win.LPARAM) -> win.LRESULT {
	context = runtime.default_context()
	switch message {
	case win.WM_CLOSE: done = true; return 0
	case win.WM_SIZE: resize(); return 0
	case win.WM_DESTROY: done = true; return 0
	case win.WM_COMMAND:
		switch int(w & 0xFFFF) {
		case 101:
			text: [4096]u16
			count := win.GetWindowTextW(address, &text[0], len(text))
			if count > 0 { navigate(win.utf16_to_utf8(text[:count]) or_else "") }
		case 102:
			if view != nil { (cast(proc "system" (^wv.COM) -> win.HRESULT)view.v[31])(view) }
		case 103: devtools()
		}
		return 0
	}
	return win.DefWindowProcW(hwnd, message, w, l)
}
environment_ready :: proc "system" (this: rawptr, result: win.HRESULT, env: ^wv.COM) -> win.HRESULT {
	context = runtime.default_context()
	fmt.printf("[inspector] Environment callback: HRESULT %d.\n", result)
	if done { return 0 }
	if result < 0 || env == nil { error("Could not open the inspector profile. Close other browser inspectors and retry."); return 0 }
	if (cast(proc "system" (^wv.COM, win.HWND, ^wv.Handler) -> win.HRESULT)env.v[3])(env, window, &controller_handler) < 0 { error("Could not create the browser controller.") }
	return 0
}
controller_ready :: proc "system" (this: rawptr, result: win.HRESULT, object: ^wv.COM) -> win.HRESULT {
	context = runtime.default_context()
	fmt.printf("[inspector] Controller callback: HRESULT %d.\n", result)
	if done { return 0 }
	if result < 0 || object == nil { error("Could not initialize WebView2."); return 0 }
	controller = object; wv.add_ref(controller)
	if (cast(proc "system" (^wv.COM, ^^wv.COM) -> win.HRESULT)controller.v[25])(controller, &view) < 0 { error("Could not create the browser view."); return 0 }
	settings: ^wv.COM
	if (cast(proc "system" (^wv.COM, ^^wv.COM) -> win.HRESULT)view.v[3])(view, &settings) >= 0 {
		(cast(proc "system" (^wv.COM, win.BOOL) -> win.HRESULT)settings.v[12])(settings, true)
		wv.release_com(settings)
	}
	resize()
	(cast(proc "system" (^wv.COM, win.BOOL) -> win.HRESULT)controller.v[4])(controller, true)
	event: i64
	(cast(proc "system" (^wv.COM, ^wv.Handler, ^i64) -> win.HRESULT)view.v[7])(view, &navigation_handler, &event)
	(cast(proc "system" (^wv.COM, ^wv.Handler, ^i64) -> win.HRESULT)view.v[44])(view, &popup_handler, &event)
	navigate(initial_url)
	devtools()
	return 0
}
navigation_starting :: proc "system" (this: rawptr, sender, args: ^wv.COM) -> win.HRESULT {
	context = runtime.default_context()
	// The address bar is local UI; no URL or credential is printed to the console.
	uri := wv.get_text(args, 3)
	win.SetWindowTextW(address, cast(cstring16)raw_data(win.utf8_to_utf16(uri)))
	return 0
}
popup_requested :: proc "system" (this: rawptr, sender, args: ^wv.COM) -> win.HRESULT {
	context = runtime.default_context()
	(cast(proc "system" (^wv.COM, win.BOOL) -> win.HRESULT)args.v[6])(args, true)
	navigate(wv.get_text(args, 3))
	return 0
}

run :: proc() {
	port := 0
	for i := 1; i < len(os.args); i += 1 {
		switch os.args[i] {
		case "--parent-pipe": parent_pipe = true
		case "--wait-for-tracer": initial_url = "about:blank"
		case "--debug-port":
			i += 1
			if i >= len(os.args) { os.exit(2) }
			for digit in os.args[i] {
				if digit < '0' || digit > '9' || port > 6553 { os.exit(2) }
				port = port*10 + int(digit-'0')
			}
			if port < 1 || port > 65535 { os.exit(2) }
		case: initial_url = os.args[i]
		}
	}
	// The debugging endpoint exists only when explicitly requested by the launcher.
	if port > 0 {
		debug_arguments = fmt.aprintf("--remote-debugging-port=%d --remote-debugging-address=127.0.0.1", port)
	}
	fmt.printf("[inspector] Starting separate browser; debugging port %d.\n", port)
	if win.CoInitializeEx(nil, .APARTMENTTHREADED) < 0 { error("Could not initialize COM."); return }
	defer win.CoUninitialize()
	directory, dir_err := os.get_executable_directory(context.temp_allocator)
	if dir_err != nil { error("Could not locate the WebView2 loader."); return }
	loader := win.LoadLibraryExW(cast(cstring16)raw_data(win.utf8_to_utf16(fmt.tprintf("%s\\WebView2Loader.dll", directory))), nil, {.LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR, .LOAD_LIBRARY_SEARCH_SYSTEM32})
	if loader == nil { error("WebView2Loader.dll is missing. Run build.bat inspect none."); return }
	defer win.FreeLibrary(loader)
	version_fn := cast(proc "system" (^u16, ^^u16) -> win.HRESULT)win.GetProcAddress(loader, "GetAvailableCoreWebView2BrowserVersionString")
	create_fn := cast(proc "system" (^u16, ^u16, rawptr, ^wv.Handler) -> win.HRESULT)win.GetProcAddress(loader, "CreateCoreWebView2EnvironmentWithOptions")
	if version_fn == nil || create_fn == nil { error("The official WebView2 loader is invalid. Rebuild the inspector."); return }
	version: ^u16
	if version_fn(nil, &version) < 0 { error("Install Microsoft Edge WebView2 Evergreen Runtime: https://developer.microsoft.com/microsoft-edge/webview2/"); return }
	win.CoTaskMemFree(version)
	local, found := os.lookup_env_alloc("LOCALAPPDATA", context.allocator); defer delete(local)
	if !found || len(local) == 0 { error("LOCALAPPDATA is unavailable."); return }
	profile := fmt.aprintf("%s\\Krodin\\BrowserInspector", local); defer delete(profile)
	if os.make_directory_all(profile) != nil { error("Could not create the separate inspector profile."); return }
	wv.init_handler(&env_handler, &env_vtable, win.L("{4e8a3389-c9d8-4bd2-b6b5-124fee6cc14d}"), rawptr(environment_ready))
	wv.init_handler(&controller_handler, &controller_vtable, win.L("{6c4819f3-c9b7-4260-8127-c9f5bde7f68c}"), rawptr(controller_ready))
	wv.init_handler(&navigation_handler, &navigation_vtable, win.L("{9adbe429-f36d-432b-9ddc-f8881fbd76e3}"), rawptr(navigation_starting))
	wv.init_handler(&popup_handler, &popup_vtable, win.L("{d4c185fe-c81c-4989-97af-2d3fa7ab5651}"), rawptr(popup_requested))
	instance := win.HANDLE(win.GetModuleHandleW(nil))
	class := win.WNDCLASSEXW{cbSize = size_of(win.WNDCLASSEXW), lpfnWndProc = window_proc, hInstance = instance, lpszClassName = win.L("KrodinBrowserInspector")}
	if win.RegisterClassExW(&class) == 0 { error("Could not register the inspector window."); return }
	window = win.CreateWindowExW(0, class.lpszClassName, win.L("Krodin browser inspector - separate profile"), win.WS_OVERLAPPEDWINDOW, win.CW_USEDEFAULT, win.CW_USEDEFAULT, 1400, 900, nil, nil, instance, nil)
	if window == nil { error("Could not open the inspector window."); return }
	defer win.DestroyWindow(window)
	address = win.CreateWindowExW(0, win.L("EDIT"), cast(cstring16)raw_data(win.utf8_to_utf16(initial_url)), win.WS_CHILD | win.WS_VISIBLE | win.WS_BORDER | win.ES_AUTOHSCROLL, 8, 8, 900, 25, window, win.HMENU(uintptr(100)), instance, nil)
	for label, i in ([]cstring16{win.L("Go"), win.L("Reload"), win.L("DevTools")}) {
		buttons[i] = win.CreateWindowExW(0, win.L("BUTTON"), label, win.WS_CHILD | win.WS_VISIBLE, 1000+i32(i)*85, 8, 80, 25, window, win.HMENU(uintptr(101+i)), instance, nil)
	}
	resize()
	win.ShowWindow(window, win.SW_SHOW)
	options_vtable = {rawptr(options_query), rawptr(options_ref), rawptr(options_ref), rawptr(options_arguments), rawptr(options_put_string), rawptr(options_language), rawptr(options_put_string), rawptr(options_version), rawptr(options_put_string), rawptr(options_sso), rawptr(options_put_sso)}
	options.v = &options_vtable
	win.IIDFromString(win.L("{2fde08a8-1e9a-4766-8c05-95a9ceb9d1c5}"), &options.iid)
	created := create_fn(nil, raw_data(win.utf8_to_utf16(profile)), &options, &env_handler)
	if created < 0 { error(fmt.tprintf("Could not create the inspector browser environment (HRESULT %d). Close other inspectors and retry.", created)); return }
	defer {
		if controller != nil { (cast(proc "system" (^wv.COM) -> win.HRESULT)controller.v[24])(controller) }
		wv.release_com(view); wv.release_com(controller)
	}
	for !done {
		message: win.MSG
		for win.PeekMessageW(&message, nil, 0, 0, win.PM_REMOVE) { win.TranslateMessage(&message); win.DispatchMessageW(&message) }
		if parent_pipe {
			available: u32
			if !win.PeekNamedPipe(win.GetStdHandle(win.STD_INPUT_HANDLE), nil, 0, nil, &available, nil) || available > 0 { done = true }
		}
		free_all(context.temp_allocator)
		time.sleep(10*time.Millisecond)
	}
}
main :: proc() {
	run()
	if failed { os.exit(1) }
}
