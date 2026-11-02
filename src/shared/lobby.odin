package shared

import "core:encoding/endian"

Lobby_Player :: struct { id: u32, team, class_id: i32 }
Lobby_State :: struct {
	local_id: u32,
	team, capacity: i32,
	select_team: bool,
	// 0: no request, 1: accepted, 2: denied. Requests are serialized per client.
	team_result: u8,
	team_names: [2]string,
	count: int,
	players: [MAX_PLAYERS_PER_MATCH]Lobby_Player,
}

packet_serialize_team_request :: proc(buf: []byte, team: i32) -> int {
	if len(buf) < PACKET_HEADER_SIZE+4 { return 0 }
	endian.put_u32(buf[:4], .Little, PACKET_MAGIC)
	buf[4] = u8(Packet_Type.TEAM_REQUEST)
	endian.put_u16(buf[5:7], .Little, 4)
	endian.put_i32(buf[7:11], .Little, team)
	return 11
}

packet_deserialize_team_request :: proc(buf: []byte) -> (i32, bool) {
	h, ok := packet_deserialize_header(buf)
	if !ok || h.packet_type != .TEAM_REQUEST || h.payload_len != 4 || len(buf) != 11 { return 0, false }
	team, _ := endian.get_i32(buf[7:11], .Little)
	return team, team >= 0 && team <= 2
}

packet_serialize_lobby :: proc(buf: []byte, state: ^Lobby_State) -> int {
	count := clamp(state.count, 0, MAX_PLAYERS_PER_MATCH)
	size := 7 + 80 + count*12
	if len(buf) < size { return 0 }
	for &b in buf[:size] { b = 0 }
	endian.put_u32(buf[:4], .Little, PACKET_MAGIC)
	buf[4] = u8(Packet_Type.LOBBY_STATE)
	endian.put_u16(buf[5:7], .Little, u16(size-7))
	endian.put_u32(buf[7:11], .Little, state.local_id)
	endian.put_i32(buf[11:15], .Little, state.team)
	endian.put_i32(buf[15:19], .Little, state.capacity)
	buf[19] = state.select_team ? 1 : 0
	buf[20] = state.team_result
	buf[21] = u8(count)
	for name, i in state.team_names {
		length := min(31, len(name))
		copy(buf[23+i*32:23+i*32+length], transmute([]u8)name[:length])
	}
	for player, i in state.players[:count] {
		offset := 87+i*12
		endian.put_u32(buf[offset:offset+4], .Little, player.id)
		endian.put_i32(buf[offset+4:offset+8], .Little, player.team)
		endian.put_i32(buf[offset+8:offset+12], .Little, player.class_id)
	}
	return size
}

// Names reference the packet buffer; callers retaining a state must copy them.
packet_deserialize_lobby :: proc(buf: []byte) -> (state: Lobby_State, ok: bool) {
	h, valid := packet_deserialize_header(buf)
	if !valid || h.packet_type != .LOBBY_STATE || len(buf) < 87 { return }
	count := int(buf[21])
	if count > MAX_PLAYERS_PER_MATCH || len(buf) != 87+count*12 || int(h.payload_len) != len(buf)-7 { return }
	state.local_id, _ = endian.get_u32(buf[7:11], .Little)
	state.team, _ = endian.get_i32(buf[11:15], .Little)
	state.capacity, _ = endian.get_i32(buf[15:19], .Little)
	state.select_team = buf[19] != 0
	state.team_result = buf[20]
	state.count = count
	for i in 0..<2 {
		start := 23+i*32
		length := 0
		for length < 32 && buf[start+length] != 0 { length += 1 }
		state.team_names[i] = string(buf[start:start+length])
	}
	for &player, i in state.players[:count] {
		offset := 87+i*12
		player.id, _ = endian.get_u32(buf[offset:offset+4], .Little)
		player.team, _ = endian.get_i32(buf[offset+4:offset+8], .Little)
		player.class_id, _ = endian.get_i32(buf[offset+8:offset+12], .Little)
	}
	return state, true
}
