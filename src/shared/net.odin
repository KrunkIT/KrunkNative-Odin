package shared

import "core:encoding/endian"

PACKET_MAGIC :: 0x4B52554E // 'KRUN'
PACKET_HEADER_SIZE :: 7
PROTOCOL_VERSION :: 4
PACKET_PLAYER_STATE_PAYLOAD_SIZE :: 81
MAX_PLAYERS_PER_MATCH :: 32
// The server broadcasts one snapshot per N simulation ticks.
SNAPSHOT_RATE_DIVISOR :: 2
NET_SEND_QUEUE_CAPACITY :: 64 * 1024

// TCP may accept only a prefix before a non-blocking socket reports
// Would_Block. Keep that prefix accounted for and retry the exact remaining
// bytes later so packet boundaries are never corrupted.
Net_Send_Queue :: struct {
	data:  [NET_SEND_QUEUE_CAPACITY]byte,
	start: int,
	end:   int,
}

net_send_queue_pending :: proc(queue: ^Net_Send_Queue) -> []byte {
	if queue == nil || queue.start >= queue.end {
		return nil
	}
	return queue.data[queue.start:queue.end]
}

net_send_queue_push :: proc(queue: ^Net_Send_Queue, data: []byte) -> bool {
	if queue == nil || len(data) == 0 {
		return queue != nil
	}

	pending := queue.end - queue.start
	if len(data) > NET_SEND_QUEUE_CAPACITY - pending {
		return false
	}

	if queue.end + len(data) > NET_SEND_QUEUE_CAPACITY {
		copy(queue.data[:pending], queue.data[queue.start:queue.end])
		queue.start = 0
		queue.end = pending
	}

	copy(queue.data[queue.end:queue.end + len(data)], data)
	queue.end += len(data)
	return true
}

net_send_queue_consume :: proc(queue: ^Net_Send_Queue, count: int) {
	if queue == nil || count <= 0 {
		return
	}

	pending := queue.end - queue.start
	queue.start += min(count, pending)
	if queue.start >= queue.end {
		queue.start = 0
		queue.end = 0
	}
}

Packet_Type :: enum u8 {
	CONNECT      = 1,
	DISCONNECT   = 2,
	PLAYER_INPUT = 3,
	GAME_STATE   = 4,
	PING         = 5,
	CHAT         = 6,
	MATCH_STATE  = 7,
}

Packet_Header :: struct {
	magic:       u32,
	packet_type: Packet_Type,
	payload_len: u16,
}

// Matches the C Input struct field layout for player inputs.
Packet_Player_Input :: struct {
	seq:      i32,
	move_dir: i32,

	delta:    f32,
	x_dir:    f32,
	y_dir:    f32,

	flags:    u8,
}

packet_serialize_connect :: proc(buf: []byte, class_id: i32) -> int {
	if len(buf) < PACKET_HEADER_SIZE + 6 {
		return 0
	}
	endian.put_u32(buf[0:4], .Little, PACKET_MAGIC)
	buf[4] = u8(Packet_Type.CONNECT)
	endian.put_u16(buf[5:7], .Little, 6)
	endian.put_u16(buf[PACKET_HEADER_SIZE:PACKET_HEADER_SIZE + 2], .Little, PROTOCOL_VERSION)
	endian.put_i32(buf[PACKET_HEADER_SIZE + 2:PACKET_HEADER_SIZE + 6], .Little, class_id)
	return PACKET_HEADER_SIZE + 6
}

packet_deserialize_connect :: proc(buf: []byte) -> (class_id: i32, version: u16, ok: bool) {
	header, header_ok := packet_deserialize_header(buf)
	if !header_ok || header.packet_type != .CONNECT || header.payload_len != 6 || len(buf) != PACKET_HEADER_SIZE + 6 {
		return 0, 0, false
	}
	version, _ = endian.get_u16(buf[PACKET_HEADER_SIZE:PACKET_HEADER_SIZE + 2], .Little)
	class_id, _ = endian.get_i32(buf[PACKET_HEADER_SIZE + 2:PACKET_HEADER_SIZE + 6], .Little)
	return class_id, version, true
}

