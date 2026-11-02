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
		opcode, _ := packet[0].(string)
		numeric, _ := packet[0].(i64)
		if sid == state.local_sid && !player.life_ended && (opcode == "3" || numeric == 3) {
			// Browser deathDelay: 0xaf0 ms. Disconnects and round switches
			// do not impose a death cooldown; duplicate deaths do not extend it.
			state.respawn_available_at = state.received_at + 2.8
		}
		player.health = 0
		player.active = false
		player.life_ended = true
		if sid == state.local_sid { state.in_game = false }
		// REMOVE_PLAYER(2) has no death count; KILL_PLAYER(3) does.
		if (opcode == "3" || numeric == 3) && len(packet) > 2 {
			if deaths, ok := krunker_world_bounded_number(packet[2], 0, 2147483647); ok { player.deaths = u32(deaths) }
		}
		player.pose_count = 0
		player.revision += 1
		return true
	}
	return false
}
