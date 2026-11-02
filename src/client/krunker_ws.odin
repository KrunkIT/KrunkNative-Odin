package main

import "core:c"
import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import curl "vendor:curl"
import glfw "vendor:glfw"
import shared "../shared"
import kproto "../krunker"

// Krunker_WS_State is deliberately separate from Net_Client_State. The
// native server uses a length-prefixed TCP protocol while Krunker uses a TLS
// WebSocket carrying concatenated MessagePack values.
Krunker_WS_State :: struct {
	handle:       ^curl.CURL,
	connected:    bool,
	global_ready: bool,
	got_load:     bool,
	bootstrapped: bool,
	spawned:      bool,
	team:         i32,
	class_index:  i32,
	q_index:      int,
	ah_num:       u8,
	recv_buffer:  [4096]byte,
	ws_url:       string,
	pending:      [dynamic]string,
	rx_logged:    int,
	decode_errors: int,
	send_blocked: bool,
	error_buffer: [curl.ERROR_SIZE]byte,
	upgrade_capture: kproto.Network_HTTP_Capture,
	message: kproto.Krunker_WS_Message,
	rendered_map_revision: u64,
	render_map_ready: bool,
	player_revisions: map[i32]u64,
	local_sync_revision: u64,
	local_ammo_revision: u64,
	ready_received: bool,
	bootstrap_step: int,
	last_server_message: string,
	input_elapsed: f64,
	send_elapsed: f64,
	input_commands: [dynamic]shared.Input,
	input_reset: bool,
	input_swap: u8,
	command_direction: shared.Vec2,
	render_previous, render_current: Krunker_Render_Sample,
	render_sample_ready: bool,
	prediction_corrections: int,
	input_sequence: i32,
	input_logged: int,
	heartbeat_logged: int,
	snapshots_received: int,
	server_error: string,
}

krunker_ws_set_status :: proc(client: ^Client, text: string) {
	delete(client.join_status)
	client.join_status = strings.clone(text)
	kproto.network_log("status", text)
}

krunker_ws_url_encode :: proc(value: string) -> string {
	return kproto.network_url_encode(value)
}

krunker_ws_json_string :: proc(object: json.Object, key: string) -> (string, bool) {
	raw, found := object[key]
	if !found do return "", false
	if value, ok := raw.(json.String); ok { return string(value), true }
	return "", false
}

krunker_ws_game_version :: proc(value: json.Value) -> string {
	if entries, ok := value.(json.Array); ok {
		for entry in entries {
			if fields, ok := entry.(json.Array); ok && len(fields) > 4 {
				if metadata, ok := fields[4].(json.Object); ok {
					if version, ok := krunker_ws_json_string(metadata, "v"); ok && len(version) > 0 { return strings.clone(version) }
				}
			}
		}
	}
	if object, ok := value.(json.Object); ok {
		if games, found := object["games"]; found { return krunker_ws_game_version(games) }
	}
	return strings.clone("1.0.0")
}

krunker_ws_access_token :: proc() -> (string, bool) {
	if token, ok := os.lookup_env_alloc("KRUNKER_ACCESS_TOKEN", context.allocator); ok {
		if len(token) > 0 { kproto.network_log("auth", fmt.tprintf("source=environment KRUNKER_ACCESS_TOKEN present=true bytes=%d", len(token))); return token, true }
		delete(token)
	}
	data, err := os.read_entire_file_from_path(".env", context.temp_allocator)
	if err != nil { kproto.network_log("auth", fmt.tprintf("ERROR reading .env from working directory: %v", err)); return "", false }
	lines := strings.split_lines(string(data))
	defer delete(lines)
	for raw_line in lines {
		line := strings.trim_space(raw_line)
		if len(line) == 0 || line[0] == '#' do continue
		eq := strings.index(line, "=")
		if eq <= 0 || strings.trim_space(line[:eq]) != "KRUNKER_ACCESS_TOKEN" do continue
		value := strings.trim_space(line[eq + 1:])
		if len(value) >= 2 && ((value[0] == '"' && value[len(value)-1] == '"') || (value[0] == '\'' && value[len(value)-1] == '\'')) { value = value[1:len(value)-1] }
		if len(value) > 0 { kproto.network_log("auth", fmt.tprintf("source=.env KRUNKER_ACCESS_TOKEN present=true bytes=%d", len(value))); return strings.clone(value), true }
	}
	kproto.network_log("auth", "ERROR KRUNKER_ACCESS_TOKEN missing or empty in .env")
	return "", false
}

krunker_ws_http_failure :: proc(stage: string, status: i64, transport_ok: bool, body: []byte) -> string {
	safe := kproto.network_log_safe(string(body), 240)
	defer delete(safe)
	return fmt.tprintf("%s failed: HTTP %d, transport_ok=%v, body=%s. See logs/krunker-network.log", stage, status, transport_ok, safe)
}

