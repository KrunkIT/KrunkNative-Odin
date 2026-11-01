package main

import "core:fmt"
import "core:c"
import "core:encoding/json"
import "core:net"
import "core:os"
import "core:strings"
import "base:runtime"
import shared "../src/shared"
import krunker "../src/krunker"
import curl "vendor:curl"

Http_Capture :: struct { body: [dynamic]byte }

curl_write_body :: proc "c" (buffer: [^]byte, size, count: c.size_t, output: rawptr) -> c.size_t {
	context = runtime.default_context()
	total := int(size * count)
	if output == nil || total <= 0 do return 0
	capture := cast(^Http_Capture)output
	append(&capture.body, ..buffer[:total])
	return c.size_t(total)
}

curl_http_request :: proc(url, method, request_body: string) -> (body: [dynamic]byte, status: i64, code: curl.code, ok: bool) {
	handle := curl.easy_init()
	if handle == nil {
		code = .E_FAILED_INIT
		return
	}
	defer curl.easy_cleanup(handle)

	url_c := strings.clone_to_cstring(url)
	defer delete(url_c)
	if curl.easy_setopt(handle, .URL, url_c) != .E_OK {
		code = .E_SETOPT_OPTION_SYNTAX
		return
	}
	if curl.easy_setopt(handle, .CONNECTTIMEOUT_MS, c.long(8000)) != .E_OK || curl.easy_setopt(handle, .TIMEOUT_MS, c.long(15000)) != .E_OK {
		code = .E_SETOPT_OPTION_SYNTAX
		return
	}
	headers: ^curl.slist
	origin := strings.clone_to_cstring("Origin: https://krunker.io")
	referer := strings.clone_to_cstring("Referer: https://krunker.io/")
	user_agent := strings.clone_to_cstring("User-Agent: Mozilla/5.0 (KrunkNative link-flow test)")
	defer delete(origin)
	defer delete(referer)
	defer delete(user_agent)
	headers = curl.slist_append(headers, origin)
	headers = curl.slist_append(headers, referer)
	headers = curl.slist_append(headers, user_agent)
	defer curl.slist_free_all(headers)

	capture := new(Http_Capture)
	defer free(capture)
	if curl.easy_setopt(handle, .WRITEFUNCTION, curl.write_callback(curl_write_body)) != .E_OK || curl.easy_setopt(handle, .WRITEDATA, rawptr(capture)) != .E_OK {
		code = .E_SETOPT_OPTION_SYNTAX
		return
	}
	if method == "POST" {
		body_c := strings.clone_to_cstring(request_body)
		defer delete(body_c)
		content_type := strings.clone_to_cstring("Content-Type: application/json")
		defer delete(content_type)
		headers = curl.slist_append(headers, content_type)
		if curl.easy_setopt(handle, .POST, c.long(1)) != .E_OK || curl.easy_setopt(handle, .POSTFIELDS, rawptr(body_c)) != .E_OK {
			code = .E_SETOPT_OPTION_SYNTAX
			return
		}
	}
	if curl.easy_setopt(handle, .HTTPHEADER, headers) != .E_OK {
		code = .E_SETOPT_OPTION_SYNTAX
		return
	}

	code = curl.easy_perform(handle)
	if code != .E_OK {
		return
	}
	http_status: c.long
	if curl.easy_getinfo(handle, .RESPONSE_CODE, &http_status) != .E_OK {
		code = .E_RECV_ERROR
		return
	}
	for byte_value in capture.body {
		append(&body, byte_value)
	}
	return body, i64(http_status), code, true
}

json_string_field :: proc(object: json.Object, key: string) -> (value: string, ok: bool) {
	raw, found := object[key]
	if !found do return
	if text, is_string := raw.(json.String); is_string {
		return string(text), true
	}
	return
}

game_list_version :: proc(entries: json.Array, fallback: string) -> string {
	for entry in entries {
		if fields, is_entry := entry.(json.Array); is_entry && len(fields) > 4 {
			if metadata, is_metadata := fields[4].(json.Object); is_metadata {
				if candidate, candidate_ok := json_string_field(metadata, "v"); candidate_ok && len(candidate) > 0 {
					return candidate
				}
			}
		}
	}
	return fallback
}

