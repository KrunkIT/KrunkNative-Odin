package krunker

import shared "../shared"
import "core:math"
import "core:strings"

// Krunker_World_Player is the small, authoritative subset needed by the
// native client while the renderer is still backed by shared.Player.  The
// wire records are positional and contain many cosmetic fields; unknown
// values are intentionally ignored instead of being guessed.
Krunker_World_Player :: struct {
	sid:        i32,
	name: string,
	socket_id: string,
	team:       i32,
	class_index: i32,
	secondary_id: i32,
	secondary_revision: u64,
	loadout_revision: u64,
	score, kills, deaths: u32,
	noclip, frozen, unlimited_ammo: bool,
	speed_boost: f32,
	controls_revision: u64,
	position_revision: u64,
	life_ended: bool,
	health:     f32,
	max_health: f32,
	position:   shared.Vec3,
	velocity:   shared.Vec3,
	direction:  shared.Vec2,
	on_ground:  bool,
	on_ladder:  bool,
	on_terrain: bool,
	did_jump: bool,
	did_wall_jump: bool,
	on_wall: i32,
	slide_timer: f32,
	can_slide: bool,
	can_slide_timer: f32,
	cylinder_velocity: shared.Vec2,
	crouch_val: f32,
	aim_val:    f32,
	weapon_slot: i32,
	ping:       i32,
	active:     bool,
	has_position: bool,
	revision: u64,
	ack_seq: i32,
	has_ack: bool,
	sync_revision: u64,
	ammo: [8]i32,
	ammo_count: int,
	ammo_revision: u64,
	poses: [16]Krunker_World_Pose,
	pose_count: int,
	send_rate: f32,
}

Krunker_Countdown :: enum { NONE, WAITING, WARMUP, STARTING, INTERMISSION }

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
	game_config: shared.Game_Config,
	has_game_config: bool,
	server_time: f64,
	has_server_time: bool,
	sync_received_at, previous_sync_received_at: f64,
	has_previous_sync: bool,
	send_rate: f32,
	received_at: f64,
	local_sid:   i32,
	local_socket_id: string,
	local_connection_uid: string,
	map_revision: u64,
	players:     [dynamic]Krunker_World_Player,
	lobby_players: [dynamic]Krunker_Lobby_Player,
	lobby_capacity: i32,
	lobby_team_capacity: i32,
	lobby_select_team: bool,
	has_allowed_classes: bool,
	allowed_classes: [len(shared.CLASSES_LIST)]bool,
	limit_classes: bool,
	class_limits: [len(shared.CLASSES_LIST)]i32,
	lobby_team_names: [2]string,
	shots:       [dynamic]Krunker_World_Shot,
	match: shared.Match_State,
	has_match: bool,
	game_state: i32,
	timer_kind: i32,
	timer_text: string,
	timer_received_at, objective_received_at, lockout_received_at: f64,
	countdown: Krunker_Countdown,
	countdown_remaining: f32,
	countdown_received_at: f64,
	respawn_available_at: f64,
	final_round_counted: bool,
	objective_uid: i32,
	objective_occupants: i32,
	interact_progress, interact_manual_progress: f32,
	interact_manual_visible: bool,
	lives: i32,
	last_hit_at: f64,
	hit_revision: u64,
	hit_lethal: bool,
	winner_team, end_result: i32,
	rounds_total: u32,
	objective_weapon: i32,
	projectile_events: [dynamic]Krunker_Projectile_Event,
}

krunker_world_reset :: proc(state: ^Krunker_World_State) {
	for player in state.players { delete(player.name); delete(player.socket_id) }
	delete(state.players)
	krunker_lobby_clear(state)
	delete(state.lobby_players)
	for name in state.lobby_team_names { delete(name) }
	delete(state.shots)
	delete(state.projectile_events)
	delete(state.local_socket_id)
	delete(state.local_connection_uid)
	delete(state.timer_text)
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

// The browser uses 1 for hip fire and 0 for ADS; shared.Player uses the reverse.
krunker_world_aim :: proc(value: Krunker_Msgpack_Value, fallback: f32) -> f32 {
	if number, ok := krunker_world_number(value); ok { return clamp(1 - f32(number), 0, 1) }
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
	state.server_time, state.has_server_time = 0, false
	state.sync_received_at, state.previous_sync_received_at = 0, 0
	state.has_previous_sync, state.send_rate = false, 0
	krunker_world_apply_game_config(state, packet)
	for player in state.players { delete(player.name); delete(player.socket_id) }
	clear(&state.players)
	clear(&state.shots)
	state.in_game = false
	krunker_world_init_match(state, packet)
	state.mode_index = krunker_world_i32(packet[2], -1)
	state.is_comp = false
	state.is_ranked = false
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
		// START has no coordinates. A dead life's pose must not become the
		// new spawn while we wait for its roster/snapshot. A roster received
		// before START has already revived the player with fresh coordinates.
		if local.life_ended || !local.active { local.has_position = false }
		local.velocity, local.has_ack, local.pose_count = {}, false, 0
		local.team = krunker_world_i32(packet[2], local.team)
		if len(packet) > 8 { local.class_index = krunker_world_i32(packet[8], local.class_index) }
		local.active = true
		local.life_ended = false
		local.frozen, local.noclip, local.unlimited_ammo = false, false, false
		local.speed_boost = 0
		local.controls_revision += 1
		local.revision += 1
	}
	state.in_game = true
	state.respawn_available_at = 0
	if len(packet) > 1 { krunker_world_set_timer_text(state, packet[1]) }
	if len(packet) > 5 { state.move_lock = krunker_world_bool(packet[5]) }
	return true
}