krunker_ws_log_token_expiry :: proc(token: string) {
	parts := strings.split(token, ".")
	defer delete(parts)
	if len(parts) != 3 { kproto.network_log("auth", "access token is not a three-part JWT; expiry unavailable"); return }
	data, err := base64.decode(parts[1], base64.DEC_URL_TABLE)
	if err != nil { kproto.network_log("auth", fmt.tprintf("JWT payload decode failed=%v; expiry unavailable", err)); return }
	defer delete(data)
	value, parse_err := json.parse_string(string(data), parse_integers = true)
	if parse_err != .None { kproto.network_log("auth", "JWT payload JSON invalid; expiry unavailable"); return }
	defer json.destroy_value(value)
	if object, ok := value.(json.Object); ok {
		if expiry, ok := object["exp"].(json.Integer); ok {
			now := time.time_to_unix(time.now())
			kproto.network_log("auth", fmt.tprintf("JWT exp_unix=%d now_unix=%d remaining_seconds=%d expired=%v (decoded only; signature not verified here)", expiry, now, i64(expiry)-now, i64(expiry) <= now))
			return
		}
	}
	kproto.network_log("auth", "JWT exp missing; expiry unavailable")
}

krunker_ws_resolve_invite :: proc(link: ^shared.Join_Link) -> (string, bool, string) {
	access, access_ok := krunker_ws_access_token()
	if !access_ok { return "", false, "KRUNKER_ACCESS_TOKEN is missing; set it in .env. See logs/krunker-network.log" }
	defer delete(access)
	kproto.network_log_secret(access)
	krunker_ws_log_token_expiry(access)
	access_encoded := krunker_ws_url_encode(access)
	defer delete(access_encoded)
	kproto.network_log_secret(access_encoded)
	validation, validation_status, validation_ok := kproto.network_http("https://matchmaker.krunker.io/generate-token", "GET", "", "generate-token")
	defer delete(validation)
	if !validation_ok || validation_status < 200 || validation_status >= 300 || len(strings.trim_space(string(validation[:]))) == 0 {
		return "", false, krunker_ws_http_failure("matchmaker /generate-token", validation_status, validation_ok, validation[:])
	}
	validation_token := strings.trim_space(string(validation[:]))
	kproto.network_log_secret(validation_token)
	validation_encoded := krunker_ws_url_encode(validation_token)
	defer delete(validation_encoded)
	kproto.network_log_secret(validation_encoded)
	kproto.network_log("generate-token", fmt.tprintf("validation token received; bytes=%d (value redacted)", len(validation_token)))
	version := strings.clone("1.0.0")
	defer delete(version)
	game_list, game_status, game_ok := kproto.network_http("https://matchmaker.krunker.io/game-list?hostname=krunker.io", "GET", "", "game-list")
	if game_ok && game_status >= 200 && game_status < 300 {
		if value, err := json.parse_string(string(game_list[:]), parse_integers = true); err == .None {
			delete(version)
			version = krunker_ws_game_version(value)
			json.destroy_value(value)
		} else { kproto.network_log("game-list", fmt.tprintf("ERROR JSON parse=%v; using fallback version=1.0.0; body=%s", err, string(game_list[:]))) }
	} else { kproto.network_log("game-list", "WARNING game list unavailable; using fallback version=1.0.0") }
	delete(game_list)
	data_query, query_ok := kproto.krunker_seek_data_query(version)
	if !query_ok { return "", false, "Could not serialize matchmaker dataQuery; see logs/krunker-network.log" }
	defer delete(data_query)
	kproto.network_log("seek-game", fmt.tprintf("game=%s region=sgp hostname=krunker.io autoChangeGame=false dataQuery=%s; version 1.0.0 means fallback if absent from metadata", link.game_id, data_query))
	data_encoded := krunker_ws_url_encode(data_query)
	game_encoded := krunker_ws_url_encode(link.game_id)
	defer delete(data_encoded)
	defer delete(game_encoded)
	seek := fmt.tprintf("https://matchmaker.krunker.io/seek-game?hostname=krunker.io&region=sgp&autoChangeGame=false&validationToken=%s&dataQuery=%s&accessToken=%s&game=%s", validation_encoded, data_encoded, access_encoded, game_encoded)
	assignment_body, status, ok := kproto.network_http(seek, "GET", "", "seek-game")
	defer delete(assignment_body)
	if !ok || status < 200 || status >= 300 { return "", false, krunker_ws_http_failure("matchmaker /seek-game", status, ok, assignment_body[:]) }
	value, parse_err := json.parse_string(string(assignment_body[:]), parse_integers = true)
	if parse_err != .None { kproto.network_log("seek-game", fmt.tprintf("ERROR JSON parse=%v body=%s", parse_err, string(assignment_body[:]))); return "", false, "matchmaker returned invalid JSON; see logs/krunker-network.log" }
	defer json.destroy_value(value)
	object, object_ok := value.(json.Object)
	if !object_ok { kproto.network_log("seek-game", fmt.tprintf("ERROR expected object; body=%s", string(assignment_body[:]))); return "", false, "matchmaker response was not an object; see logs/krunker-network.log" }
	host, host_ok := krunker_ws_json_string(object, "host")
	client_key, key_ok := krunker_ws_json_string(object, "clientId")
	game_id, game_id_ok := krunker_ws_json_string(object, "gameId")
	if key_ok { kproto.network_log_secret(client_key) }
	kproto.network_log("seek-game", fmt.tprintf("assignment host_present=%v clientId_present=%v gameId_present=%v body=%s", host_ok, key_ok, game_id_ok, string(assignment_body[:])))
	if !host_ok || !key_ok || !game_id_ok || len(host) == 0 || len(client_key) == 0 || len(game_id) == 0 { return "", false, "matchmaker response omitted host, clientId, or gameId; see logs/krunker-network.log" }
	resolved_game := krunker_ws_url_encode(game_id)
	resolved_key := krunker_ws_url_encode(client_key)
	defer delete(resolved_game)
	defer delete(resolved_key)
	kproto.network_log_secret(resolved_key)
	url := fmt.aprintf("wss://%s/ws?gameId=%s&clientKey=%s&at=%s", host, resolved_game, resolved_key, access_encoded)
	return url, true, ""
}

