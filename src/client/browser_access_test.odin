package main

import "core:encoding/base64"
import "core:fmt"
import "core:strings"
import "core:testing"
import "core:time"
import access "../browser_access"
import shared "../shared"
import menuui "../menu"
import kproto "../krunker"

when ODIN_TEST {
	access_test_token :: proc(seconds: i64 = 3600) -> string {
		payload := fmt.tprintf("%s%d%s", `{"exp":`, time.time_to_unix(time.now())+seconds, `}`)
		encoded := base64.encode(transmute([]byte)payload, base64.ENC_URL_TABLE, options = {.No_Padding}); defer delete(encoded)
		return fmt.aprintf("eyJhbGciOiJub25lIn0.%s.fixture", string(encoded))
	}
	access_test_start :: proc(state: ^Client_Access) -> bool { return true }
	access_test_guest_token :: proc() -> string {
		payload := fmt.tprintf("%s%d%s", `{"exp":`, time.time_to_unix(time.now())+3600, `,"extra":{"platform":"anonymous","verified":true}}`)
		encoded := base64.encode(transmute([]byte)payload, base64.ENC_URL_TABLE, options = {.No_Padding}); defer delete(encoded)
		return fmt.aprintf("eyJhbGciOiJub25lIn0.%s.fixture", string(encoded))
	}
	access_test_guest_fallback :: proc() -> (string, bool) { return access_test_guest_token(), true }
	access_test_guest_poll :: proc(state: ^Client_Access) -> (access.Message, bool, bool) {
		return access.Message{state.request, strings.clone("TOKEN"), access_test_guest_token()}, true, true
	}
	access_test_login_start :: proc(state: ^Client_Access) -> bool { return !state.join_after_access }
	access_test_fail_start :: proc(state: ^Client_Access) -> bool { return false }
	access_test_load :: proc() -> string { return access_test_token() }
	access_test_empty :: proc() -> string { return "" }
	access_test_expired :: proc() -> string { return strings.clone("e30.eyJleHAiOjF9.fixture") }
	access_test_fallback :: proc() -> (string, bool) { return access_test_token(), true }
	access_test_no_fallback :: proc() -> (string, bool) { return "", false }
	access_test_forbidden_load :: proc() -> string { panic("usable in-memory browser token should be reused") }
	access_test_forbidden_fallback :: proc() -> (string, bool) { panic("browser cache must take precedence") }
	access_test_invalidate :: proc() {}
	access_test_persist :: proc(token: string) -> bool { return access.usable(token, time.time_to_unix(time.now())) }
	access_test_connect :: proc(client: ^Client, link: ^shared.Join_Link) -> bool {
		client.net_input_seq += 1
		krunker_ws_set_status(client, link.raw)
		return true
	}
	access_test_poll :: proc(state: ^Client_Access) -> (access.Message, bool, bool) {
		return access.Message{state.request, strings.clone("TOKEN"), access_test_token()}, true, true
	}
	access_test_assignment_poll :: proc(state: ^Client_Access) -> (access.Message, bool, bool) {
		token := access_test_token(7200); defer delete(token)
		value := fmt.aprintf("%s%s%s", `{"host":"lobby-fixture.krunker.io","clientId":"fixture-client","gameId":"FRA:fixture","usernamePresent":true,"websocketUrl":"wss://lobby-fixture.krunker.io/ws?gameId=FRA:fixture&clientKey=fixture-client&at=`, token, `&clientUID=fixture-uid&tc=fixture-tc&dm=fixture-dm&bpt=fixture-bypass"}`)
		return access.Message{state.request, strings.clone("ASSIGNMENT"), value}, true, true
	}
	access_test_assignment_connect :: proc(client: ^Client, link: ^shared.Join_Link) -> bool {
		expected := "wss://lobby-fixture.krunker.io/ws?gameId=FRA:fixture&clientKey=fixture-client&at="
		if !strings.has_prefix(client.access.assignment_url, expected) { panic("browser socket URL must be preserved exactly") }
		if !strings.contains(client.access.assignment_url, fmt.tprintf("&at=%s&clientUID=fixture-uid&tc=fixture-tc&dm=fixture-dm&bpt=fixture-bypass", client.access.token)) { panic("socket must use the browser-selected token and optional parameters") }
		if link.game_id != "FRA:original" { panic("assignment handoff must continue the original invite") }
		client.net_input_seq += 1
		return true
	}
	access_test_stale :: proc(state: ^Client_Access) -> (access.Message, bool, bool) {
		return access.Message{state.request-1, strings.clone("TOKEN"), access_test_token()}, true, true
	}
	access_test_closed :: proc(state: ^Client_Access) -> (access.Message, bool, bool) { return {}, false, false }
	access_test_trace :: proc(state: ^Client_Access) -> (access.Message, bool, bool) {
		return access.Message{state.request, strings.clone("TRACE"), strings.clone("WAIT_LOGIN")}, true, true
	}
	access_test_captcha_start :: proc(client: ^Client) -> bool { return client.access.captcha_pending && client.access.join_after_access }
	access_test_captcha_poll :: proc(state: ^Client_Access) -> (access.Message, bool, bool) {
		return access.Message{state.request, strings.clone("CAPTCHA"), strings.clone("fixture-proof+/=")}, true, true
	}
	access_test_captcha_stale :: proc(state: ^Client_Access) -> (access.Message, bool, bool) {
		return access.Message{state.request-1, strings.clone("CAPTCHA"), strings.clone("fixture-proof+/=")}, true, true
	}
	access_test_captcha_connect :: proc(client: ^Client, link: ^shared.Join_Link) -> bool {
		if client.access.captcha_token != "fixture-proof+/=" || link.game_id != "FRA:original" { panic("proof and original invite must survive helper shutdown") }
		delete(client.access.captcha_token); client.access.captcha_token = ""
		client.net_input_seq += 1
		return true
	}
	@(test)
	challenge_handoff_continues_original_native_join_once :: proc(t: ^testing.T) {
		defer kproto.network_log_clear_secrets()
		client: Client; defer access_test_cleanup(&client)
		client.join_link, _ = shared.join_link_parse("FRA:original")
		client.access.token = access_test_token()
		testing.expect(t, client_captcha_begin(&client, access_test_captcha_start))
		request := client.access.request
		testing.expect(t, client_captcha_begin(&client, access_test_captcha_start) && client.access.request == request)
		menuui.set_invite(&client.menu, "NY:edited")
		client_access_tick(&client, access_test_captcha_stale, access_test_captcha_connect, access_test_persist)
		testing.expect(t, client.access.status == .PENDING && client.net_input_seq == 0)
		client_access_tick(&client, access_test_captcha_poll, access_test_captcha_connect, access_test_persist)
		testing.expect(t, client.access.status == .READY && client.access.captcha_retried && !client.access.captcha_pending)
		testing.expect(t, client.net_input_seq == 1 && !client.access.retried && len(client.access.token) > 0)
		testing.expect(t, !client_captcha_begin(&client, access_test_captcha_start), "one challenge attempt per Join")
		client_access_tick(&client, access_test_captcha_poll, access_test_captcha_connect, access_test_persist)
		testing.expect(t, client.net_input_seq == 1)
	}
	@(test)
	challenge_cancellation_and_helper_failure_never_continue :: proc(t: ^testing.T) {
		client: Client; defer access_test_cleanup(&client)
		client.join_link, _ = shared.join_link_parse("FRA:original")
		client_captcha_begin(&client, access_test_captcha_start)
		client_access_cancel(&client)
		client_access_tick(&client, access_test_captcha_poll, access_test_captcha_connect, access_test_persist)
		testing.expect(t, client.net_input_seq == 0 && len(client.access.captcha_token) == 0)
		client.access.captcha_retried = false
		client_captcha_begin(&client, access_test_captcha_start)
		client_access_tick(&client, access_test_closed, access_test_captcha_connect, access_test_persist)
		testing.expect(t, client.access.status == .ERROR && !client.access.captcha_pending && client.net_input_seq == 0)
		client.access.captcha_retried = false
		client_captcha_begin(&client, access_test_captcha_start)
		client_access_tick(&client, access_test_poll, access_test_captcha_connect, access_test_persist)
		testing.expect(t, client.access.status == .ERROR && client.net_input_seq == 0, "login token cannot satisfy a challenge request")
	}
	access_test_handoff_http :: proc(url, method, body, stage: string) -> ([dynamic]byte, i64, bool) {
		if stage != "seek-game" { return access_test_http(url, method, body, stage) }
		encoded := kproto.network_url_encode("fixture-proof+/="); defer delete(encoded)
		validation := kproto.network_url_encode("fixture-validation"); defer delete(validation)
		if !strings.contains(url, fmt.tprintf("captchaToken=%s", encoded)) || !strings.contains(url, fmt.tprintf("validationToken=%s", validation)) { panic("native seek must combine browser proof with native validation") }
		result := make([dynamic]byte); append(&result, `{"host":"lobby-fixture.krunker.io","port":3000,"gameId":"FRA:original","clientId":"fixture-key"}`)
		return result, 200, true
	}
	@(test)
	challenge_proof_is_encoded_in_native_seek_and_redacted :: proc(t: ^testing.T) {
		defer kproto.network_log_clear_secrets()
		link, _ := shared.join_link_parse("FRA:original"); defer shared.join_link_free(&link)
		token := access_test_token(); defer delete(token)
		rejected, challenge: bool
		url, ok, _ := krunker_ws_resolve_invite(&link, token, &rejected, access_test_captcha_http, needs_captcha = &challenge)
		delete(url)
		testing.expect(t, !ok && !rejected && challenge)
		url, ok, _ = krunker_ws_resolve_invite(&link, token, &rejected, access_test_handoff_http, captcha = "fixture-proof+/=", needs_captcha = &challenge)
		defer delete(url)
		testing.expect(t, ok && !rejected && !challenge && strings.has_prefix(url, "wss://lobby-fixture.krunker.io/ws?"))
		testing.expect(t, !strings.contains(url, "captchaToken"), "proof only goes to matchmaking, never the game socket")
		safe := kproto.network_log_safe("captchaToken=fixture-unregistered-proof&game=FRA:original"); defer delete(safe)
		testing.expect(t, !strings.contains(safe, "fixture-unregistered-proof") && strings.contains(safe, "FRA:original"))
	}
	@(test)
	browser_assignment_continues_original_native_join_once :: proc(t: ^testing.T) {
		defer kproto.network_log_clear_secrets()
		client: Client; defer access_test_cleanup(&client)
		client.join_link, _ = shared.join_link_parse("FRA:original")
		client.access.token = access_test_token()
		old_token := strings.clone(client.access.token); defer delete(old_token)
		testing.expect(t, client_captcha_begin(&client, access_test_captcha_start))
		request := client.access.request
		client_access_tick(&client, access_test_assignment_poll, access_test_assignment_connect, access_test_persist)
		testing.expect(t, client.access.status == .READY && client.net_input_seq == 1)
		testing.expect(t, client.access.request != request && len(client.access.assignment_url) > 0)
		testing.expect(t, client.access.token != old_token && client.access.from_browser, "handoff replaces stale native access with the browser-selected account token")
		safe := kproto.network_log_safe("server echoed fixture-client fixture-uid fixture-bypass"); defer delete(safe)
		testing.expect(t, !strings.contains(safe, "fixture-client") && !strings.contains(safe, "fixture-uid") && !strings.contains(safe, "fixture-bypass"), "socket credentials must be redacted even outside query fields")
		client_access_tick(&client, access_test_assignment_poll, access_test_assignment_connect, access_test_persist)
		testing.expect(t, client.net_input_seq == 1, "assignment must continue the native join once")
	}
	@(test)
	browser_socket_handoff_cannot_join_after_cancel_or_during_login :: proc(t: ^testing.T) {
		client: Client; defer access_test_cleanup(&client)
		client.join_link, _ = shared.join_link_parse("FRA:original")
		client_captcha_begin(&client, access_test_captcha_start)
		client_access_cancel(&client)
		client_access_tick(&client, access_test_assignment_poll, access_test_assignment_connect, access_test_persist)
		testing.expect(t, client.net_input_seq == 0 && len(client.access.assignment_url) == 0)
		client_access_login(&client, access_test_login_start)
		client_access_tick(&client, access_test_assignment_poll, access_test_assignment_connect, access_test_persist)
		testing.expect(t, client.access.status == .ERROR && client.net_input_seq == 0 && len(client.access.assignment_url) == 0)
	}
	@(test)
	browser_socket_handoff_validates_origin_identity_and_account_access :: proc(t: ^testing.T) {
		token := access_test_token(); defer delete(token)
		guest := access_test_guest_token(); defer delete(guest)
		url := fmt.aprintf("wss://lobby-fixture.krunker.io/ws?gameId=FRA%%3Afixture&clientKey=fixture-client&at=%s&clientUID=fixture-uid", token); defer delete(url)
		for invalid in ([]string{
			"wss://other.invalid/ws?gameId=FRA:fixture&clientKey=fixture-client",
			fmt.tprintf("%s&at=%s", url, token),
			fmt.tprintf("wss://evil@lobby-fixture.krunker.io/ws?gameId=FRA:fixture&clientKey=fixture-client&at=%s", token),
			fmt.tprintf("wss://lobby-fixture.krunker.io:3000/ws?gameId=FRA:fixture&clientKey=fixture-client&at=%s", token),
			fmt.tprintf("wss://lobby-fixture.krunker.io/ws?gameId=NY:other&clientKey=fixture-client&at=%s", token),
			fmt.tprintf("wss://lobby-fixture.krunker.io/ws?gameId=FRA:fixture&clientKey=other-client&at=%s", token),
			fmt.tprintf("wss://lobby-fixture.krunker.io/ws?gameId=FRA:fixture&clientKey=fixture-client&at=%s", guest),
			"wss://lobby-fixture.krunker.io/ws?gameId=FRA:fixture&clientKey=fixture-client&at=e30.eyJleHAiOjF9.fixture",
			fmt.tprintf("%s#fragment", url),
		}) {
			value := fmt.tprintf("%s%s%s", `{"host":"lobby-fixture.krunker.io","clientId":"fixture-client","gameId":"FRA:fixture","usernamePresent":true,"websocketUrl":"`, invalid, `"}`)
			_, _, valid := client_access_assignment_url(value)
			testing.expect(t, !valid, "reject mismatched or unusable socket details")
		}
		for username in ([]string{"true", "false", "null"}) {
			value := fmt.tprintf("%s%s%s%s%s", `{"host":"lobby-fixture.krunker.io","clientId":"fixture-client","gameId":"FRA:fixture","usernamePresent":`, username, `,"websocketUrl":"`, url, `"}`)
			captured, selected, valid := client_access_assignment_url(value)
			defer delete(captured); defer delete(selected)
			testing.expect(t, valid == (username == "true"))
			if valid { testing.expect(t, captured == url && selected == token) }
		}
	}
	access_test_error :: proc(state: ^Client_Access) -> (access.Message, bool, bool) {
		return access.Message{state.request, strings.clone("ERROR"), strings.clone("eyJsecret_token")}, true, true
	}
	access_test_cleanup :: proc(client: ^Client) {
		client_access_cancel(client); delete(client.access.token); delete(client.access.assignment_url)
		delete(client.join_status); delete(client.selection_status)
		shared.join_link_free(&client.join_link)
	}
	@(test)
	browser_diagnostics_do_not_complete_or_replace_pending_join :: proc(t: ^testing.T) {
		client: Client; defer access_test_cleanup(&client)
		testing.expect(t, client_access_begin(&client, access_test_start))
		request := client.access.request
		before := strings.clone(client.join_status); defer delete(before)
		for _ in 0..<3 {
			client_access_tick(&client, access_test_trace, access_test_connect, access_test_persist)
		}
		testing.expect(t, client.access.status == .PENDING && client.access.request == request)
		testing.expect(t, client.net_input_seq == 0 && len(client.access.token) == 0)
		testing.expect(t, client.join_status == before, "helper diagnostics must not overwrite menu status")
		client_access_tick(&client, access_test_poll, access_test_connect, access_test_persist)
		testing.expect(t, client.access.status == .READY && client.net_input_seq == 1)
	}
	@(test)
	browser_token_precedence_and_expiry :: proc(t: ^testing.T) {
		client: Client; defer access_test_cleanup(&client)
		now := time.time_to_unix(time.now())
		testing.expect(t, client_access_select(&client, now, access_test_load, access_test_forbidden_fallback))
		testing.expect(t, client.access.from_browser)
		testing.expect(t, client_access_select(&client, now, access_test_forbidden_load, access_test_forbidden_fallback))
		delete(client.access.token); client.access.token = ""
		when ODIN_OS == .Windows {
			testing.expect(t, !client_access_select(&client, now, access_test_expired, access_test_forbidden_fallback), "Windows must never consult environment fallback")
		} else {
			testing.expect(t, client_access_select(&client, now, access_test_expired, access_test_fallback))
			testing.expect(t, !client.access.from_browser)
		}
		testing.expect(t, !client_access_select(&client, now, access_test_empty, access_test_no_fallback))
		testing.expect(t, len(client.access.token) == 0)
	}
	@(test)
	guest_access_is_rejected_from_memory_cache_fallback_and_helper :: proc(t: ^testing.T) {
		client: Client; defer access_test_cleanup(&client)
		now := time.time_to_unix(time.now())
		client.access.token, client.access.from_browser = access_test_guest_token(), true
		testing.expect(t, !client_access_select(&client, now, access_test_empty, access_test_no_fallback))
		testing.expect(t, len(client.access.token) == 0)
		testing.expect(t, !client_access_select(&client, now, access_test_guest_token, access_test_guest_fallback))
		testing.expect(t, len(client.access.token) == 0)
		when ODIN_OS == .Windows {
			testing.expect(t, !client_access_select(&client, now, access_test_guest_token, access_test_forbidden_fallback), "guest cache must lead to browser login without consulting environment fallback")
		} else {
			testing.expect(t, client_access_select(&client, now, access_test_guest_token, access_test_fallback))
			testing.expect(t, !client.access.from_browser && access.usable(client.access.token, now), "valid fallback can replace a guest browser cache")
		}
		delete(client.access.token); client.access.token = ""
		client_access_begin(&client, access_test_start)
		client_access_tick(&client, access_test_guest_poll, access_test_connect, access_test_persist)
		testing.expect(t, client.access.status == .ERROR && client.net_input_seq == 0)
		testing.expect(t, len(client.access.token) == 0 && strings.contains(client.join_status, "Guest access detected"))
	}
	@(test)
	browser_login_without_invite_prepares_access_without_joining :: proc(t: ^testing.T) {
		client: Client; defer access_test_cleanup(&client)
		// A previous invite must never become a continuation for an explicit Login.
		client.join_link, _ = shared.join_link_parse("FRA:previous")
		client.local_practice = true
		testing.expect(t, len(menuui.invite(&client.menu)) == 0)
		testing.expect(t, client_access_login(&client, access_test_login_start))
		request := client.access.request
		testing.expect(t, !client_access_login(&client, access_test_login_start) && client.access.request == request)
		menu_apply_action(&client, {kind = .JOIN_LINK})
		testing.expect(t, client.join_queued == 0)
		client_access_tick(&client, access_test_poll, access_test_connect, access_test_persist)
		testing.expect(t, client.access.status == .READY && client.net_input_seq == 0 && client.local_practice)
		testing.expect(t, client.join_status == "Login complete. You can now join a lobby.")
		testing.expect(t, client_access_select(&client, time.time_to_unix(time.now()), access_test_forbidden_load, access_test_forbidden_fallback), "later Join reuses the prepared token")
		client_access_tick(&client, access_test_poll, access_test_connect, access_test_persist)
		testing.expect(t, client.net_input_seq == 0)
	}
	@(test)
	browser_standalone_login_cancellation_revokes_late_results :: proc(t: ^testing.T) {
		client: Client; defer access_test_cleanup(&client)
		testing.expect(t, client_access_login(&client, access_test_login_start))
		menu_apply_action(&client, {kind = .CANCEL_JOIN})
		client_access_tick(&client, access_test_poll, access_test_connect, access_test_persist)
		testing.expect(t, client.access.status == .IDLE && len(client.access.token) == 0 && client.net_input_seq == 0)
		testing.expect(t, client.join_status == "Login cancelled.")
		client.join_queued = 2
		testing.expect(t, !client_access_login(&client, access_test_login_start), "Login cannot replace a queued Join")
		client.join_queued = 0
		testing.expect(t, !client_access_login(&client, access_test_fail_start) && client.access.status == .ERROR)
	}
	@(test)
	browser_join_continues_original_invite_once :: proc(t: ^testing.T) {
		client: Client; defer access_test_cleanup(&client)
		client.join_link, _ = shared.join_link_parse("FRA:original")
		testing.expect(t, client_access_begin(&client, access_test_start))
		request := client.access.request
		menuui.set_invite(&client.menu, "FRA:edited")
		testing.expect(t, client_access_begin(&client, access_test_start) && client.access.request == request)
		menu_apply_action(&client, {kind = .JOIN_LINK})
		testing.expect(t, client.join_queued == 0 && client.access.request == request, "duplicate Join is suppressed")
		client_access_tick(&client, access_test_stale, access_test_connect, access_test_persist)
		testing.expect(t, client.access.status == .PENDING && client.net_input_seq == 0)
		client_access_tick(&client, access_test_poll, access_test_connect, access_test_persist)
		testing.expect(t, client.access.status == .READY && client.net_input_seq == 1 && client.join_status == "FRA:original")
		client_access_tick(&client, access_test_poll, access_test_connect, access_test_persist)
		testing.expect(t, client.net_input_seq == 1)
	}
	@(test)
	browser_cancel_and_helper_failure_never_join :: proc(t: ^testing.T) {
		client: Client; defer access_test_cleanup(&client)
		client_access_begin(&client, access_test_start)
		menu_apply_action(&client, {kind = .CANCEL_JOIN})
		client_access_tick(&client, access_test_poll, access_test_connect, access_test_persist)
		testing.expect(t, client.net_input_seq == 0 && client.access.status == .IDLE)
		client_access_begin(&client, access_test_start)
		client_access_tick(&client, access_test_closed, access_test_connect, access_test_persist)
		testing.expect(t, client.net_input_seq == 0 && client.access.status == .ERROR)
		testing.expect(t, !client_access_begin(&client, access_test_fail_start) && client.access.status == .ERROR)
		client_access_begin(&client, access_test_start)
		client_access_tick(&client, access_test_error, access_test_connect, access_test_persist)
		testing.expect(t, client.access.status == .ERROR && !strings.contains(client.join_status, "eyJsecret"))
	}
	@(test)
	browser_authentication_retries_only_once :: proc(t: ^testing.T) {
		client: Client; defer access_test_cleanup(&client)
		client.access.token = access_test_token()
		testing.expect(t, !client_access_retry(&client, false, access_test_start, access_test_invalidate))
		testing.expect(t, client_access_retry(&client, true, access_test_start, access_test_invalidate))
		client_access_tick(&client, access_test_poll, access_test_connect, access_test_persist)
		testing.expect(t, client.net_input_seq == 1 && client.access.retried)
		testing.expect(t, !client_access_retry(&client, true, access_test_start, access_test_invalidate))
		testing.expect(t, len(client.access.token) == 0 && client.access.status == .ERROR)
	}
	access_test_http :: proc(url, method, body, stage: string) -> ([dynamic]byte, i64, bool) {
		response := stage == "generate-token" ? "fixture-validation" : stage == "game-list" ? "[]" : `{"error":"INVALID_ACCESS_TOKEN"}`
		result := make([dynamic]byte); append(&result, response)
		return result, stage == "seek-game" ? 403 : 200, true
	}
	@(test)
	matchmaker_captcha_stops_join_without_authentication_retry :: proc(t: ^testing.T) {
		defer kproto.network_log_clear_secrets()
		link, _ := shared.join_link_parse("FRA:fixture"); defer shared.join_link_free(&link)
		token := access_test_token(); defer delete(token)
		for provider in ([]proc(string, string, string, string) -> ([dynamic]byte, i64, bool){access_test_captcha_http, access_test_captcha_generate, access_test_captcha_game_list, access_test_captcha_success}) {
			rejected: bool
			url, ok, status := krunker_ws_resolve_invite(&link, token, &rejected, provider)
			testing.expect(t, !ok && !rejected && len(url) == 0)
			testing.expect(t, strings.contains(status, "CAPTCHA") && !strings.contains(status, token))
			delete(url)
		}
	}
	access_test_captcha_http :: proc(url, method, body, stage: string) -> ([dynamic]byte, i64, bool) {
		if stage != "seek-game" { return access_test_http(url, method, body, stage) }
		result := make([dynamic]byte); append(&result, `{"error":"CaptchaRequired","message":"Invalid token"}`)
		return result, 400, true
	}
	access_test_captcha_generate :: proc(url, method, body, stage: string) -> ([dynamic]byte, i64, bool) {
		if stage != "generate-token" { panic("CAPTCHA must stop resolution without further requests") }
		result := make([dynamic]byte); append(&result, `{"error":"CaptchaRequired"}`)
		return result, 200, true
	}
	access_test_captcha_game_list :: proc(url, method, body, stage: string) -> ([dynamic]byte, i64, bool) {
		if stage == "generate-token" { return access_test_http(url, method, body, stage) }
		if stage != "game-list" { panic("CAPTCHA must stop resolution without a seek request") }
		result := make([dynamic]byte); append(&result, `{"error":"CaptchaRequired"}`)
		return result, 403, true
	}
	access_test_captcha_success :: proc(url, method, body, stage: string) -> ([dynamic]byte, i64, bool) {
		if stage != "seek-game" { return access_test_http(url, method, body, stage) }
		result := make([dynamic]byte); append(&result, `{"error":"CaptchaRequired"}`)
		return result, 200, true
	}
	@(test)
	matchmaker_token_rejection_uses_network_provider :: proc(t: ^testing.T) {
		defer kproto.network_log_clear_secrets()
		link, _ := shared.join_link_parse("FRA:original"); defer shared.join_link_free(&link)
		token := access_test_token(); defer delete(token)
		rejected: bool
		url, ok, status := krunker_ws_resolve_invite(&link, token, &rejected, access_test_http)
		defer delete(url)
		testing.expect(t, !ok && rejected && !strings.contains(status, token))
		safe := kproto.network_log_safe(fmt.tprintf("access_token=%s refresh_token=fixture-refresh", token)); defer delete(safe)
		testing.expect(t, !strings.contains(safe, token) && !strings.contains(safe, "fixture-refresh"))
		client: Client
		krunker_ws_set_status(&client, fmt.tprintf("server echoed %s", token))
		client_selection_status(&client, fmt.tprintf("server echoed %s", token))
		testing.expect(t, !strings.contains(client.join_status, token) && !strings.contains(client.selection_status, token), "server echoes cannot expose tokens in menu views")
		delete(client.join_status); delete(client.selection_status)
	}
	when ODIN_OS == .Windows {
		@(test)
		windows_access_ignores_environment_and_dotenv_tokens :: proc(t: ^testing.T) {
			token, ok := krunker_ws_access_token(); defer delete(token)
			testing.expect(t, !ok && len(token) == 0)
			client: Client; defer access_test_cleanup(&client)
			testing.expect(t, !client_access_select(&client, time.time_to_unix(time.now()), access_test_empty, access_test_forbidden_fallback))
			testing.expect(t, len(client.access.token) == 0)
		}
		@(test)
		websocket_token_rejection_is_deferred_until_next_tick :: proc(t: ^testing.T) {
			client: Client; defer access_test_cleanup(&client)
			defer krunker_ws_disconnect(&client.krunker)
			defer kproto.krunker_world_reset(&client.krunker_world)
			client.join_link, _ = shared.join_link_parse("FRA:original")
			packet, _ := kproto.krunker_msgpack_encode_packet("dc", []kproto.Krunker_Msgpack_Value{"Invalid token"}, 0)
			defer delete(packet)
			client.krunker.connected = true
			krunker_ws_apply_world(&client, packet)
			testing.expect(t, client.krunker.auth_rejected && !client.krunker.connected && client.access.status == .IDLE)
			client.krunker.auth_rejected, client.krunker.ready_received, client.krunker.connected = false, true, true
			krunker_ws_apply_world(&client, packet)
			testing.expect(t, !client.krunker.auth_rejected, "automatic retry is limited to the pending join")
		}
	}
	@(test)
	offline_and_direct_connections_do_not_require_browser :: proc(t: ^testing.T) {
		client: Client
		client_access_tick(&client, access_test_poll, access_test_connect, access_test_persist)
		testing.expect(t, client.access.request == 0 && client.net_input_seq == 0, "offline ticks do not start authentication")
		for invite in ([]string{"krodin://127.0.0.1:21015", "wss://example.invalid/ws"}) {
			link, _ := shared.join_link_parse(invite)
			testing.expect(t, !client_access_browser_link(&link))
			shared.join_link_free(&link)
		}
		testing.expect(t, client.access.request == 0, "direct links do not require authentication")
	}
}