// Matches the C Player snapshot layout used for GAME_STATE.
Packet_Player_State :: struct {
	player_id: u32,
	active:    bool,
	is_you:    bool,
	team:      i32,
	class_id:  i32,
	position:  Vec3,
	velocity:  Vec3,
	x_dir:     f32,
	y_dir:     f32,
	on_ground: bool,
	on_ladder: bool,
	on_ramp: bool,
	on_terrain: bool,
	terrain_slipping: bool,
	did_jump: bool,
	did_wall_jump: bool,
	can_slide: bool,
	on_wall: u8,
	crouch_val: f32,
	aim_val: f32,
	slide_timer: f32,
	jump_timer: f32,
	health:    f32,
	max_health: i32,
	weapon_id: u8,
	active_ammo: u32,
	ack_seq:   i32,
}

packet_serialize_disconnect :: proc(buf: []byte) -> int {
	if len(buf) < PACKET_HEADER_SIZE {
		return 0
	}
	endian.put_u32(buf[0:4], .Little, PACKET_MAGIC)
	buf[4] = u8(Packet_Type.DISCONNECT)
	endian.put_u16(buf[5:7], .Little, 0)
	return PACKET_HEADER_SIZE
}

Packet_Match_State :: struct {
	phase:               Match_Phase,
	map_index:           i32,
	time_remaining:      f32,
	team1_score:         u32,
	team2_score:         u32,
	active_object_index: i32,
	active_zone:         i32,
	owner_team:          i32,
	contested:           bool,
	rotation_remaining:  f32,
	// Snapshot cadence the server is actually using; the client must
	// interpolate at this rate so motion stays smooth at any tick_rate.
	send_rate:           f32,
	player_count:        i32,
	player_ids:          [MAX_PLAYERS_PER_MATCH]u32,
}

packet_serialize_input :: proc(buf: []byte, input: ^Input) -> int {
	header_size := PACKET_HEADER_SIZE
	payload_size := 5 * 4 + 1 // seq + move_dir + delta + x_dir + y_dir + flags

	if len(buf) < header_size + payload_size {
		return 0
	}

	header := Packet_Header {
		magic       = PACKET_MAGIC,
		packet_type = .PLAYER_INPUT,
		payload_len = u16(payload_size),
	}

	endian.put_u32(buf[0:4], .Little, header.magic)
	buf[4] = u8(header.packet_type)
	endian.put_u16(buf[5:7], .Little, header.payload_len)

	offset := header_size

	endian.put_i32(buf[offset:offset + 4], .Little, input.seq)
	offset += 4

	endian.put_i32(buf[offset:offset + 4], .Little, input.move_dir)
	offset += 4

	endian.put_f32(buf[offset:offset + 4], .Little, input.delta)
	offset += 4

	endian.put_f32(buf[offset:offset + 4], .Little, input.x_dir)
	offset += 4

	endian.put_f32(buf[offset:offset + 4], .Little, input.y_dir)
	offset += 4

	flags: u8 = 0
	if input.shoot {
		flags |= 1
	}
	if input.scope {
		flags |= 2
	}
	if input.jump {
		flags |= 4
	}
	if input.crouch {
		flags |= 8
	}
	if input.reload {
		flags |= 16
	}
	flags |= u8((input.swap & 0x3) << 5)

	buf[offset] = flags
	offset += 1

	return offset
}

packet_deserialize_input :: proc(buf: []byte) -> (input: Input, ok: bool) {
	header_size := PACKET_HEADER_SIZE
	payload_size := 5 * 4 + 1

	if len(buf) < header_size + payload_size {
		return {}, false
	}

	offset := header_size

	input.seq, _ = endian.get_i32(buf[offset:offset + 4], .Little)
	offset += 4

	input.move_dir, _ = endian.get_i32(buf[offset:offset + 4], .Little)
	offset += 4

	input.delta, _ = endian.get_f32(buf[offset:offset + 4], .Little)
	offset += 4

	input.x_dir, _ = endian.get_f32(buf[offset:offset + 4], .Little)
	offset += 4

	input.y_dir, _ = endian.get_f32(buf[offset:offset + 4], .Little)
	offset += 4

	flags := buf[offset]

	input.shoot = (flags & 1) != 0
	input.scope = (flags & 2) != 0
	input.jump = (flags & 4) != 0
	input.crouch = (flags & 8) != 0
	input.reload = (flags & 16) != 0
	input.swap = u8((flags >> 5) & 0x3)

	return input, true
}