krunker_ws_pack_string :: proc(out: ^[dynamic]byte, value: string) {
	if len(value) < 32 { append(out, byte(0xA0 | len(value))) }
	else if len(value) < 256 { append(out, 0xD9, byte(len(value))) }
	else { append(out, 0xDA, byte(len(value) >> 8), byte(len(value))) }
	append(out, value)
}

krunker_ws_pack_int :: proc(out: ^[dynamic]byte, value: i32) {
	if value >= 0 && value < 128 { append(out, byte(value)) }
	else if value < 0 && value >= -32 { append(out, byte(i8(value))) }
	else if value >= 0 && value < 256 { append(out, 0xCC, byte(value)) }
	else if value >= 0 && value < 65536 { append(out, 0xCD, byte(value >> 8), byte(value)) }
	else if value >= 0 { append(out, 0xCE, byte(value >> 24), byte(value >> 16), byte(value >> 8), byte(value)) }
	else if value >= -128 { append(out, 0xD0, byte(i8(value))) }
	else if value >= -32768 { append(out, 0xD1, byte(value >> 8), byte(value)) }
	else { append(out, 0xD2, byte(value >> 24), byte(value >> 16), byte(value >> 8), byte(value)) }
}

krunker_ws_pack_nil :: proc(out: ^[dynamic]byte) { append(out, 0xC0) }
krunker_ws_pack_array :: proc(out: ^[dynamic]byte, count: int) { if count < 16 { append(out, byte(0x90 | count)) } else { append(out, 0xDC, byte(count >> 8), byte(count)) } }
krunker_ws_pack_map :: proc(out: ^[dynamic]byte, count: int) { append(out, byte(0x80 | count)) }

krunker_ws_finish_packet :: proc(payload: [dynamic]byte, opcode: string, ah_num: ^u8) -> [dynamic]byte {
	ah_num^ = kproto.krunker_msgpack_counter_next(ah_num^, opcode)
	out := make([dynamic]byte, len(payload) + 2)
	copy(out[:len(payload)], payload[:])
	out[len(payload)] = byte(ah_num^ >> 4)
	out[len(payload) + 1] = byte(ah_num^ & 15)
	delete(payload)
	return out
}

