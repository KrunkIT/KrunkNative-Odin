package main

import "core:strings"
import "core:fmt"
import "core:time"
import "core:encoding/json"
import "core:net"
import glfw "vendor:glfw"
import access "../browser_access"
import shared "../shared"
import kproto "../krunker"

Access_Status :: enum { IDLE, PENDING, READY, ERROR }
Client_Access :: struct {
	status: Access_Status,
	request: u64,
	log_request: u64,
	token: string,
	assignment_url: string,
	captcha_token: string,
	captcha_pending, captcha_retried: bool,
	from_browser, retried, visible: bool,
	join_after_access: bool,
	started: time.Time,
	child: access.Child,
}

client_access_log :: proc(state: ^Client_Access, text: string) {
	elapsed := state.log_request > 0 ? time.duration_milliseconds(time.since(state.started)) : 0.0
	kproto.network_log("auth", fmt.tprintf("[request=%d +%.1fms] %s", state.log_request, elapsed, text))
}

client_access_browser_link :: proc(link: ^shared.Join_Link) -> bool {
	return link.scheme == "http" || link.scheme == "https" || link.scheme == "game"
}

client_access_cancel :: proc(client: ^Client) {
	if client.access.status == .PENDING {
		client_access_log(&client.access, "Request revoked and helper pipes closed; late replies cannot join.")
	}
	client.access.request += 1
	client.access.status, client.access.visible = .IDLE, false
	client.access.join_after_access = false
	client.access.captcha_pending = false
	delete(client.access.captcha_token); client.access.captcha_token = ""
	when ODIN_OS == .Windows { access.stop(&client.access.child, client.access.request-1) }
}

client_browser_start :: proc(state: ^Client_Access) -> bool {
	when ODIN_OS == .Windows { return access.start(&state.child, state.request, state.join_after_access) }
	else { return false }
}
client_browser_poll :: proc(state: ^Client_Access) -> (access.Message, bool, bool) {
	when ODIN_OS == .Windows { return access.receive(state.child.output, &state.child.buffer) }
	else { return {}, false, false }
}

client_access_begin :: proc(client: ^Client, start_browser: proc(^Client_Access) -> bool = client_browser_start, join_after_access: bool = true) -> bool {
	state := &client.access
	if state.status == .PENDING { client_access_log(state, "Duplicate access request ignored; existing request is pending."); return true }
	state.request += 1
	delete(state.assignment_url); state.assignment_url = ""
	state.log_request = state.request
	state.join_after_access = join_after_access
	state.status, state.visible, state.started = .PENDING, false, time.now()
	client_access_log(state, join_after_access ? "Join needs browser access; starting helper with the pending invite retained." : "Login requested; opening browser without joining a lobby.")
	krunker_ws_set_status(client, "Preparing browser access…")
	if !start_browser(state) {
		client_access_log(state, "Helper launch failed. Check krodin_browser.exe beside the client.")
		client_access_cancel(client)
		state.status = .ERROR
		krunker_ws_set_status(client, "Could not start krodin_browser.exe. Rebuild or reinstall the Windows package, then retry Join.")
		return false
	}
	client_access_log(state, "Helper process started; waiting for browser initialization.")
	return true
}