packet_serialize_state :: proc(buf: []byte, state: ^Packet_Player_State) -> int {
	header_size := PACKET_HEADER_SIZE
	payload_size := PACKET_PLAYER_STATE_PAYLOAD_SIZE

	if len(buf) < header_size + payload_size {
		return 0
	}

	header := Packet_Header {
		magic       = PACKET_MAGIC,
		packet_type = .GAME_STATE,
		payload_len = u16(payload_size),
	}

	endian.put_u32(buf[0:4], .Little, header.magic)
	buf[4] = u8(header.packet_type)
	endian.put_u16(buf[5:7], .Little, header.payload_len)

	offset := header_size

	endian.put_u32(buf[offset:offset + 4], .Little, state.player_id)
	offset += 4
	buf[offset] = state.active ? 1 : 0
	offset += 1
	buf[offset] = state.is_you ? 1 : 0
	offset += 1
	endian.put_i32(buf[offset:offset + 4], .Little, state.team)
	offset += 4
	endian.put_i32(buf[offset:offset + 4], .Little, state.class_id)
	offset += 4

	endian.put_f32(buf[offset:offset + 4], .Little, state.position.x)
	endian.put_f32(buf[offset + 4:offset + 8], .Little, state.position.y)
	endian.put_f32(buf[offset + 8:offset + 12], .Little, state.position.z)
	offset += 12

	endian.put_f32(buf[offset:offset + 4], .Little, state.velocity.x)
	endian.put_f32(buf[offset + 4:offset + 8], .Little, state.velocity.y)
	endian.put_f32(buf[offset + 8:offset + 12], .Little, state.velocity.z)
	offset += 12

	endian.put_f32(buf[offset:offset + 4], .Little, state.x_dir)
	offset += 4

	endian.put_f32(buf[offset:offset + 4], .Little, state.y_dir)
	offset += 4

	movement_flags: u8
	movement_flags |= state.on_ground ? 1 : 0
	movement_flags |= state.on_ladder ? 2 : 0
	movement_flags |= state.on_ramp ? 4 : 0
	movement_flags |= state.on_terrain ? 8 : 0
	movement_flags |= state.terrain_slipping ? 16 : 0
	movement_flags |= state.did_jump ? 32 : 0
	movement_flags |= state.did_wall_jump ? 64 : 0
	movement_flags |= state.can_slide ? 128 : 0
	buf[offset] = movement_flags
	offset += 1
	buf[offset] = state.on_wall
	offset += 1

	endian.put_f32(buf[offset:offset + 4], .Little, state.crouch_val)
	offset += 4
	endian.put_f32(buf[offset:offset + 4], .Little, state.aim_val)
	offset += 4
	endian.put_f32(buf[offset:offset + 4], .Little, state.slide_timer)
	offset += 4
	endian.put_f32(buf[offset:offset + 4], .Little, state.jump_timer)
	offset += 4

	endian.put_f32(buf[offset:offset + 4], .Little, state.health)
	offset += 4
	endian.put_i32(buf[offset:offset + 4], .Little, state.max_health)
	offset += 4

	buf[offset] = state.weapon_id
	offset += 1
	endian.put_u32(buf[offset:offset + 4], .Little, state.active_ammo)
	offset += 4
	endian.put_i32(buf[offset:offset + 4], .Little, state.ack_seq)
	offset += 4

	return offset
}