krunker_ws_message :: proc(opcode: string, ah_num: ^u8, q_index: int, team: i32 = 0, class_index: i32 = 0) -> [dynamic]byte {
	message: [dynamic]byte
	switch opcode {
	case "load":
		krunker_ws_pack_array(&message, 1); krunker_ws_pack_string(&message, "load")
	case "po":
		krunker_ws_pack_array(&message, 1); krunker_ws_pack_string(&message, "po")
	case "v":
		krunker_ws_pack_array(&message, 1); krunker_ws_pack_string(&message, "v")
	case "en":
		krunker_ws_pack_array(&message, 14); krunker_ws_pack_string(&message, "en")
		krunker_ws_pack_array(&message, 34)
		krunker_ws_pack_int(&message, class_index); krunker_ws_pack_int(&message, 2482)
		krunker_ws_pack_array(&message, 2); krunker_ws_pack_int(&message, -1); krunker_ws_pack_int(&message, -1)
		values := [?]i32{-1, -1, 2, 0, 0, 1, -1, -1, 1, 0, -1, -1, -1, -1, -1, -1, 0, -1, -1, 1, 1, 1, -1, -1, -1, 0}
		for value in values { krunker_ws_pack_int(&message, value) }
		krunker_ws_pack_array(&message, 2); krunker_ws_pack_nil(&message); krunker_ws_pack_int(&message, -1)
		krunker_ws_pack_int(&message, -1); krunker_ws_pack_int(&message, -1); krunker_ws_pack_int(&message, -1); krunker_ws_pack_int(&message, 1)
		krunker_ws_pack_int(&message, 16); krunker_ws_pack_int(&message, 18)
		for _ in 0 ..< 6 { append(&message, 0xC2) }
		krunker_ws_pack_nil(&message); append(&message, 0xC2); append(&message, 0xC2); append(&message, 0xC2)
	case "team":
		krunker_ws_pack_array(&message, 3); krunker_ws_pack_string(&message, "cd"); krunker_ws_pack_string(&message, "t"); krunker_ws_pack_int(&message, team)
	case "class":
		krunker_ws_pack_array(&message, 3); krunker_ws_pack_string(&message, "cd"); krunker_ws_pack_string(&message, "c"); krunker_ws_pack_map(&message, 2); krunker_ws_pack_string(&message, "c"); krunker_ws_pack_int(&message, class_index); krunker_ws_pack_string(&message, "s"); krunker_ws_pack_nil(&message)
	case "q":
		switch q_index {
		case 0:
			krunker_ws_pack_array(&message, 7); krunker_ws_pack_string(&message, "q"); krunker_ws_pack_int(&message, 0); krunker_ws_pack_int(&message, 0); krunker_ws_pack_array(&message, 2); krunker_ws_pack_int(&message, 8); krunker_ws_pack_int(&message, 33); krunker_ws_pack_int(&message, 0); krunker_ws_pack_array(&message, 2); krunker_ws_pack_int(&message, 0); krunker_ws_pack_int(&message, -4712); krunker_ws_pack_map(&message, 11)
			keys := [?]string{"0-4", "0-5", "0-6", "0-7", "0-8", "0-9", "0-10", "0-11", "0-12", "0-13", "0-14"}
			for key in keys { krunker_ws_pack_string(&message, key); krunker_ws_pack_int(&message, key == "0-4" ? -1 : 0) }
		case 1:
			krunker_ws_pack_array(&message, 5); krunker_ws_pack_string(&message, "q"); krunker_ws_pack_int(&message, 0); krunker_ws_pack_int(&message, 2); krunker_ws_pack_array(&message, 3); krunker_ws_pack_int(&message, 8); krunker_ws_pack_int(&message, 12); krunker_ws_pack_int(&message, 15); krunker_ws_pack_int(&message, 0)
		case 2:
			krunker_ws_pack_array(&message, 5); krunker_ws_pack_string(&message, "q"); krunker_ws_pack_int(&message, 0); krunker_ws_pack_int(&message, 5); krunker_ws_pack_array(&message, 3); krunker_ws_pack_int(&message, 22); krunker_ws_pack_int(&message, 11); krunker_ws_pack_int(&message, 8); krunker_ws_pack_int(&message, 0)
		case:
			krunker_ws_pack_array(&message, 5); krunker_ws_pack_string(&message, "q"); krunker_ws_pack_int(&message, 0); krunker_ws_pack_int(&message, 8); krunker_ws_pack_array(&message, 5); krunker_ws_pack_int(&message, 10); krunker_ws_pack_int(&message, 12); krunker_ws_pack_int(&message, 5); krunker_ws_pack_int(&message, 6); krunker_ws_pack_int(&message, 6); krunker_ws_pack_int(&message, 0)
		}
	}
	return krunker_ws_finish_packet(message, opcode, ah_num)
}

krunker_ws_send_internal :: proc(state: ^Krunker_WS_State, opcode: string, queue_on_again: bool) -> bool {
	state.send_blocked = false
	// Advance the shared counter only after a complete successful send.
	// Retrying an unsent packet must reuse its counter, including across wrap.
	next_counter := state.ah_num
	packet := krunker_ws_message(opcode, &next_counter, state.q_index, state.team, state.class_index)
	defer delete(packet)
	sent: c.size_t
	code := curl.ws_send(state.handle, rawptr(&packet[0]), c.size_t(len(packet)), &sent, 0, curl.WS_BINARY)
	if code == .E_AGAIN && sent == 0 {
		state.send_blocked = true
		if queue_on_again { append(&state.pending, strings.clone(opcode)); kproto.network_log("ws-send", fmt.tprintf("would block; queued opcode=%s pending=%d", opcode, len(state.pending))) }
		return queue_on_again
	}
	if code != .E_OK || int(sent) != len(packet) {
		kproto.network_log("ws-send", fmt.tprintf("ERROR opcode=%s curl=%v (%s) sent=%d expected=%d detail=%s", opcode, code, string(curl.easy_strerror(code)), sent, len(packet), string(cast(cstring)&state.error_buffer[0])))
		return false
	}
	state.ah_num = next_counter
	if opcode == "v" && state.spawned { state.heartbeat_logged += 1 }
	if opcode != "v" || !state.spawned || state.heartbeat_logged <= 3 || state.heartbeat_logged % 120 == 0 {
		kproto.network_log("ws-send", fmt.tprintf("opcode=%s bytes=%d counter=%d q_index=%d pending=%d", opcode, sent, state.ah_num, state.q_index, len(state.pending)))
	}
	if opcode == "q" { state.q_index += 1 }
	return true
}