url_encode_component :: proc(value: string) -> string {
	builder, err := strings.builder_make_none()
	if err != nil do return ""
	defer strings.builder_destroy(&builder)
	hex := "0123456789ABCDEF"
	for index in 0 ..< len(value) {
		byte_value := value[index]
		safe := byte_value >= 'a' && byte_value <= 'z' || byte_value >= 'A' && byte_value <= 'Z' || byte_value >= '0' && byte_value <= '9' || byte_value == '-' || byte_value == '_' || byte_value == '.' || byte_value == '~'
		if safe {
			strings.write_byte(&builder, byte_value)
		} else {
			strings.write_byte(&builder, '%')
			strings.write_byte(&builder, hex[byte_value >> 4])
			strings.write_byte(&builder, hex[byte_value & 15])
		}
	}
	return strings.clone(strings.to_string(builder))
}

curl_websocket_probe :: proc(url: string) -> (code: curl.code, status: i64, ok: bool) {
	handle := curl.easy_init()
	if handle == nil do return .E_FAILED_INIT, 0, false
	defer curl.easy_cleanup(handle)
	url_c := strings.clone_to_cstring(url)
	defer delete(url_c)
	if curl.easy_setopt(handle, .URL, url_c) != .E_OK {
		return .E_SETOPT_OPTION_SYNTAX, 0, false
	}
	if curl.easy_setopt(handle, .CONNECTTIMEOUT_MS, c.long(8000)) != .E_OK || curl.easy_setopt(handle, .TIMEOUT_MS, c.long(15000)) != .E_OK {
		return .E_SETOPT_OPTION_SYNTAX, 0, false
	}
	if curl.easy_setopt(handle, .CONNECT_ONLY, c.long(2)) != .E_OK {
		return .E_SETOPT_OPTION_SYNTAX, 0, false
	}
	headers: ^curl.slist
	origin := strings.clone_to_cstring("Origin: https://krunker.io")
	referer := strings.clone_to_cstring("Referer: https://krunker.io/")
	user_agent := strings.clone_to_cstring("User-Agent: Mozilla/5.0 (KrunkNative link-flow test)")
	defer delete(origin)
	defer delete(referer)
	defer delete(user_agent)
	headers = curl.slist_append(headers, origin)
	headers = curl.slist_append(headers, referer)
	headers = curl.slist_append(headers, user_agent)
	defer curl.slist_free_all(headers)
	if curl.easy_setopt(handle, .HTTPHEADER, headers) != .E_OK {
		return .E_SETOPT_OPTION_SYNTAX, 0, false
	}
	code = curl.easy_perform(handle)
	if code != .E_OK do return code, 0, false
	http_status: c.long
	if curl.easy_getinfo(handle, .RESPONSE_CODE, &http_status) != .E_OK {
		return .E_RECV_ERROR, 0, false
	}
	status = i64(http_status)
	if status != 101 {
		return .E_HTTP_RETURNED_ERROR, status, false
	}
	return code, status, true
}

dotenv_access_token :: proc() -> (token: string, ok: bool) {
	data, err := os.read_entire_file_from_path(".env", context.temp_allocator)
	if err != nil do return

	for &line in strings.split_lines(string(data)) {
		line = strings.trim_space(line)
		if len(line) == 0 || line[0] == '#' do continue
		if strings.has_prefix(line, "export ") {
			line = strings.trim_space(line[7:])
		}
		eq := strings.index(line, "=")
		if eq <= 0 do continue
		key := strings.trim_space(line[:eq])
		if key != "KRUNKER_ACCESS_TOKEN" do continue
		value := strings.trim_space(line[eq + 1:])
		if len(value) >= 2 && ((value[0] == '"' && value[len(value) - 1] == '"') || (value[0] == '\'' && value[len(value) - 1] == '\'')) {
			value = value[1:len(value) - 1]
		}
		if len(value) == 0 do return
		return strings.clone(value), true
	}
	return
}

