package shared

import "core:encoding/endian"

PACKET_MAGIC :: 0x4B52554E // 'KRUN'

Packet_Type :: enum u8 {
	CONNECT      = 1,
	DISCONNECT   = 2,
	PLAYER_INPUT = 3,
	GAME_STATE   = 4,
	PING         = 5,
	CHAT         = 6,
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

// Matches the C Player snapshot layout used for GAME_STATE.
Packet_Player_State :: struct {
	player_id: u32,
	position:  Vec3,
	velocity:  Vec3,
	x_dir:     f32,
	y_dir:     f32,
	health:    i32,
	weapon_id: u8,
}

packet_serialize_input :: proc(buf: []byte, input: ^Input) -> int {
	header_size := size_of(Packet_Header)
	payload_size := 4 * 4 + 1 // seq + move_dir + delta + x_dir + y_dir + flags

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
	header_size := size_of(Packet_Header)
	payload_size := 4 * 4 + 1

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
	header_size := size_of(Packet_Header)
	payload_size := 4 + size_of(Vec3) + size_of(Vec3) + 4 + 4 + 4 + 1

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

	endian.put_i32(buf[offset:offset + 4], .Little, state.health)
	offset += 4

	buf[offset] = state.weapon_id
	offset += 1

	return offset
}

packet_deserialize_state :: proc(buf: []byte) -> (state: Packet_Player_State, ok: bool) {
	header_size := size_of(Packet_Header)
	payload_size := 4 + size_of(Vec3) + size_of(Vec3) + 4 + 4 + 4 + 1

	if len(buf) < header_size + payload_size {
		return {}, false
	}

	offset := header_size

	state.player_id, _ = endian.get_u32(buf[offset:offset + 4], .Little)
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

	state.health, _ = endian.get_i32(buf[offset:offset + 4], .Little)
	offset += 4

	state.weapon_id = buf[offset]

	return state, true
}

packet_deserialize_header :: proc(buf: []byte) -> (header: Packet_Header, ok: bool) {
	if len(buf) < size_of(Packet_Header) {
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

// Networking hooks — the C port declares these as SHIMs; keep the same contracts.
player_send_event :: proc() {
	// SHIM
}

game_broadcast :: proc() {
	// SHIM
}