krunker_ws_send :: proc(state: ^Krunker_WS_State, opcode: string) -> bool {
	return krunker_ws_send_internal(state, opcode, true)
}

krunker_ws_flush_pending :: proc(state: ^Krunker_WS_State) -> bool {
	for len(state.pending) > 0 {
		opcode := state.pending[0]
		if !krunker_ws_send_internal(state, opcode, false) { return state.send_blocked }
		delete(opcode)
		ordered_remove(&state.pending, 0)
	}
	return true
}

// Team selection is already confirmed in the lobby. Send the current class
// before one entry request, without delaying input after the server starts us.
KRUNKER_BOOTSTRAP_OPS := [?]string{"po", "class", "en"}

krunker_ws_bootstrap_tick :: proc(client: ^Client, send_control: proc(^Krunker_WS_State, string) -> bool = krunker_ws_send) {
	state := &client.krunker
	if !state.connected || !state.got_load || !state.ready_received || state.bootstrapped || !client.spawn_pending do return
	for state.bootstrap_step < len(KRUNKER_BOOTSTRAP_OPS) {
		opcode := KRUNKER_BOOTSTRAP_OPS[state.bootstrap_step]
		if !send_control(state, opcode) { state.connected = false; krunker_ws_set_status(client, "Krunker lobby bootstrap send failed; see logs/krunker-network.log"); return }
		state.bootstrap_step += 1
	}
	if state.bootstrap_step == len(KRUNKER_BOOTSTRAP_OPS) {
		state.bootstrapped = true
		state.input_sequence = max(state.input_sequence, 13)
		if !state.spawned && len(state.last_server_message) == 0 { krunker_ws_set_status(client, "Team/class selected; waiting for server spawn confirmation.") }
	}
}

krunker_ws_apply_world :: proc(client: ^Client, payload: []byte, send_control: proc(^Krunker_WS_State, string) -> bool = krunker_ws_send) {
	state := &client.krunker
	messages, counter, error_text := kproto.krunker_msgpack_decode_packet(payload)
	if len(error_text) != 0 {
		state.decode_errors += 1
		if state.decode_errors <= 20 { kproto.network_log("msgpack", fmt.tprintf("ERROR decode complete_message_bytes=%d error=%s count=%d", len(payload), error_text, state.decode_errors)) }
		return
	}
	for value in messages {
		packet, ok := value.([]kproto.Krunker_Msgpack_Value)
		if !ok || len(packet) == 0 do continue
		opcode, is_text := packet[0].(string)
		// Only suppress routine updates. A late disconnect/error/challenge must
		// remain visible after the initial packet trace has reached its limit.
		if state.rx_logged <= 40 || (opcode != "k" && opcode != "l" && opcode != "gmsg") {
			kproto.network_log("msgpack", fmt.tprintf("RECV opcode=%v args=%d trailer=%d complete_message_bytes=%d", packet[0], len(packet)-1, counter, len(payload)))
		}
		client.krunker_world.received_at = glfw.GetTime()
		applied := kproto.krunker_world_apply_packet(&client.krunker_world, packet)
		if is_text {
			switch opcode {
			case "load":
				if !state.got_load {
					state.got_load = true
					if !send_control(state, "load") { state.connected = false; return }
					krunker_ws_set_status(client, "Krunker connected; loading lobby...")
				}
			case "io-init":
				kproto.network_log("ownership", fmt.tprintf("socket identity accepted=%v string_id=%v (value redacted); waiting for numeric player SID", applied, len(client.krunker_world.local_socket_id) > 0))
			case "uid":
				kproto.network_log("ownership", fmt.tprintf("lobby connection identity accepted=%v (value redacted)", applied))
			case "cd", "cda":
				for player in client.krunker_world.lobby_players {
					if player.id == client.krunker_world.local_connection_uid {
						kproto.network_log("lobby-selection", fmt.tprintf("server team=%d class=%d requested_team=%d pending=%v", player.team, player.class_index, client.requested_team, client.team_pending))
					}
				}
			case "pi":
				// SOCKET_PING is answered with the application PING (po), even
				// while the player is choosing a team/class in the lobby.
				if !send_control(state, "po") { state.connected = false; return }
			case "init":
				state.spawned = false
				kproto.network_log("world", fmt.tprintf("init map=%d mode=%d comp=%v ranked=%v", client.krunker_world.map_index, client.krunker_world.mode_index, client.krunker_world.is_comp, client.krunker_world.is_ranked))
			case "ready":
				state.ready_received = client.krunker_world.ready
				if !state.ready_received { state.connected = false; krunker_ws_set_status(client, "Lobby sent ready(false); connection rejected."); return }
				krunker_ws_set_status(client, "Lobby ready. Choose a team and class, then enter game.")
			case "start":
				kproto.network_log("spawn", fmt.tprintf("server start received; local_sid=%d players=%d; waiting for renderer handoff", client.krunker_world.local_sid, len(client.krunker_world.players)))
				state.input_sequence = max(state.input_sequence, 13)
				if !state.spawned { krunker_ws_set_status(client, "Server confirmed entry; waiting for local player position...") }
			case "l":
				state.snapshots_received += 1
				if state.snapshots_received <= 3 || state.snapshots_received % 120 == 0 {
					kproto.network_log("server-sync", fmt.tprintf("local snapshot=%d live_inputs_sent=%d; responding with v", state.snapshots_received, state.input_logged))
				}
				// Browser answers each local snapshot, including l(0), with PONG.
				if !send_control(state, "v") { state.connected = false; return }
			case "dc", "error":
				kproto.network_log("server-error", fmt.tprintf("opcode=%s args=%v", opcode, packet[1:]))
				reason := "Server did not supply a text reason"
				if len(packet) > 1 { if text, ok := packet[1].(string); ok && len(text) > 0 { reason = text } }
				client.team_pending = false
				client.spawn_pending = false
				client.requested_team = client.lobby_team
				client_selection_status(client, reason)
				delete(state.server_error)
				state.server_error = strings.clone(reason)
				krunker_ws_set_status(client, fmt.tprintf("Krunker %s: %s; see logs/krunker-network.log", opcode == "dc" ? "disconnected" : "error", reason))
				if opcode == "dc" { state.connected = false; return }
			case "cpt":
				kproto.network_log("server-error", "server requested a CAPTCHA challenge; native challenge response is not implemented")
				krunker_ws_set_status(client, "Krunker requested a CAPTCHA; see logs/krunker-network.log")
			case "gmsg", "fe":
				if len(packet) > 1 {
					if message, ok := packet[1].(string); ok && (message != state.last_server_message || opcode == "fe") {
						delete(state.last_server_message)
						state.last_server_message = strings.clone(message)
						kproto.network_log("server-message", fmt.tprintf("opcode=%s message=%s", opcode, message))
						if !state.spawned {
							if message == "wt" { krunker_ws_set_status(client, "Connected to lobby; server is waiting for players before spawning.") }
							else if opcode == "fe" { client.spawn_pending = false; client.team_pending = false; client.requested_team = client.lobby_team; client_selection_status(client, message); krunker_ws_set_status(client, fmt.tprintf("Server entry response: %s; see logs/krunker-network.log", message)) }
							else if len(message) > 0 { krunker_ws_set_status(client, fmt.tprintf("Lobby: %s", message)) }
						}
					}
				}
			case "f":
				kproto.network_log("input", fmt.tprintf("server reported input synchronization failure args=%v; next q will reset input synchronization", packet[1:]))
				krunker_client_reset_prediction(client)
				state.input_reset = true
			}
		}
		if applied { krunker_client_sync_world(client) }
	}
}