run_browser_invite_flow :: proc(link: ^shared.Join_Link) -> bool {
	if len(link.game_id) == 0 {
		fail("invite", "the browser invite did not contain a game id")
		return false
	}
	if curl.global_init(curl.GLOBAL_DEFAULT) != .E_OK {
		fail("curl", "libcurl global initialization failed")
		return false
	}
	defer curl.global_cleanup()

	fmt.println("[1/7] Fetching matchmaker validation token...")
	validation_body, validation_status, validation_code, validation_ok := curl_http_request("https://matchmaker.krunker.io/generate-token", "GET", "")
	if !validation_ok || validation_code != .E_OK {
		fmt.printf("[link-flow][ERROR][validation-token] HTTP request failed: %v\n", validation_code)
		return false
	}
	defer delete(validation_body)
	if validation_status < 200 || validation_status >= 300 || len(validation_body) == 0 {
		fmt.printf("[link-flow][ERROR][validation-token] HTTP status %d or empty token response\n", validation_status)
		return false
	}
	validation_token := strings.trim_space(string(validation_body[:]))
	fmt.printf("[link-flow] validation token: %d bytes\n", len(validation_token))

	fmt.println("[2/7] Loading access token...")
	access_token, access_token_ok := os.lookup_env_alloc("KRUNKER_ACCESS_TOKEN", context.allocator)
	access_token_source := "environment"
	if !access_token_ok || len(access_token) == 0 {
		access_token, access_token_ok = dotenv_access_token()
		access_token_source = ".env"
	}
	if !access_token_ok || len(access_token) == 0 {
		fail("access-token", "set KRUNKER_ACCESS_TOKEN in the environment or .env; the matchmaker will reject anonymous requests")
		return false
	}
	fmt.printf("[link-flow] access token: %d bytes (%s)\n", len(access_token), access_token_source)

	fmt.println("[3/7] Fetching live game version...")
	version := "1.0.0"
	game_list_body, game_list_status, game_list_code, game_list_ok := curl_http_request("https://matchmaker.krunker.io/game-list?hostname=krunker.io", "GET", "")
	if !game_list_ok || game_list_code != .E_OK || game_list_status < 200 || game_list_status >= 300 {
		fmt.printf("[link-flow][WARN][game-list] request failed (status=%d code=%v); using fallback version %s\n", game_list_status, game_list_code, version)
	} else {
		defer delete(game_list_body)
		game_list_value, game_list_parse_error := json.parse_string(string(game_list_body[:]), parse_integers = true)
		if game_list_parse_error != .None {
			fmt.printf("[link-flow][WARN][game-list] invalid JSON (%v); using fallback version %s\n", game_list_parse_error, version)
		} else {
			defer json.destroy_value(game_list_value)
			if game_list, is_array := game_list_value.(json.Array); is_array {
				version = game_list_version(game_list, version)
			} else if game_list, is_object := game_list_value.(json.Object); is_object {
				if raw_games, found := game_list["games"]; found {
					if games, is_games := raw_games.(json.Array); is_games {
						version = game_list_version(games, version)
					}
				}
			}
		}
	}
	fmt.printf("[link-flow] game version: %s\n", version)

	fmt.println("[4/7] Resolving invite through /seek-game...")
	encoded_game_id := url_encode_component(link.game_id)
	encoded_validation := url_encode_component(validation_token)
	encoded_access := url_encode_component(access_token)
	query_json, query_ok := krunker.krunker_seek_data_query(version)
	if !query_ok { fmt.println("[link-flow][ERROR][seek-game] failed to serialize dataQuery"); return false }
	defer delete(query_json)
	data_query := url_encode_component(query_json)
	seek_url := fmt.tprintf("https://matchmaker.krunker.io/seek-game?hostname=krunker.io&region=sgp&autoChangeGame=false&validationToken=%s&dataQuery=%s&accessToken=%s&game=%s", encoded_validation, data_query, encoded_access, encoded_game_id)
	seek_body, seek_status, seek_code, seek_ok := curl_http_request(seek_url, "GET", "")
	if !seek_ok || seek_code != .E_OK {
		fmt.printf("[link-flow][ERROR][seek-game] HTTP request failed: %v\n", seek_code)
		return false
	}
	defer delete(seek_body)
	fmt.printf("[link-flow] seek-game HTTP status: %d\n", seek_status)
	if seek_status < 200 || seek_status >= 300 {
		fmt.printf("[link-flow][ERROR][seek-game] server rejected request: %s\n", string(seek_body[:]))
		return false
	}
	assignment_value, assignment_parse_error := json.parse_string(string(seek_body[:]), parse_integers = true)
	if assignment_parse_error != .None {
		fmt.printf("[link-flow][ERROR][assignment] invalid JSON response: %v\n", assignment_parse_error)
		return false
	}
	defer json.destroy_value(assignment_value)
	assignment, assignment_ok := assignment_value.(json.Object)
	if !assignment_ok {
		fail("assignment", "seek-game response was not a JSON object")
		return false
	}
	game_host, game_host_ok := json_string_field(assignment, "host")
	client_key, client_key_ok := json_string_field(assignment, "clientId")
	assigned_game_id, assigned_game_id_ok := json_string_field(assignment, "gameId")
	if !game_host_ok || len(game_host) == 0 {
		fmt.printf("[link-flow][ERROR][assignment] missing host: %s\n", string(seek_body[:]))
		return false
	}
	if !client_key_ok || len(client_key) == 0 {
		fmt.printf("[link-flow][ERROR][assignment] missing clientId: %s\n", string(seek_body[:]))
		return false
	}
	if !assigned_game_id_ok || len(assigned_game_id) == 0 {
		fmt.printf("[link-flow][ERROR][assignment] missing gameId: %s\n", string(seek_body[:]))
		return false
	}
	fmt.printf("[link-flow] assignment: host=%s gameId=%s clientId=%s\n", game_host, assigned_game_id, client_key)

	fmt.println("[5/7] Building assigned WSS URL...")
	ws_url := fmt.tprintf("wss://%s/ws?gameId=%s&clientKey=%s&at=%s", game_host, url_encode_component(assigned_game_id), url_encode_component(client_key), url_encode_component(access_token))
	fmt.printf("[link-flow] websocket URL: wss://%s/ws?gameId=%s&clientKey=%s&at=<redacted>\n", game_host, url_encode_component(assigned_game_id), url_encode_component(client_key))

	fmt.println("[6/7] Performing TLS/WebSocket upgrade...")
	ws_code, ws_status, ws_ok := curl_websocket_probe(ws_url)
	if !ws_ok {
		fmt.printf("[link-flow][ERROR][websocket] upgrade failed: %v (HTTP status %d)\n", ws_code, ws_status)
		return false
	}
	fmt.println("[link-flow] websocket upgrade: OK")
	fmt.println("[7/7] Protocol handshake check...")
	fmt.println("[link-flow][WARN][protocol] transport connected, but MessagePack initial packet exchange is not sent by this diagnostic")
	fmt.println("[link-flow] complete: invite resolution and WSS connection passed")
	return true
}

