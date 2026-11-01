package krunker

import shared "../shared"
import "core:strings"

// Krunker_World_Player is the small, authoritative subset needed by the
// native client while the renderer is still backed by shared.Player.  The
// wire records are positional and contain many cosmetic fields; unknown
// values are intentionally ignored instead of being guessed.
Krunker_World_Player :: struct {
	sid:        i32,
	team:       i32,
	class_index: i32,
	health:     f32,
	max_health: f32,
	position:   shared.Vec3,
	velocity:   shared.Vec3,
	direction:  shared.Vec2,
	on_ground:  bool,
	crouch_val: f32,
	aim_val:    f32,
	weapon:     i32,
	ping:       i32,
	active:     bool,
	has_position: bool,
	revision: u64,
	ack_seq: i32,
	has_ack: bool,
}

Krunker_World_State :: struct {
	map_index:   i32,
	mode_index:  i32,
	event_index: i32,
	session_id:  i32,
	round_id:    i32,
	is_comp:     bool,
	is_ranked:   bool,
	ready:       bool,
	in_game:     bool,
	move_lock:   bool,
	server_time: f64,
	local_sid:   i32,
	local_socket_id: string,
	map_revision: u64,
	players:     [dynamic]Krunker_World_Player,
}

krunker_world_reset :: proc(state: ^Krunker_World_State) {
	delete(state.players)
	delete(state.local_socket_id)
	state^ = {map_index = -1, mode_index = -1, event_index = -1, local_sid = -1}
}

krunker_world_number :: proc(value: Krunker_Msgpack_Value) -> (f64, bool) {
	#partial switch typed in value {
	case i64:
		return f64(typed), true
	case f64:
		return typed, true
	case bool:
		return typed ? 1 : 0, true
	case:
	}
	return 0, false
}

krunker_world_i32 :: proc(value: Krunker_Msgpack_Value, fallback: i32 = 0) -> i32 {
	if number, ok := krunker_world_number(value); ok { return i32(number) }
	return fallback
}

krunker_world_f32 :: proc(value: Krunker_Msgpack_Value, fallback: f32 = 0) -> f32 {
	if number, ok := krunker_world_number(value); ok { return f32(number) }
	return fallback
}

krunker_world_bool :: proc(value: Krunker_Msgpack_Value) -> bool {
	#partial switch typed in value {
	case bool:
		return typed
	case Krunker_Msgpack_Nil:
		return false
	case:
	}
	return krunker_world_i32(value) != 0
}

krunker_world_array :: proc(value: Krunker_Msgpack_Value) -> ([]Krunker_Msgpack_Value, bool) {
	if values, ok := value.([]Krunker_Msgpack_Value); ok { return values, true }
	return nil, false
}

krunker_world_upsert_player :: proc(state: ^Krunker_World_State, sid: i32) -> ^Krunker_World_Player {
	for &player in state.players {
		if player.sid == sid { return &player }
	}
	append(&state.players, Krunker_World_Player{sid = sid, health = 100, max_health = 100})
	return &state.players[len(state.players) - 1]
}

krunker_world_can_render_local :: proc(state: ^Krunker_World_State) -> bool {
	if !state.ready || !state.in_game || state.local_sid < 0 do return false
	for &player in state.players {
		if player.sid == state.local_sid { return player.active && player.has_position }
	}
	return false
}

// init positional arguments: map, mode, event, ... isComp, isRanked,
// sessionId, roundId.  The first array element is the opcode itself.
krunker_world_apply_init :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) -> bool {
	if len(packet) < 3 { return false }
	if opcode, ok := packet[0].(string); !ok || opcode != "init" { return false }
	state.map_index = krunker_world_i32(packet[1], -1)
	state.map_revision += 1
	clear(&state.players)
	state.in_game = false
	state.mode_index = krunker_world_i32(packet[2], -1)
	if len(packet) > 3 { state.event_index = krunker_world_i32(packet[3], -1) }
	if len(packet) > 16 { state.is_comp = krunker_world_bool(packet[16]) }
	if len(packet) > 17 { state.is_ranked = krunker_world_bool(packet[17]) }
	if len(packet) > 18 { state.session_id = krunker_world_i32(packet[18], 0) }
	if len(packet) > 19 { state.round_id = krunker_world_i32(packet[19], 0) }
	state.ready = true
	return true
}

krunker_world_apply_start :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) -> bool {
	if len(packet) < 3 { return false }
	if opcode, ok := packet[0].(string); !ok || opcode != "start" { return false }
	// start(timer, team, spectating, challengeMode, moveLock, ... classIndex)
	if len(packet) > 2 && state.local_sid >= 0 {
		local := krunker_world_upsert_player(state, state.local_sid)
		local.team = krunker_world_i32(packet[2], local.team)
		if len(packet) > 8 { local.class_index = krunker_world_i32(packet[8], local.class_index) }
		local.active = true
		local.revision += 1
	}
	state.in_game = true
	if len(packet) > 5 { state.move_lock = krunker_world_bool(packet[5]) }
	return true
}