// Encoding is side-effect free: E_AGAIN and pending control messages must keep
// the reset flag, commands, and packet counter for the eventual successful send.
krunker_ws_encode_input :: proc(state: ^Krunker_WS_State) -> ([]byte, bool) {
	count := min(len(state.input_commands), kproto.KRUNKER_MAX_INPUT_BATCH)
	counter := kproto.krunker_msgpack_counter_next(state.ah_num, "q")
	return kproto.krunker_input_encode_batch(state.input_commands[:count], counter, false, state.input_reset)
}

krunker_ws_input_sent :: proc(state: ^Krunker_WS_State, count: int, counter: u8) {
	state.ah_num = counter
	state.input_reset = false
	copy(state.input_commands[:], state.input_commands[count:])
	resize(&state.input_commands, len(state.input_commands)-count)
	state.send_elapsed = max(0, state.send_elapsed - KRUNKER_SEND_SECONDS)
	state.input_logged += 1
}

krunker_ws_send_input :: proc(client: ^Client) {
	state := &client.krunker
	if !state.connected || !state.spawned || !state.bootstrapped do return
	if state.send_elapsed < KRUNKER_SEND_SECONDS || len(state.pending) > 0 || len(state.input_commands) == 0 do return
	count := min(len(state.input_commands), kproto.KRUNKER_MAX_INPUT_BATCH)
	first_sequence := state.input_commands[0].seq
	counter := kproto.krunker_msgpack_counter_next(state.ah_num, "q")
	reset := state.input_reset
	packet, ok := krunker_ws_encode_input(state)
	if !ok { krunker_ws_set_status(client, "Could not encode live movement input."); state.connected = false; return }
	defer delete(packet)
	sent: c.size_t
	code := curl.ws_send(state.handle, rawptr(&packet[0]), c.size_t(len(packet)), &sent, 0, curl.WS_BINARY)
	if code == .E_AGAIN && sent == 0 do return
	if code != .E_OK || int(sent) != len(packet) {
		kproto.network_log("input", fmt.tprintf("ERROR q curl=%v sent=%d expected=%d", code, sent, len(packet)))
		krunker_ws_set_status(client, "Live input send failed; see logs/krunker-network.log")
		state.connected = false
		return
	}
	// Keep commands intact on E_AGAIN; only successful sends consume the queue.
	krunker_ws_input_sent(state, count, counter)
	if reset || state.input_logged <= 3 || state.input_logged % 120 == 0 { kproto.network_log("input", fmt.tprintf("SENT live q seq=%d samples=%d last_seq=%d bytes=%d counter=%d reset=%v", first_sequence, count, first_sequence+i32(count)-1, sent, counter, reset)) }
}

