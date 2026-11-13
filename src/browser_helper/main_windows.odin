package main

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import win "core:sys/windows"
import access "../browser_access"
import wv "../webview2"

// ABI slots are from Microsoft.Web.WebView2 1.0.3650.58, WebView2.h.
COM :: wv.COM
Handler :: wv.Handler
init_handler :: wv.init_handler
add_ref :: wv.add_ref
release_com :: wv.release_com
get_text :: wv.get_text
Browser :: struct {
	window: win.HWND,
	controller, view: ^COM,
	id, navigation, executing_navigation: u64,
	input, output: win.HANDLE,
	buffer: [dynamic]byte,
	started: time.Time,
	visible, done, executing, probe, sdk_seen, rejected, remembered: bool,
	waiting_for_login: bool,
	captcha: bool,
	captcha_game: string,
	session_path: string,
	last_script_diagnostic: string,
}
browser: Browser
env_handler, controller_handler, script_handler, navigation_handler, popup_handler: Handler
env_vtable, controller_vtable, script_vtable, navigation_vtable, popup_vtable: [4]rawptr
install_handler: Handler
install_vtable: [4]rawptr

notify :: proc(kind, value: string) {
	if browser.probe {
		fmt.println(kind == "TOKEN" ? "TOKEN_REDACTED" : kind == "TRACE" ? access.diagnostic_text(value) : access.status_text(value))
		return
	}
	if !access.send(browser.output, access.Message{browser.id, kind, value}) { browser.done = true }
}
// Only state transitions cross IPC; the half-second polling loop stays quiet.
trace_script :: proc(code: string) -> bool {
	text := access.diagnostic_text(code)
	if text == browser.last_script_diagnostic { return false }
	browser.last_script_diagnostic = text
	notify("TRACE", code)
	return true
}
fail :: proc(code: string) { notify("ERROR", code); browser.done = true }
show :: proc() {
	if browser.visible { return }
	browser.visible = true
	win.ShowWindow(browser.window, win.SW_SHOW)
	win.SetForegroundWindow(browser.window)
	notify("STATUS", "VISIBLE")
}
resize :: proc() {
	if browser.controller == nil { return }
	bound: win.RECT
	win.GetClientRect(browser.window, &bound)
	(cast(proc "system" (^COM, win.RECT) -> win.HRESULT)browser.controller.v[6])(browser.controller, bound)
}
window_proc :: proc "system" (window: win.HWND, message: u32, w: win.WPARAM, l: win.LPARAM) -> win.LRESULT {
	context = runtime.default_context()
	switch message {
	case win.WM_CLOSE: notify("ERROR", "CANCELLED"); browser.done = true; return 0
	case win.WM_SIZE: resize(); return 0
	case win.WM_DESTROY: browser.done = true; return 0
	}
	return win.DefWindowProcW(window, message, w, l)
}

