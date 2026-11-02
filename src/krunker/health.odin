package krunker

import "core:math"

// CHANGE_HEALTH(health, sid?, hitX?, hitZ?, silent?, resetMax?). An omitted
// SID addresses the local player; remote health changes carry a numeric SID.
krunker_world_apply_health :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) -> bool {
	if len(packet) < 2 { return false }
	health, valid := krunker_world_number(packet[1])
	if !valid || math.is_nan(health) || math.is_inf(health) || health < 0 || health > 10000 { return false }
	sid := state.local_sid
	if len(packet) > 2 {
		if _, absent := packet[2].(Krunker_Msgpack_Nil); !absent { sid = krunker_world_i32(packet[2], -1) }
	}
	if sid < 0 { return false }
	player := krunker_world_upsert_player(state, sid)
	player.health = f32(health)
	if player.health > player.max_health || len(packet) > 6 && krunker_world_bool(packet[6]) {
		player.max_health = max(1, player.health)
	}
	player.revision += 1
	return true
}

// Death and disconnect messages must stop stale overhead bars immediately.
krunker_world_apply_player_gone :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) -> bool {
	if len(packet) < 2 { return false }
	sid := krunker_world_i32(packet[1], -1)
	for &player in state.players {
		if player.sid != sid { continue }
		player.health = 0
		player.active = false
		player.pose_count = 0
		player.revision += 1
		return true
	}
	return false
}
