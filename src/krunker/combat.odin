package krunker

import "core:math"
import shared "../shared"

Krunker_World_Shot :: struct {
	sid: i32,
	origin, position: shared.Vec3,
	height: f32,
	has_surface: bool,
}

// UPDATE_AMMO replaces magazines by loadout slot. Ordinary shots/reloads are
// predicted by the browser; this message corrects pickups and server changes.
krunker_world_apply_ammo :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) -> bool {
	if len(packet) < 2 || state.local_sid < 0 { return false }
	values, ok := krunker_world_array(packet[1]); if !ok || len(values) == 0 || len(values) > 8 { return false }
	player := krunker_world_upsert_player(state, state.local_sid)
	player.ammo_count = len(values)
	for value, i in values { player.ammo[i] = krunker_world_i32(value, -1) }
	player.ammo_revision += 1
	player.revision += 1
	return true
}

// SHOW_TRACER: [sid, hitX/Y/Z, surfaceYaw/Pitch?, trail, x/y/height/z,
// bulletType, impactType]. Missing surface angles indicate a miss/player hit.
krunker_world_apply_shot :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) -> bool {
	if len(packet) < 2 { return false }
	values, ok := krunker_world_array(packet[1]); if !ok || len(values) < 11 { return false }
	shot := Krunker_World_Shot{sid = krunker_world_i32(values[0], -1)}
	if shot.sid < 0 { return false }
	indices := [?]int{1, 2, 3, 7, 8, 10, 9}
	numbers: [7]f32
	for index, i in indices {
		number, valid := krunker_world_number(values[index])
		if !valid || math.is_nan(number) || math.is_inf(number) || abs(number) > 1e7 { return false }
		numbers[i] = f32(number)
	}
	shot.position = {numbers[0], numbers[1], numbers[2]}
	shot.origin = {numbers[3], numbers[4], numbers[5]}
	shot.height = numbers[6]
	_, has_yaw := krunker_world_number(values[4])
	_, has_pitch := krunker_world_number(values[5])
	shot.has_surface = has_yaw && has_pitch
	if len(state.shots) >= 256 { ordered_remove(&state.shots, 0) }
	append(&state.shots, shot)
	return true
}