environment_ready :: proc "system" (this: rawptr, result: win.HRESULT, env: ^COM) -> win.HRESULT {
	context = runtime.default_context()
	if browser.done { return 0 }
	if result < 0 || env == nil { fail("PROFILE_FAILED"); return 0 }
	notify("TRACE", "ENVIRONMENT_READY")
	hr := (cast(proc "system" (^COM, win.HWND, ^Handler) -> win.HRESULT)env.v[3])(env, browser.window, &controller_handler)
	if hr < 0 { fail("PROFILE_FAILED") }
	return 0
}
controller_ready :: proc "system" (this: rawptr, result: win.HRESULT, controller: ^COM) -> win.HRESULT {
	context = runtime.default_context()
	if browser.done { return 0 }
	if result < 0 || controller == nil { fail("PROFILE_FAILED"); return 0 }
	browser.controller = controller; add_ref(controller)
	if (cast(proc "system" (^COM, ^^COM) -> win.HRESULT)controller.v[25])(controller, &browser.view) < 0 { fail("HELPER_FAILED"); return 0 }
	notify("TRACE", "CONTROLLER_READY")
	resize()
	(cast(proc "system" (^COM, win.BOOL) -> win.HRESULT)controller.v[4])(controller, true)
	event: i64
	if (cast(proc "system" (^COM, ^Handler, ^i64) -> win.HRESULT)browser.view.v[7])(browser.view, &navigation_handler, &event) < 0 { fail("HELPER_FAILED"); return 0 }
	if (cast(proc "system" (^COM, ^Handler, ^i64) -> win.HRESULT)browser.view.v[44])(browser.view, &popup_handler, &event) < 0 { fail("HELPER_FAILED"); return 0 }
	if browser.captcha {
		game_json, err := json.marshal(browser.captcha_game)
		if err != nil { fail("CAPTCHA_SETUP_FAILED"); return 0 }
		defer delete(game_json)
		script := fmt.tprintf("window.__krodinCaptchaGame = %s;\n%s", string(game_json), string(#load("captcha.js")))
		if (cast(proc "system" (^COM, ^u16, ^Handler) -> win.HRESULT)browser.view.v[27])(browser.view, raw_data(win.utf8_to_utf16(script)), &install_handler) < 0 { fail("CAPTCHA_SETUP_FAILED") }
	} else {
		if (cast(proc "system" (^COM, ^u16) -> win.HRESULT)browser.view.v[5])(browser.view, win.L("https://krunker.io/")) < 0 { fail("HELPER_FAILED") }
	}
	return 0
}
handoff_installed :: proc "system" (this: rawptr, result: win.HRESULT, data: ^u16) -> win.HRESULT {
	context = runtime.default_context()
	if browser.done { return 0 }
	if result < 0 { fail("CAPTCHA_SETUP_FAILED"); return 0 }
	notify("TRACE", "CAPTCHA_ARMED")
	url := fmt.tprintf("https://krunker.io/?game=%s", browser.captcha_game)
	if (cast(proc "system" (^COM, ^u16) -> win.HRESULT)browser.view.v[5])(browser.view, raw_data(win.utf8_to_utf16(url))) < 0 { fail("HELPER_FAILED") }
	return 0
}
navigation_starting :: proc "system" (this: rawptr, sender, args: ^COM) -> win.HRESULT {
	context = runtime.default_context()
	browser.navigation += 1
	browser.last_script_diagnostic = ""
	notify("TRACE", access.official_source(get_text(args, 3)) ? "NAVIGATING_OFFICIAL" : "NAVIGATING_LOGIN")
	// Login redirects may leave the official origin. They receive no native token bridge.
	return 0
}
popup_requested :: proc "system" (this: rawptr, sender, args: ^COM) -> win.HRESULT {
	context = runtime.default_context()
	uri := get_text(args, 3)
	(cast(proc "system" (^COM, win.BOOL) -> win.HRESULT)args.v[6])(args, true)
	if strings.has_prefix(uri, "https://") {
		show()
		wide := win.utf8_to_utf16(uri)
		(cast(proc "system" (^COM, ^u16) -> win.HRESULT)sender.v[5])(sender, raw_data(wide))
	}
	return 0
}
script_completed :: proc "system" (this: rawptr, result: win.HRESULT, data: ^u16) -> win.HRESULT {
	context = runtime.default_context()
	browser.executing = false
	if browser.done || browser.executing_navigation != browser.navigation { return 0 }
	if result < 0 || data == nil { trace_script("SCRIPT_FAILED"); return 0 }
	if !access.official_source(get_text(browser.view, 4)) { return 0 }
	count := 0
	for count < access.MAX_MESSAGE && (cast([^]u16)data)[count] != 0 { count += 1 }
	if count >= access.MAX_MESSAGE { fail("BAD_TOKEN"); return 0 }
	text := win.utf16_to_utf8((cast([^]u16)data)[:count]) or_else ""
	value, err := json.parse_string(text)
	if err != .None { trace_script("SCRIPT_INVALID_RESULT"); return 0 }
	defer json.destroy_value(value)
	object, valid := value.(json.Object)
	if !valid { trace_script("SCRIPT_INVALID_RESULT"); return 0 }
	state, ok := object["state"].(json.String)
	if !ok { trace_script("SCRIPT_INVALID_RESULT"); return 0 }
	changed := trace_script(string(state))
	if browser.captcha {
		switch string(state) {
		case "CAPTCHA_ASSIGNMENT":
			assignment, valid := object["assignment"].(json.String)
			if !valid || len(string(assignment)) == 0 { fail("CAPTCHA_SETUP_FAILED"); return 0 }
			notify("STATUS", "CAPTCHA_ASSIGNMENT")
			notify("ASSIGNMENT", string(assignment))
			browser.done = true
		case "CAPTCHA_READY":
			token, valid := object["token"].(json.String)
			if !valid || !access.captcha_token_valid(string(token)) { fail("CAPTCHA_BAD_TOKEN"); return 0 }
			notify("CAPTCHA", string(token)); browser.done = true
		case "CAPTCHA_BAD_TOKEN", "CAPTCHA_NO_CHALLENGE", "CAPTCHA_LOGIN_REQUIRED", "CAPTCHA_SOCKET_MISMATCH": fail(string(state))
		case "CAPTCHA_WRONG_INVITE": fail("CAPTCHA_SETUP_FAILED")
		}
		return 0
	}
	browser.waiting_for_login = state == "WAIT_LOGIN" || state == "WAIT_TOKEN" || state == "WAIT_STORAGE" || state == "GUEST_TOKEN"
	switch string(state) {
	case "SDK_AVAILABLE": browser.sdk_seen = true; notify("STATUS", "SDK_AVAILABLE"); browser.done = true
	case "READY":
		browser.sdk_seen = true
		token, valid := object["token"].(json.String)
		if !valid || !access.usable(string(token), time.time_to_unix(time.now())) { fail("BAD_TOKEN"); return 0 }
		_ = os.write_entire_file(browser.session_path, []byte{1})
		notify("TOKEN", string(token)); browser.done = true
	case "SESSION_REJECTED":
		browser.sdk_seen, browser.rejected = true, true
		show()
		if changed { notify("STATUS", "SESSION_REJECTED") }
	case "PENDING": browser.sdk_seen = true
	case "WAIT_LOGIN", "WAIT_TOKEN": show()
	case "GUEST_TOKEN":
		show()
		if changed { notify("STATUS", "GUEST_TOKEN") }
	case "WAIT_STORAGE": // Let the page finish its storage write without blocking the helper's event loop.
	case "STORAGE_UNAVAILABLE": fail("STORAGE_UNAVAILABLE")
	case "BAD_TOKEN": fail("BAD_TOKEN")
	}
	return 0
}

main :: proc() {
	browser.probe = len(os.args) > 1 && os.args[1] == "--probe"
	browser.input, browser.output = win.GetStdHandle(win.STD_INPUT_HANDLE), win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	request: access.Message
	if !browser.probe {
		// Parent writes one small request before launch returns. No browser is created without it.
		for {
			message, ready, alive := access.receive(browser.input, &browser.buffer)
			if !alive { return }
			if ready { request = message; break }
			time.sleep(10*time.Millisecond)
		}
		if request.id == 0 || (request.kind != "JOIN" && request.kind != "REFRESH" && request.kind != "CAPTCHA") { return }
		browser.id = request.id
		browser.captcha = request.kind == "CAPTCHA"
		if browser.captcha {
			if !access.captcha_game_valid(request.value) { fail("CAPTCHA_SETUP_FAILED"); return }
			browser.captcha_game = request.value
		}
	}
	defer delete(request.kind); defer delete(request.value)
	defer delete(browser.buffer)
	notify("TRACE", "HELPER_STARTED")
	if win.CoInitializeEx(nil, .APARTMENTTHREADED) < 0 { fail("HELPER_FAILED"); return }
	defer win.CoUninitialize()
	directory, err := os.get_executable_directory(context.temp_allocator)
	if err != nil { fail("LOADER_MISSING"); return }
	loader_path := win.utf8_to_utf16(fmt.tprintf("%s\\WebView2Loader.dll", directory))
	loader := win.LoadLibraryExW(cast(cstring16)raw_data(loader_path), nil, {.LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR, .LOAD_LIBRARY_SEARCH_SYSTEM32})
	if loader == nil { fail("LOADER_MISSING"); return }
	defer win.FreeLibrary(loader)
	version_fn := cast(proc "system" (^u16, ^^u16) -> win.HRESULT)win.GetProcAddress(loader, "GetAvailableCoreWebView2BrowserVersionString")
	create_fn := cast(proc "system" (^u16, ^u16, rawptr, ^Handler) -> win.HRESULT)win.GetProcAddress(loader, "CreateCoreWebView2EnvironmentWithOptions")
	if version_fn == nil || create_fn == nil { fail("LOADER_MISSING"); return }
	notify("TRACE", "LOADER_READY")
	version: ^u16
	if version_fn(nil, &version) < 0 { fail("RUNTIME_MISSING"); return }
	win.CoTaskMemFree(version)
	notify("TRACE", "RUNTIME_READY")
	root := access.root_path(); defer delete(root)
	if len(root) == 0 { fail("PROFILE_FAILED"); return }
	profile := fmt.tprintf("%s\\Browser", root)
	// Probes use a separate profile and never call the token method.
	if browser.probe { profile = fmt.tprintf("%s\\BrowserProbe", directory) }
	browser.session_path = fmt.aprintf("%s\\krodin-session", profile)
	defer delete(browser.session_path)
	browser.remembered = os.is_file(browser.session_path)
	first := !browser.remembered
	notify("TRACE", first ? "PROFILE_NEW" : "PROFILE_REMEMBERED")
	os.make_directory(root)
	init_handler(&env_handler, &env_vtable, win.L("{4e8a3389-c9d8-4bd2-b6b5-124fee6cc14d}"), rawptr(environment_ready))
	init_handler(&controller_handler, &controller_vtable, win.L("{6c4819f3-c9b7-4260-8127-c9f5bde7f68c}"), rawptr(controller_ready))
	init_handler(&script_handler, &script_vtable, win.L("{49511172-cc67-4bca-9923-137112f4c4cc}"), rawptr(script_completed))
	init_handler(&navigation_handler, &navigation_vtable, win.L("{9adbe429-f36d-432b-9ddc-f8881fbd76e3}"), rawptr(navigation_starting))
	init_handler(&popup_handler, &popup_vtable, win.L("{d4c185fe-c81c-4989-97af-2d3fa7ab5651}"), rawptr(popup_requested))
	init_handler(&install_handler, &install_vtable, win.L("{b99369f3-9b11-47b5-bc6f-8e7895fcea17}"), rawptr(handoff_installed))
	instance := win.HANDLE(win.GetModuleHandleW(nil))
	class := win.WNDCLASSEXW{cbSize = size_of(win.WNDCLASSEXW), lpfnWndProc = window_proc, hInstance = instance, lpszClassName = win.L("KrodinBrowserAccess")}
	if win.RegisterClassExW(&class) == 0 { fail("HELPER_FAILED"); return }
	browser.window = win.CreateWindowExW(0, class.lpszClassName, win.L("Krodin - Krunker browser access"), win.WS_OVERLAPPEDWINDOW, win.CW_USEDEFAULT, win.CW_USEDEFAULT, 1100, 800, nil, nil, instance, nil)
	if browser.window == nil { fail("HELPER_FAILED"); return }
	if browser.captcha { win.SetWindowTextW(browser.window, win.L("Krodin - Verification for native Join")) }
	defer win.DestroyWindow(browser.window)
	if first || request.kind != "REFRESH" || browser.probe { show() }
	if create_fn(nil, raw_data(win.utf8_to_utf16(profile)), nil, &env_handler) < 0 { fail("PROFILE_FAILED"); return }
	defer {
		if browser.controller != nil { (cast(proc "system" (^COM) -> win.HRESULT)browser.controller.v[24])(browser.controller) }
		release_com(browser.view); release_com(browser.controller)
	}
	browser.started = time.now()
	last_poll := time.Time{}
	for !browser.done {
		message: win.MSG
		for win.PeekMessageW(&message, nil, 0, 0, win.PM_REMOVE) {
			win.TranslateMessage(&message); win.DispatchMessageW(&message)
		}
		if !browser.probe {
			message, ready, alive := access.receive(browser.input, &browser.buffer)
			if !alive { break }
			if ready {
				cancel := message.id == browser.id && message.kind == "CANCEL"
				delete(message.kind); delete(message.value)
				if cancel { notify("ERROR", "CANCELLED"); break }
			}
		}
		elapsed := time.since(browser.started)
		if elapsed > 180*time.Second { fail(browser.rejected ? "SESSION_REJECTED" : "TIMEOUT"); break }
		if !browser.captcha && elapsed > 45*time.Second && (browser.probe || browser.remembered) && !browser.sdk_seen && !browser.waiting_for_login && (browser.view == nil || access.official_source(get_text(browser.view, 4))) { fail("SDK_UNAVAILABLE"); break }
		if elapsed > 12*time.Second { show() }
		if browser.view != nil && !browser.executing && time.since(last_poll) > 500*time.Millisecond && access.official_source(get_text(browser.view, 4)) {
			script := fmt.tprintf("window.__krodinProbeOnly = %s;\n%s", browser.probe ? "true" : "false", string(#load("auth.js")))
			if browser.captcha { script = `(() => { const s = window.__krodinCaptchaHandoff; return s ? {state:s.state, token:s.token, assignment:s.assignment || ''} : {state:'WAIT_CAPTCHA'}; })()` }
			browser.executing, browser.executing_navigation = true, browser.navigation
			hr := (cast(proc "system" (^COM, ^u16, ^Handler) -> win.HRESULT)browser.view.v[29])(browser.view, raw_data(win.utf8_to_utf16(script)), &script_handler)
			if hr < 0 { browser.executing = false; trace_script("SCRIPT_FAILED") }
			last_poll = time.now()
		}
		free_all(context.temp_allocator)
		time.sleep(10*time.Millisecond)
	}
	browser.done = true
}