krunker_ws_poll :: proc(client: ^Client) {
	state := &client.krunker
	if !state.connected do return
	if !krunker_ws_flush_pending(state) { state.connected = false; krunker_ws_set_status(client, "Krunker WebSocket send failed."); return }
	buffer: [4096]byte
	for iterations := 0; iterations < 8; iterations += 1 {
		received: c.size_t
		meta: ^curl.ws_frame
		code := curl.ws_recv(state.handle, rawptr(&buffer[0]), c.size_t(len(buffer)), &received, &meta)
		if code == .E_AGAIN do break
		if code != .E_OK {
			kproto.network_log("ws-recv", fmt.tprintf("ERROR curl=%v (%s) detail=%s got_load=%v bootstrapped=%v spawned=%v", code, string(curl.easy_strerror(code)), string(cast(cstring)&state.error_buffer[0]), state.got_load, state.bootstrapped, state.spawned))
			krunker_ws_set_status(client, fmt.tprintf("Krunker WebSocket receive failed: %v; see logs/krunker-network.log", code))
			state.connected = false
			break
		}
		state.rx_logged += 1
		if meta != nil && state.rx_logged <= 40 { kproto.network_log("ws-recv", fmt.tprintf("frame=%d bytes=%d flags=%d offset=%d bytesleft=%d (frame logging limited to first 40)", state.rx_logged, received, meta.flags, meta.offset, meta.bytesleft)) }
		if meta != nil && (meta.flags & curl.WS_CLOSE) == curl.WS_CLOSE {
			close_code := -1
			reason := ""
			if received >= 2 { close_code = int(buffer[0])*256 + int(buffer[1]); reason = string(buffer[2:int(received)]) }
			code_text := received >= 2 ? fmt.tprintf("%d", close_code) : "absent"
			kproto.network_log("ws-close", fmt.tprintf("code=%s reason=%s close_payload_bytes=%d got_load=%v bootstrapped=%v spawned=%v live_inputs_sent=%d local_snapshots=%d", code_text, reason, received, state.got_load, state.bootstrapped, state.spawned, state.input_logged, state.snapshots_received))
			if len(state.server_error) > 0 { krunker_ws_set_status(client, fmt.tprintf("Krunker disconnected: %s; see logs/krunker-network.log", state.server_error)) }
			else if received < 2 { krunker_ws_set_status(client, "Krunker lobby closed the WebSocket without a status or reason; see logs/krunker-network.log") }
			else { krunker_ws_set_status(client, fmt.tprintf("Krunker lobby closed the WebSocket: %d %s; see logs/krunker-network.log", close_code, reason)) }
			state.connected = false
			break
		}
		if received == 0 do break
		if meta == nil { krunker_ws_set_status(client, "WebSocket receive omitted frame metadata."); state.connected = false; break }
		if (meta.flags & (curl.WS_PING | curl.WS_PONG)) != {} { continue }
		if (meta.flags & curl.WS_TEXT) != {} { kproto.network_log("ws-recv", "ignoring unexpected text frame"); continue }
		payload, complete, assembly_error := kproto.krunker_ws_message_feed(&state.message, buffer[:int(received)], i64(meta.offset), i64(meta.bytesleft), (meta.flags & curl.WS_CONT) != {})
		if len(assembly_error) > 0 { krunker_ws_set_status(client, assembly_error); state.connected = false; break }
		if !complete do continue
		if len(payload) > len(buffer) { kproto.network_log("ws-message", fmt.tprintf("reassembled complete message bytes=%d", len(payload))) }
		krunker_ws_apply_world(client, payload)
		if !state.connected do break
	}
	krunker_ws_bootstrap_tick(client)
}

krunker_ws_disconnect :: proc(state: ^Krunker_WS_State) {
	if state.handle != nil { kproto.network_log("disconnect", fmt.tprintf("connected=%v got_load=%v bootstrapped=%v spawned=%v pending=%d", state.connected, state.got_load, state.bootstrapped, state.spawned, len(state.pending))) }
	if state.handle != nil { curl.easy_cleanup(state.handle) }
	if state.global_ready { curl.global_cleanup() }
	for opcode in state.pending { delete(opcode) }
	delete(state.pending)
	delete(state.ws_url)
	delete(state.upgrade_capture.body)
	delete(state.upgrade_capture.headers)
	delete(state.message.buffer)
	delete(state.player_revisions)
	delete(state.input_commands)
	delete(state.last_server_message)
	delete(state.server_error)
	state^ = {}
}