// ADD_PLAYERS (opcode 0) contains flat records with a fixed stride of 53.
// Only fields used by the native simulation are copied.
krunker_world_apply_add_players :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) -> bool {
	if state.has_match && state.match.phase == .ENDED { return false }
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
		if name, named := records[offset+5].(string); named && name != player.name { delete(player.name); player.name = strings.clone(name) }
		if socket_id, ok := records[offset].(string); ok && socket_id == state.local_socket_id && len(socket_id) > 0 { state.local_sid = sid }
		if socket_id, ok := records[offset].(string); ok && socket_id != player.socket_id { delete(player.socket_id); player.socket_id = strings.clone(socket_id) }
		player.position = {krunker_world_f32(records[offset + 2]), krunker_world_f32(records[offset + 3]), krunker_world_f32(records[offset + 4])}
		player.has_position = true
		player.max_health = krunker_world_f32(records[offset + 8], player.max_health)
		// A nil roster health means full health, including on respawn.
		player.health = krunker_world_f32(records[offset + 7], player.max_health)
		player.team = krunker_world_i32(records[offset + 9], player.team)
		player.class_index = krunker_world_i32(records[offset + 6], player.class_index)
		player.secondary_id = krunker_world_i32(records[offset + 15], 2)
		player.secondary_revision += 1
		player.direction.y = krunker_world_f32(records[offset + 18], player.direction.y)
		player.active = true
		player.life_ended = false
		player.revision += 1
		player.pose_count = 0
		krunker_world_buffer_pose(player, state.received_at)
	}
	return true
}