packet_deserialize_state :: proc(buf: []byte) -> (state: Packet_Player_State, ok: bool) {
	header_size := PACKET_HEADER_SIZE
	payload_size := PACKET_PLAYER_STATE_PAYLOAD_SIZE

	header, header_ok := packet_deserialize_header(buf)
	if !header_ok || header.packet_type != .GAME_STATE || header.payload_len != u16(payload_size) || len(buf) != header_size + payload_size {
		return {}, false
	}

	offset := header_size

	state.player_id, _ = endian.get_u32(buf[offset:offset + 4], .Little)
	offset += 4
	state.active = buf[offset] != 0
	offset += 1
	state.is_you = buf[offset] != 0
	offset += 1
	state.team, _ = endian.get_i32(buf[offset:offset + 4], .Little)
	offset += 4
	state.class_id, _ = endian.get_i32(buf[offset:offset + 4], .Little)
	offset += 4

	state.position.x, _ = endian.get_f32(buf[offset:offset + 4], .Little)
	state.position.y, _ = endian.get_f32(buf[offset + 4:offset + 8], .Little)
	state.position.z, _ = endian.get_f32(buf[offset + 8:offset + 12], .Little)
	offset += 12

	state.velocity.x, _ = endian.get_f32(buf[offset:offset + 4], .Little)
	state.velocity.y, _ = endian.get_f32(buf[offset + 4:offset + 8], .Little)
	state.velocity.z, _ = endian.get_f32(buf[offset + 8:offset + 12], .Little)
	offset += 12

	state.x_dir, _ = endian.get_f32(buf[offset:offset + 4], .Little)
	offset += 4

	state.y_dir, _ = endian.get_f32(buf[offset:offset + 4], .Little)
	offset += 4

	movement_flags := buf[offset]
	offset += 1
	state.on_ground = (movement_flags & 1) != 0
	state.on_ladder = (movement_flags & 2) != 0
	state.on_ramp = (movement_flags & 4) != 0
	state.on_terrain = (movement_flags & 8) != 0
	state.terrain_slipping = (movement_flags & 16) != 0
	state.did_jump = (movement_flags & 32) != 0
	state.did_wall_jump = (movement_flags & 64) != 0
	state.can_slide = (movement_flags & 128) != 0
	state.on_wall = buf[offset]
	offset += 1

	state.crouch_val, _ = endian.get_f32(buf[offset:offset + 4], .Little)
	offset += 4
	state.aim_val, _ = endian.get_f32(buf[offset:offset + 4], .Little)
	offset += 4
	state.slide_timer, _ = endian.get_f32(buf[offset:offset + 4], .Little)
	offset += 4
	state.jump_timer, _ = endian.get_f32(buf[offset:offset + 4], .Little)
	offset += 4

	state.health, _ = endian.get_f32(buf[offset:offset + 4], .Little)
	offset += 4
	state.max_health, _ = endian.get_i32(buf[offset:offset + 4], .Little)
	offset += 4

	state.weapon_id = buf[offset]
	offset += 1
	state.active_ammo, _ = endian.get_u32(buf[offset:offset + 4], .Little)
	offset += 4
	state.ack_seq, _ = endian.get_i32(buf[offset:offset + 4], .Little)

	return state, true
}

packet_deserialize_header :: proc(buf: []byte) -> (header: Packet_Header, ok: bool) {
	if len(buf) < PACKET_HEADER_SIZE {
		return {}, false
	}

	header.magic, _ = endian.get_u32(buf[0:4], .Little)
	if header.magic != PACKET_MAGIC {
		return {}, false
	}

	header.packet_type = Packet_Type(buf[4])
	header.payload_len, _ = endian.get_u16(buf[5:7], .Little)

	return header, true
}

packet_match_state_from_game :: proc(game: ^Game) -> Packet_Match_State {
	state := Packet_Match_State{
		phase               = game.match.phase,
		map_index           = game.current_map_index,
		time_remaining      = game.match.time_remaining,
		team1_score         = game.match.team_scores[1],
		team2_score         = game.match.team_scores[2],
		active_object_index = game.match.objective.active_object_index,
		active_zone         = game.match.objective.active_zone,
		owner_team          = game.match.objective.owner_team,
		contested           = game.match.objective.contested,
		rotation_remaining  = game.match.objective.rotation_remaining,
	}

	// Authoritative roster: every player the server still tracks. Clients use
	// this list to drop ghosts when someone disconnects.
	state.player_count = min(i32(len(game.players)), MAX_PLAYERS_PER_MATCH)
	for i in 0 ..< state.player_count {
		state.player_ids[i] = u32(game.players[i].uid)
	}
	return state
}

packet_apply_match_state :: proc(game: ^Game, state: ^Packet_Match_State) {
	game.match.phase = state.phase
	game.current_map_index = state.map_index
	game.match.time_remaining = state.time_remaining
	game.match.team_scores[1] = state.team1_score
	game.match.team_scores[2] = state.team2_score
	game.match.objective.active_object_index = state.active_object_index
	game.match.objective.active_zone = state.active_zone
	game.match.objective.owner_team = state.owner_team
	game.match.objective.contested = state.contested
	game.match.objective.rotation_remaining = state.rotation_remaining
}