print_usage :: proc() {
	fmt.println("Usage: krunker_link_flow_test <lobby-link>")
	fmt.println()
	fmt.println("Examples:")
	fmt.println("  krunker_link_flow_test https://krunker.io/?game=abc123")
	fmt.println("  krunker_link_flow_test tcp://127.0.0.1:21015")
}

fail :: proc(stage, message: string) -> bool {
	// Keep diagnostics on stdout so progress and failure lines remain ordered
	// when the executable is run from a shell or captured by a test harness.
	fmt.printf("[link-flow][ERROR][%s] %s\n", stage, message)
	return false
}

main :: proc() {
	if len(os.args) < 2 {
		print_usage()
		fail("arguments", "a lobby link is required")
		os.exit(2)
	}
	if len(os.args) > 2 {
		print_usage()
		fail("arguments", "expected exactly one lobby link argument")
		os.exit(2)
	}

	input := os.args[1]
	fmt.printf("[link-flow] input: %s\n", input)
	link, parsed := shared.join_link_parse(input)
	if !parsed {
		fail("parse", "the link is empty, malformed, or uses an unsupported scheme")
		os.exit(3)
	}
	defer shared.join_link_free(&link)
	fmt.println("[link-flow] parse: OK")
	fmt.printf("[link-flow] scheme: %s\n", link.scheme)
	fmt.printf("[link-flow] host: %s\n", link.host)
	fmt.printf("[link-flow] port: %d\n", link.port)
	fmt.printf("[link-flow] path: %s\n", link.path)
	fmt.printf("[link-flow] game id: %s\n", link.game_id)
	fmt.printf("[link-flow] team hint: %s\n", link.team_hint)

	if link.scheme == "http" || link.scheme == "https" || link.scheme == "game" {
		if len(link.game_id) == 0 {
			fail("invite", "HTTP invite has no game or gameId query parameter")
			os.exit(4)
		}
		fmt.println("[link-flow] invite: OK")
		if !run_browser_invite_flow(&link) {
			os.exit(5)
		}
		os.exit(0)
	}

	if link.scheme == "ws" || link.scheme == "wss" {
		if len(link.host) == 0 {
			fail("endpoint", "WebSocket link has no host")
			os.exit(4)
		}
		if len(link.path) == 0 {
			fail("endpoint", "WebSocket link has no path; assigned Krunker links must target /ws")
			os.exit(4)
		}
		if link.path != "/ws" {
			fmt.printf("[link-flow][WARN][endpoint] WebSocket path is %s; Krunker normally uses /ws\n", link.path)
		}
		if len(link.game_id) == 0 {
			fail("endpoint", "WebSocket link is missing the gameId query parameter")
			os.exit(4)
		}
		if len(link.client_key) == 0 {
			fail("endpoint", "WebSocket link is missing the clientKey query parameter")
			os.exit(4)
		}
		if len(link.access_token) == 0 {
			fail("endpoint", "WebSocket link is missing the at access-token query parameter")
			os.exit(4)
		}
		fmt.println("[link-flow] endpoint: OK")
		if curl.global_init(curl.GLOBAL_DEFAULT) != .E_OK {
			fail("curl", "libcurl global initialization failed")
			os.exit(5)
		}
	ws_code, ws_status, ws_ok := curl_websocket_probe(link.raw)
	curl.global_cleanup()
	if !ws_ok {
		fmt.printf("[link-flow][ERROR][websocket] upgrade failed: %v (HTTP status %d)\n", ws_code, ws_status)
			os.exit(5)
		}
		fmt.println("[link-flow] websocket upgrade: OK")
		fmt.println("[link-flow][WARN][protocol] transport connected, but MessagePack handshake is not sent by this diagnostic")
		os.exit(0)
	}

	if link.scheme != "tcp" && link.scheme != "krunker" {
		fail("scheme", "only tcp:// and krunker:// can reach the native protocol")
		os.exit(4)
	}
	if len(link.host) == 0 {
		fail("endpoint", "native endpoint has no host")
		os.exit(4)
	}
	port := link.port
	if port == 0 {
		port = 21015
		fmt.println("[link-flow] port: missing; using native default 21015")
	}
	if port < 1 || port > 65535 {
		fail("endpoint", "port must be between 1 and 65535")
		os.exit(4)
	}

	fmt.printf("[link-flow] dialing native TCP %s:%d...\n", link.host, port)
	socket, err := net.dial_tcp(link.host, int(port))
	if err != nil {
		fmt.printf("[link-flow][ERROR][connect] %s:%d could not be reached: %v\n", link.host, port, err)
		os.exit(6)
	}
	net.close(socket)
	fmt.println("[link-flow] connect: OK")
	fmt.println("[link-flow] complete: parse, endpoint validation, and native TCP connect passed")
}