// UPDATE_PLAYERS (opcode k) records are stride 13: sid, position, direction,
// step, onGround, crouch, weapon, aim, grapple, ping.
krunker_world_apply_update_players :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) -> bool {
	if state.has_match && state.match.phase == .ENDED { return false }
	if len(packet) < 2 { return false }
	if opcode, ok := packet[0].(string); !ok || opcode != "k" { return false }
	records, ok := krunker_world_array(packet[1])
	if !ok {
		if _, empty := packet[1].(Krunker_Msgpack_Nil); !empty && krunker_world_i32(packet[1], -1) != 0 { return false }
	}
	if len(packet) > 2 { state.send_rate = clamp(krunker_world_f32(packet[2], 10), 1, 128) }
	if len(packet) > 3 {
		if stamp, valid := krunker_world_number(packet[3]); valid && !math.is_nan(stamp) && !math.is_inf(stamp) && stamp >= 0 {
			state.previous_sync_received_at = state.sync_received_at
			state.has_previous_sync = state.has_server_time && state.received_at > state.sync_received_at
			state.sync_received_at = state.received_at
			state.server_time, state.has_server_time = stamp, true
		}
	}
	for offset := 0; offset + 13 <= len(records); offset += 13 {
		sid := krunker_world_i32(records[offset], -1)
		if sid < 0 { continue }
		player := krunker_world_upsert_player(state, sid)
		if player.life_ended { continue }
		player.position = {krunker_world_f32(records[offset + 1]), krunker_world_f32(records[offset + 2]), krunker_world_f32(records[offset + 3])}
		// k compresses angles to degrees. Roster and local l angles are radians.
		// The browser calls yaw xDire and pitch yDire; Vec2 is pitch/yaw.
		if pitch, ok := krunker_world_number(records[offset + 5]); ok { player.direction.x = f32(pitch) * math.PI / 180 }
		if yaw, ok := krunker_world_number(records[offset + 4]); ok { player.direction.y = f32(yaw) * math.PI / 180 }
		player.on_ground = krunker_world_bool(records[offset + 7])
		player.crouch_val = krunker_world_f32(records[offset + 8])
		player.weapon_slot = krunker_world_i32(records[offset + 9], player.weapon_slot)
		player.aim_val = krunker_world_aim(records[offset + 10], player.aim_val)
		player.ping = krunker_world_i32(records[offset + 12], player.ping)
		if len(packet) > 2 { player.send_rate = clamp(krunker_world_f32(packet[2], 10), 1, 128) }
		krunker_world_buffer_pose(player, state.received_at)
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
	if state.has_match && state.match.phase == .ENDED { return false }
	if len(packet) < 2 { return false }
	if opcode, ok := packet[0].(string); !ok || opcode != "l" { return false }
	values, ok := krunker_world_array(packet[1]); if !ok || len(values) < 18 { return false }
	if state.local_sid < 0 { return false }
	player := krunker_world_upsert_player(state, state.local_sid)
	if player.life_ended { return false }
	player.position = {krunker_world_f32(values[2]), krunker_world_f32(values[3]), krunker_world_f32(values[4])}
	player.ping = krunker_world_i32(values[1], player.ping)
	player.velocity = {krunker_world_f32(values[6]), krunker_world_f32(values[5]), krunker_world_f32(values[7])}
	player.direction.y = krunker_world_f32(values[8])
	player.weapon_slot = krunker_world_i32(values[17], player.weapon_slot)
	player.on_ground = krunker_world_bool(values[9])
	player.did_jump = krunker_world_bool(values[10])
	player.did_wall_jump = krunker_world_bool(values[11])
	player.on_wall = krunker_world_i32(values[13])
	player.on_ladder = krunker_world_bool(values[14])
	player.aim_val = krunker_world_aim(values[15], player.aim_val)
	player.crouch_val = krunker_world_f32(values[16])
	if len(values) > 18 { player.slide_timer = krunker_world_f32(values[18]) / 1000 }
	if len(values) > 19 { player.can_slide = krunker_world_bool(values[19]) }
	if len(values) > 20 { player.on_terrain = krunker_world_bool(values[20]) }
	if len(values) > 22 { player.cylinder_velocity = {krunker_world_f32(values[21]), krunker_world_f32(values[22])} }
	if len(values) > 24 { player.can_slide_timer = krunker_world_f32(values[24]) / 1000 }
	player.active = true
	player.has_position = true
	player.revision += 1
	player.ack_seq = krunker_world_i32(values[0], -1)
	player.has_ack = true
	player.sync_revision += 1
	return true
}

// REGEN_PLAYER carries the confirmed equipped loadout only when resetClass is
// true. A cosmetic/preferences update must not change live physics or refill it.
krunker_world_apply_regen :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) -> bool {
	if len(packet) < 4 { return false }
	items, valid := krunker_world_array(packet[3])
	if !valid || len(items) < 16 { return false }
	class := krunker_world_i32(items[15], -1)
	if class < 0 || int(class) >= len(shared.CLASSES_LIST) { return false }
	sid := krunker_world_i32(packet[1], -1)
	for &player in state.players {
		if player.sid != sid { continue }
		if !krunker_world_bool(packet[2]) { return true }
		player.class_index = class
		player.secondary_id = krunker_world_i32(items[14], 2)
		player.secondary_revision += 1
		player.loadout_revision += 1
		player.max_health = f32(shared.CLASSES_LIST[class].health) * (state.has_game_config ? state.game_config.health_mlt : 1)
		if !player.life_ended { player.health = player.max_health }
		player.weapon_slot, player.ammo_count = 0, 0
		player.velocity, player.cylinder_velocity = {}, {}
		player.did_jump, player.did_wall_jump, player.on_ladder, player.on_terrain = false, false, false, false
		player.on_wall, player.slide_timer, player.can_slide_timer = 0, 0, 0
		player.can_slide = true
		// l may still describe the old loadout. Do not replay it on regeneration.
		player.has_ack = false
		player.revision += 1
		return true
	}
	return false
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
	krunker_world_rebase_clocks(state)
	if numeric_opcode, numeric_ok := packet[0].(i64); numeric_ok {
		if numeric_opcode == 0 { return krunker_world_apply_add_players(state, packet) }
		if numeric_opcode == 9 { return krunker_world_apply_shot(state, packet) }
		if numeric_opcode == 2 || numeric_opcode == 3 { return krunker_world_apply_player_gone(state, packet) }
		if numeric_opcode >= 4 && numeric_opcode <= 7 {
			opcodes := [4]string{"4", "5", "6", "7"}
			return krunker_world_apply_gameplay(state, packet, opcodes[numeric_opcode-4])
		}
		return false
	}
	opcode, ok := packet[0].(string); if !ok { return false }
	switch opcode {
	case "uid":
		if len(packet) < 2 { return false }
		uid, valid := packet[1].(string)
		if !valid || len(uid) == 0 { return false }
		delete(state.local_connection_uid)
		state.local_connection_uid = strings.clone(uid)
		return true
	case "cd", "cda": return krunker_world_apply_lobby(state, packet)
	case "io-init": return krunker_world_apply_io_init(state, packet)
	case "init": return krunker_world_apply_init(state, packet)
	case "ready": return krunker_world_apply_ready(state, packet)
	case "start": return krunker_world_apply_start(state, packet)
	case "0": return krunker_world_apply_add_players(state, packet)
	case "k": return krunker_world_apply_update_players(state, packet)
	case "l": return krunker_world_apply_sync_player(state, packet)
	case "rg": return krunker_world_apply_regen(state, packet)
	case "uamo": return krunker_world_apply_ammo(state, packet)
	case "9": return krunker_world_apply_shot(state, packet)
	case "h": return krunker_world_apply_health(state, packet)
	case "2", "3": return krunker_world_apply_player_gone(state, packet)
	case "pr", "pre", "ex": return krunker_world_apply_projectile(state, packet, opcode)
	case: return krunker_world_apply_gameplay(state, packet, opcode)
	}
	return false
}