krunker_ws_connect :: proc(client: ^Client, link: ^shared.Join_Link) -> bool {
	krunker_ws_disconnect(&client.krunker)
	state := &client.krunker
	if curl.global_init(curl.GLOBAL_DEFAULT) != .E_OK { krunker_ws_set_status(client, "Could not initialize libcurl for Krunker WebSocket."); return false }
	state.global_ready = true
	kproto.network_log("curl", fmt.tprintf("library=%s", string(curl.version())))
	kproto.network_log("invite", fmt.tprintf("scheme=%s host=%s port=%d path=%s game=%s team_hint=%s", link.scheme, link.host, link.port, link.path, link.game_id, link.team_hint))
	url := ""
	if link.scheme == "http" || link.scheme == "https" || link.scheme == "game" {
		krunker_ws_set_status(client, "Resolving lobby through Krunker matchmaker…")
		resolved_url, ok, error_text := krunker_ws_resolve_invite(link)
		url = resolved_url
		if !ok { krunker_ws_set_status(client, error_text); krunker_ws_disconnect(state); return false }
	} else if link.scheme == "ws" || link.scheme == "wss" {
		url = strings.clone(link.raw)
	} else {
		krunker_ws_set_status(client, "This link is not a Krunker WebSocket or browser invite.")
		krunker_ws_disconnect(state)
		return false
	}
	defer delete(url)
	kproto.network_log("websocket", fmt.tprintf("CONNECT %s; awaiting lobby selection", url))
	handle := curl.easy_init()
	if handle == nil { krunker_ws_set_status(client, "Could not allocate the Krunker WebSocket handle."); krunker_ws_disconnect(state); return false }
	state.handle = handle
	state.ws_url = strings.clone(url)
	url_c := strings.clone_to_cstring(url)
	defer delete(url_c)
	headers: ^curl.slist
	origin := strings.clone_to_cstring("Origin: https://krunker.io")
	referer := strings.clone_to_cstring("Referer: https://krunker.io/")
	user_agent := strings.clone_to_cstring("User-Agent: Mozilla/5.0 (KrunkNative)")
	defer delete(origin); defer delete(referer); defer delete(user_agent)
	headers = curl.slist_append(headers, origin); headers = curl.slist_append(headers, referer); headers = curl.slist_append(headers, user_agent)
	defer curl.slist_free_all(headers)
	setup := []curl.code{
		curl.easy_setopt(handle, .ERRORBUFFER, rawptr(&state.error_buffer[0])),
		curl.easy_setopt(handle, .HEADERFUNCTION, curl.write_callback(kproto.network_http_header)),
		curl.easy_setopt(handle, .HEADERDATA, rawptr(&state.upgrade_capture)),
		curl.easy_setopt(handle, .WRITEFUNCTION, curl.write_callback(kproto.network_http_write)),
		curl.easy_setopt(handle, .WRITEDATA, rawptr(&state.upgrade_capture)),
		curl.easy_setopt(handle, .DEBUGFUNCTION, curl.debug_callback(kproto.network_http_debug)),
		curl.easy_setopt(handle, .VERBOSE, c.long(1)),
		curl.easy_setopt(handle, .URL, url_c),
		curl.easy_setopt(handle, .CONNECTTIMEOUT_MS, c.long(8000)),
		curl.easy_setopt(handle, .TIMEOUT_MS, c.long(1000)),
		curl.easy_setopt(handle, .CONNECT_ONLY, c.long(2)),
		curl.easy_setopt(handle, .HTTPHEADER, headers),
	}
	option_names := []string{"ERRORBUFFER", "HEADERFUNCTION", "HEADERDATA", "WRITEFUNCTION", "WRITEDATA", "DEBUGFUNCTION", "VERBOSE", "URL", "CONNECTTIMEOUT_MS", "TIMEOUT_MS", "CONNECT_ONLY", "HTTPHEADER"}
	for code, i in setup { if code != .E_OK { kproto.network_log("websocket", fmt.tprintf("ERROR curl option=%s code=%v (%s)", option_names[i], code, string(curl.easy_strerror(code)))); krunker_ws_set_status(client, "Could not configure WebSocket; see logs/krunker-network.log"); krunker_ws_disconnect(state); return false } }
	kproto.network_log("websocket", "upgrade connect_timeout=8000ms timeout=1000ms Origin=https://krunker.io Referer=https://krunker.io/ User-Agent=Mozilla/5.0 (KrunkNative)")
	code := curl.easy_perform(handle)
	status := kproto.network_http_info(handle, "websocket", code, string(cast(cstring)&state.error_buffer[0]))
	kproto.network_log("websocket", fmt.tprintf("upgrade response headers=%s body=%s", string(state.upgrade_capture.headers[:]), string(state.upgrade_capture.body[:])))
	if code != .E_OK {
		krunker_ws_set_status(client, fmt.tprintf("Krunker WebSocket upgrade failed: HTTP %d curl=%v; see logs/krunker-network.log", status, code)); krunker_ws_disconnect(state); return false
	}
	state.connected = true
	client_clear_players(client)
	client.game.is_local = false
	state.team = 0
	state.class_index = client.selected_class
	krunker_ws_set_status(client, "Krunker WebSocket connected; waiting for server load…")
	return true
}