// ADD_PLAYERS (opcode 0) contains flat records with a fixed stride of 53.
// Only fields used by the native simulation are copied.
krunker_world_apply_add_players :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) -> bool {
	if len(packet) < 2 { return false }
	opcode, numeric := packet[0].(i64)
	text, textual := packet[0].(string)
	if !(numeric && opcode == 0) && !(textual && text == "0") { return false }
	records, ok := krunker_world_array(packet[1]); if !ok { return false }
	stride := 53
	for offset := 0; offset + stride <= len(records); offset += stride {
		// record[0] is the connection/socket ID (usually a string); record[1]
		// is the numeric simulation SID used by k/l and renderer ownership.
		sid := krunker_world_i32(records[offset + 1], -1)
		if sid < 0 { continue }
		player := krunker_world_upsert_player(state, sid)
		if socket_id, ok := records[offset].(string); ok && socket_id == state.local_socket_id && len(socket_id) > 0 { state.local_sid = sid }
		player.position = {krunker_world_f32(records[offset + 2]), krunker_world_f32(records[offset + 3]), krunker_world_f32(records[offset + 4])}
		player.has_position = true
		player.health = krunker_world_f32(records[offset + 7], player.health)
		player.max_health = krunker_world_f32(records[offset + 8], player.max_health)
		player.team = krunker_world_i32(records[offset + 9], player.team)
		player.class_index = krunker_world_i32(records[offset + 6], player.class_index)
		player.direction.y = krunker_world_f32(records[offset + 18], player.direction.y)
		player.active = true
		player.revision += 1
	}
	return true
}

// UPDATE_PLAYERS (opcode k) records are stride 13: sid, position, direction,
// step, onGround, crouch, weapon, aim, grapple, ping.
krunker_world_apply_update_players :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) -> bool {
	if len(packet) < 2 { return false }
	if opcode, ok := packet[0].(string); !ok || opcode != "k" { return false }
	records, ok := krunker_world_array(packet[1]); if !ok { return false }
	if len(packet) > 3 { state.server_time, _ = krunker_world_number(packet[3]) }
	for offset := 0; offset + 13 <= len(records); offset += 13 {
		sid := krunker_world_i32(records[offset], -1)
		if sid < 0 { continue }
		player := krunker_world_upsert_player(state, sid)
		player.position = {krunker_world_f32(records[offset + 1]), krunker_world_f32(records[offset + 2]), krunker_world_f32(records[offset + 3])}
		// The wire calls yaw xDire and pitch yDire; shared.Vec2 is pitch/yaw.
		player.direction = {krunker_world_f32(records[offset + 5]), krunker_world_f32(records[offset + 4])}
		player.on_ground = krunker_world_bool(records[offset + 7])
		player.crouch_val = krunker_world_f32(records[offset + 8])
		player.weapon = krunker_world_i32(records[offset + 9], player.weapon)
		player.aim_val = krunker_world_f32(records[offset + 10])
		player.ping = krunker_world_i32(records[offset + 12], player.ping)
		player.active = true
		player.has_position = true
		player.revision += 1
	}
	return true
}

// SYNC_PLAYER (opcode l) is the local authoritative snapshot.  Its field
// positions are stable in the deobfuscated receiver and are kept separate
// from k's remote-player interpolation records.
krunker_world_apply_sync_player :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) -> bool {
	if len(packet) < 2 { return false }
	if opcode, ok := packet[0].(string); !ok || opcode != "l" { return false }
	values, ok := krunker_world_array(packet[1]); if !ok || len(values) < 18 { return false }
	if state.local_sid < 0 { return false }
	player := krunker_world_upsert_player(state, state.local_sid)
	player.position = {krunker_world_f32(values[2]), krunker_world_f32(values[3]), krunker_world_f32(values[4])}
	player.velocity = {krunker_world_f32(values[6]), krunker_world_f32(values[5]), krunker_world_f32(values[7])}
	player.direction.y = krunker_world_f32(values[8])
	player.weapon = krunker_world_i32(values[17], player.weapon)
	player.on_ground = krunker_world_bool(values[9])
	player.aim_val = krunker_world_f32(values[15])
	player.crouch_val = krunker_world_f32(values[16])
	player.active = true
	player.has_position = true
	player.revision += 1
	player.ack_seq = krunker_world_i32(values[0], -1)
	player.has_ack = true
	return true
}

krunker_world_apply_ready :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) -> bool {
	if len(packet) < 2 { return false }
	if opcode, ok := packet[0].(string); !ok || opcode != "ready" { return false }
	state.ready = krunker_world_bool(packet[1])
	if !state.ready { state.in_game = false; state.move_lock = true }
	return true
}

krunker_world_apply_io_init :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) -> bool {
	if len(packet) < 2 { return false }
	if opcode, ok := packet[0].(string); !ok || opcode != "io-init" { return false }
	if socket_id, ok := packet[1].(string); ok {
		delete(state.local_socket_id)
		state.local_socket_id = strings.clone(socket_id)
		state.local_sid = -1
		return len(socket_id) > 0
	}
	state.local_sid = krunker_world_i32(packet[1], -1)
	return state.local_sid >= 0
}

krunker_world_apply_packet :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) -> bool {
	if len(packet) == 0 { return false }
	if numeric_opcode, numeric_ok := packet[0].(i64); numeric_ok {
		if numeric_opcode == 0 { return krunker_world_apply_add_players(state, packet) }
		return false
	}
	opcode, ok := packet[0].(string); if !ok { return false }
	switch opcode {
	case "io-init": return krunker_world_apply_io_init(state, packet)
	case "init": return krunker_world_apply_init(state, packet)
	case "ready": return krunker_world_apply_ready(state, packet)
	case "start": return krunker_world_apply_start(state, packet)
	case "0": return krunker_world_apply_add_players(state, packet)
	case "k": return krunker_world_apply_update_players(state, packet)
	case "l": return krunker_world_apply_sync_player(state, packet)
	}
	return false
}