// The page builds the URL after SDK renewal. Validate it, then preserve it
// exactly rather than replacing its token with an older native cache entry.
client_access_assignment_url :: proc(value: string) -> (string, string, bool) {
	parsed, err := json.parse_string(value, parse_integers = true)
	if err != .None do return "", "", false
	defer json.destroy_value(parsed)
	object, ok := parsed.(json.Object)
	if !ok do return "", "", false
	host, host_ok := object["host"].(json.String)
	client_id, client_ok := object["clientId"].(json.String)
	game_id, game_ok := object["gameId"].(json.String)
	url, url_ok := object["websocketUrl"].(json.String)
	username, username_ok := object["usernamePresent"].(json.Boolean)
	if !host_ok || !client_ok || !game_ok || !url_ok || !username_ok || !bool(username) || len(host) == 0 || len(client_id) == 0 || len(client_id) > 4096 || len(url) > 49152 { return "", "", false }
	if !strings.has_suffix(string(host), ".krunker.io") || !access.captcha_game_valid(string(game_id)) { return "", "", false }
	for b in string(host) { if !(b >= 'a' && b <= 'z' || b >= '0' && b <= '9' || b == '-' || b == '.') { return "", "", false } }
	for b in string(url) { if b <= 32 || b > 126 || b == '\\' || b == '#' { return "", "", false } }
	scheme, authority, path, query, fragment := net.split_url(string(url))
	defer delete(query)
	if scheme != "wss" || authority != string(host) || path != "/ws" || len(fragment) != 0 { return "", "", false }
	// Reject duplicate/ambiguous fields before using the parser's query map.
	query_start := strings.index(string(url), "?")
	if query_start < 0 { return "", "", false }
	fields := strings.split(string(url)[query_start+1:], "&"); defer delete(fields)
	if len(fields) != len(query) { return "", "", false }
	for key in query {
		if key != "gameId" && key != "clientKey" && key != "at" && key != "clientUID" && key != "bpt" && key != "tc" && key != "dm" { return "", "", false }
	}
	game, valid_game := net.percent_decode(query["gameId"]); defer delete(game)
	key, valid_key := net.percent_decode(query["clientKey"]); defer delete(key)
	token, valid_token := net.percent_decode(query["at"])
	if !valid_game || !valid_key || !valid_token || game != string(game_id) || key != string(client_id) || !access.usable(token, time.time_to_unix(time.now())) {
		delete(token); return "", "", false
	}
	return strings.clone(string(url)), token, true
}
client_browser_captcha_start :: proc(client: ^Client) -> bool {
	when ODIN_OS == .Windows {
		return access.start(&client.access.child, client.access.request, false, "CAPTCHA", client.join_link.game_id)
	} else { return false }
}
client_captcha_begin :: proc(client: ^Client, start_browser: proc(^Client) -> bool = client_browser_captcha_start) -> bool {
	state := &client.access
	if state.status == .PENDING { return true }
	if state.captcha_retried || !access.captcha_game_valid(client.join_link.game_id) { return false }
	state.captcha_retried, state.captcha_pending = true, true
	state.request += 1
	state.log_request, state.join_after_access = state.request, true
	state.status, state.started = .PENDING, time.now()
	client_access_log(state, "Native matchmaking requires verification; opening the official page for this invite. The assigned game socket will be handed to the native client before opening.")
	krunker_ws_set_status(client, "Preparing verification handoff...")
	if !start_browser(client) {
		client_access_cancel(client); state.status = .ERROR
		krunker_ws_set_status(client, "Could not start the challenge helper. Rebuild the Windows browser helper and retry Join.")
		return false
	}
	return true
}

client_access_login :: proc(client: ^Client, start_browser: proc(^Client_Access) -> bool = client_browser_start) -> bool {
	if client.join_queued > 0 || client.access.status == .PENDING { return false }
	client.access.retried = false
	return client_access_begin(client, start_browser, join_after_access = false)
}

// Startup and direct connections never touch the cache.
client_browser_load :: proc() -> string {
	when ODIN_OS == .Windows { return access.cache_load() }
	else { return "" }
}
client_access_select :: proc(client: ^Client, now: i64, load_browser: proc() -> string = client_browser_load, load_fallback: proc() -> (string, bool) = krunker_ws_access_token) -> bool {
	state := &client.access
	memory_state := access.token_state(state.token, now)
	if state.from_browser && memory_state == .READY {
		client_access_log(state, "Reusing browser access from memory; expiry is more than 60 seconds away.")
		return true
	}
	if memory_state == .GUEST {
		client_access_log(state, "Ignoring guest JWT in memory; account access is required.")
	}
	{
		cached := load_browser()
		cached_state := access.token_state(cached, now)
		if cached_state == .READY {
			delete(state.token); state.token, state.from_browser, state.status = cached, true, .READY
			client_access_log(state, "Loaded usable browser access from encrypted DPAPI cache; helper not needed.")
			return true
		}
		if cached_state == .GUEST { client_access_log(state, "Ignoring guest JWT in encrypted cache; account access is required.") }
		delete(cached)
	}
	when ODIN_OS == .Windows {
		client_access_log(state, "Environment/.env token fallback disabled; this Windows build uses browser access only.")
	} else {
		client_access_log(state, "No usable browser access in memory or encrypted cache; checking environment/.env fallback.")
		fallback, ok := load_fallback()
		fallback_state := access.token_state(fallback, now)
		if ok && fallback_state == .READY {
			delete(state.token); state.token, state.from_browser, state.status = fallback, false, .READY
			client_access_log(state, "Using environment/.env access; helper not needed.")
			return true
		}
		if fallback_state == .GUEST { client_access_log(state, "Ignoring guest JWT in environment/.env fallback; account access is required.") }
		delete(fallback)
	}
	delete(state.token); state.token = ""
	client_access_log(state, "No usable access available; browser login or renewal is required.")
	return false
}