packet_serialize_match_state :: proc(buf: []byte, state: ^Packet_Match_State) -> int {
	count := clamp(state.player_count, 0, MAX_PLAYERS_PER_MATCH)
	payload_size := 42 + int(count) * 4
	if len(buf) < PACKET_HEADER_SIZE + payload_size {
		return 0
	}

	endian.put_u32(buf[0:4], .Little, PACKET_MAGIC)
	buf[4] = u8(Packet_Type.MATCH_STATE)
	endian.put_u16(buf[5:7], .Little, u16(payload_size))
	offset := PACKET_HEADER_SIZE
	buf[offset] = u8(state.phase); offset += 1
	endian.put_i32(buf[offset:offset + 4], .Little, state.map_index); offset += 4
	endian.put_f32(buf[offset:offset + 4], .Little, state.time_remaining); offset += 4
	endian.put_u32(buf[offset:offset + 4], .Little, state.team1_score); offset += 4
	endian.put_u32(buf[offset:offset + 4], .Little, state.team2_score); offset += 4
	endian.put_i32(buf[offset:offset + 4], .Little, state.active_object_index); offset += 4
	endian.put_i32(buf[offset:offset + 4], .Little, state.active_zone); offset += 4
	endian.put_i32(buf[offset:offset + 4], .Little, state.owner_team); offset += 4
	buf[offset] = state.contested ? 1 : 0; offset += 1
	endian.put_f32(buf[offset:offset + 4], .Little, state.rotation_remaining); offset += 4
	endian.put_f32(buf[offset:offset + 4], .Little, state.send_rate); offset += 4
	endian.put_i32(buf[offset:offset + 4], .Little, count); offset += 4
	for i in 0 ..< count {
		endian.put_u32(buf[offset:offset + 4], .Little, state.player_ids[i])
		offset += 4
	}
	return offset
}

packet_deserialize_match_state :: proc(buf: []byte) -> (state: Packet_Match_State, ok: bool) {
	header, header_ok := packet_deserialize_header(buf)
	if !header_ok || header.packet_type != .MATCH_STATE || header.payload_len < 42 || len(buf) < PACKET_HEADER_SIZE + 42 {
		return {}, false
	}

	offset := PACKET_HEADER_SIZE
	state.phase = Match_Phase(buf[offset]); offset += 1
	state.map_index, _ = endian.get_i32(buf[offset:offset + 4], .Little); offset += 4
	state.time_remaining, _ = endian.get_f32(buf[offset:offset + 4], .Little); offset += 4
	state.team1_score, _ = endian.get_u32(buf[offset:offset + 4], .Little); offset += 4
	state.team2_score, _ = endian.get_u32(buf[offset:offset + 4], .Little); offset += 4
	state.active_object_index, _ = endian.get_i32(buf[offset:offset + 4], .Little); offset += 4
	state.active_zone, _ = endian.get_i32(buf[offset:offset + 4], .Little); offset += 4
	state.owner_team, _ = endian.get_i32(buf[offset:offset + 4], .Little); offset += 4
	state.contested = buf[offset] != 0; offset += 1
	state.rotation_remaining, _ = endian.get_f32(buf[offset:offset + 4], .Little); offset += 4
	state.send_rate, _ = endian.get_f32(buf[offset:offset + 4], .Little); offset += 4

	count, _ := endian.get_i32(buf[offset:offset + 4], .Little)
	offset += 4
	if count < 0 || count > MAX_PLAYERS_PER_MATCH {
		return {}, false
	}
	if int(header.payload_len) != 42 + int(count) * 4 || len(buf) != PACKET_HEADER_SIZE + 42 + int(count) * 4 {
		return {}, false
	}
	state.player_count = count
	for i in 0 ..< count {
		state.player_ids[i], _ = endian.get_u32(buf[offset:offset + 4], .Little)
		offset += 4
	}
	return state, true
}

// Networking hooks — the C port declares these as SHIMs; keep the same contracts.
player_send_event :: proc() {
	// SHIM
}

game_broadcast :: proc() {
	// SHIM
}