client_browser_invalidate :: proc() {
	when ODIN_OS == .Windows {
		if !access.cache_invalidate() { kproto.network_log("auth", "Could not delete the invalid cached token. Check permissions under LOCALAPPDATA/Krodin.") }
	}
}
client_browser_save :: proc(token: string) -> bool { when ODIN_OS == .Windows { return access.cache_save(token) } else { return false } }

client_access_retry :: proc(client: ^Client, rejected: bool, start_browser: proc(^Client_Access) -> bool = client_browser_start, invalidate: proc() = client_browser_invalidate) -> bool {
	if !rejected { return false }
	client_access_log(&client.access, "Server explicitly rejected access; invalidating the token and encrypted cache.")
	delete(client.access.token); client.access.token = ""
	invalidate()
	if client.access.retried {
		client_access_log(&client.access, "Authentication retry already used; stopping without another retry.")
		client.access.status = .ERROR; return false
	}
	client.access.retried = true
	client_access_log(&client.access, "Requesting browser access for the single permitted authentication retry.")
	return client_access_begin(client, start_browser)
}

client_access_tick :: proc(client: ^Client, poll_browser: proc(^Client_Access) -> (access.Message, bool, bool) = client_browser_poll, connect: proc(^Client, ^shared.Join_Link) -> bool = krunker_ws_connect_ready, persist: proc(string) -> bool = client_browser_save) {
	state := &client.access
	if state.status != .PENDING { return }
	message, ready, alive := poll_browser(state)
	if ready {
		defer delete(message.kind); defer delete(message.value)
		if message.id != state.request { client_access_log(state, "Stale helper reply ignored."); return }
		switch message.kind {
		case "TRACE":
			client_access_log(state, access.diagnostic_text(message.value))
		case "STATUS":
			client_access_log(state, access.status_text(state.captcha_pending && message.value == "VISIBLE" ? "CAPTCHA_VISIBLE" : message.value))
			if message.value == "VISIBLE" {
				state.visible = true
				if client.window != nil { glfw.SetInputMode(client.window, glfw.CURSOR, glfw.CURSOR_NORMAL) }
				client.mouse_state.locked = false
			}
			krunker_ws_set_status(client, access.status_text(state.captcha_pending && message.value == "VISIBLE" ? "CAPTCHA_VISIBLE" : message.value))
		case "ASSIGNMENT":
			if !state.captcha_pending || !state.join_after_access {
				client_access_log(state, "Socket handoff received outside a verification Join; stopping without connecting.")
				client_access_cancel(client); state.status = .ERROR
				krunker_ws_set_status(client, access.status_text("CAPTCHA_SETUP_FAILED")); return
			}
			assignment_url, token, valid := client_access_assignment_url(message.value)
			if !valid {
				client_access_log(state, "Browser assignment failed native validation; contents omitted.")
				client_access_cancel(client); state.status = .ERROR
				krunker_ws_set_status(client, access.status_text("CAPTCHA_SETUP_FAILED")); return
			}
			delete(state.assignment_url); state.assignment_url = assignment_url
			kproto.network_log_secret(token)
			_, _, _, query, _ := net.split_url(assignment_url)
			defer delete(query)
			for key in ([]string{"at", "clientKey", "clientUID", "bpt"}) {
				kproto.network_log_secret(query[key])
				decoded, ok := net.percent_decode(query[key])
				if ok { kproto.network_log_secret(decoded) }
				delete(decoded)
			}
			client_access_log(state, fmt.tprintf("Socket handoff v2: exact browser URL captured before connection; token_matches_cache=%v clientUID_present=%v bpt_present=%v tc_present=%v dm_present=%v. Credentials omitted.", token == state.token, strings.contains(assignment_url, "&clientUID="), strings.contains(assignment_url, "&bpt="), strings.contains(assignment_url, "&tc="), strings.contains(assignment_url, "&dm=")))
			delete(state.token); state.token, state.from_browser = token, true
			if !persist(state.token) { client_access_log(state, "Handoff access accepted; encrypted cache could not be updated.") }
			client_access_cancel(client)
			state.status = .READY
			krunker_ws_set_status(client, "Browser match found; opening native connection...")
			connect(client, &client.join_link)
		case "CAPTCHA":
			if !state.captcha_pending || !access.captcha_token_valid(message.value) {
				client_access_cancel(client); state.status = .ERROR
				krunker_ws_set_status(client, access.status_text("CAPTCHA_BAD_TOKEN")); return
			}
			proof := strings.clone(message.value)
			kproto.network_log_secret(proof)
			client_access_cancel(client)
			state.captcha_token, state.status = proof, .READY
			client_access_log(state, "Challenge proof received over private pipe; helper closing. Retrying native matchmaking once; proof omitted.")
			krunker_ws_set_status(client, "Verification received; retrying native matchmaking...")
			connect(client, &client.join_link)
		case "TOKEN":
			if state.captcha_pending {
				client_access_cancel(client); state.status = .ERROR
				krunker_ws_set_status(client, access.status_text("CAPTCHA_SETUP_FAILED")); return
			}
			token_state := access.token_state(message.value, time.time_to_unix(time.now()))
			if token_state != .READY {
				client_access_log(state, token_state == .GUEST ? access.diagnostic_text("GUEST_TOKEN") : "Helper token rejected by native expiry check; token contents omitted.")
				client_access_cancel(client); state.status = .ERROR
				krunker_ws_set_status(client, access.status_text(token_state == .GUEST ? "GUEST_TOKEN" : "BAD_TOKEN")); return
			}
			delete(state.token); state.token = strings.clone(message.value)
			client_access_log(state, "Browser access passed native expiry and guest-platform checks; token contents omitted.")
			state.from_browser = true
			join_after_access := state.join_after_access
			client_access_cancel(client)
			state.status = .READY
			when ODIN_OS == .Windows {
				if !persist(state.token) { client_access_log(state, "Browser access ready; encrypted cache could not be saved. Access will be requested again after restart.") }
				else { client_access_log(state, "Access saved to encrypted DPAPI cache; refresh credentials remain in the browser.") }
			}
			if join_after_access {
				client_access_log(state, "Access ready; continuing the original invite through lobby resolution.")
				// join_link is the original parsed invite, independent of later edits to the field.
				connect(client, &client.join_link)
			} else {
				client_access_log(state, "Login complete; waiting for an explicit Join.")
				krunker_ws_set_status(client, "Login complete. You can now join a lobby.")
			}
		case "ERROR":
			client_access_log(state, access.status_text(message.value))
			client_access_cancel(client); state.status = .ERROR
			krunker_ws_set_status(client, access.status_text(message.value))
		case:
			client_access_log(state, "Unexpected helper message; stopping browser access (contents omitted).")
			client_access_cancel(client); state.status = .ERROR
			krunker_ws_set_status(client, access.status_text("HELPER_FAILED"))
		}
		return
	}
	if !alive || time.since(state.started) > 190*time.Second {
		client_access_log(state, alive ? "Browser access exceeded the request timeout." : "Helper pipe closed before access was ready; helper may have exited.")
		client_access_cancel(client); state.status = .ERROR
		krunker_ws_set_status(client, access.status_text(alive ? "TIMEOUT" : "HELPER_FAILED"))
	}
}

client_access_forget :: proc(client: ^Client) {
	client_access_log(&client.access, "Forget browser session requested; clearing access cache and Krodin browser profile.")
	client_access_cancel(client)
	client.join_queued = 0
	delete(client.access.token); client.access.token = ""
	delete(client.access.assignment_url); client.access.assignment_url = ""
	client.access.from_browser, client.access.retried = false, false
	when ODIN_OS == .Windows {
		if !access.forget() {
			client_access_log(&client.access, "Browser session could not be cleared; close other Krodin browser windows and retry.")
			krunker_ws_set_status(client, "Could not clear the browser profile. Close other Krodin browser windows, wait a moment, then select Forget browser session again.")
			return
		}
	}
	client_access_log(&client.access, "Browser session and encrypted access cache cleared.")
	krunker_ws_set_status(client, "Browser session forgotten. Join will request new access.")
}
