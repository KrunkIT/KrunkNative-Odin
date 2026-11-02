package krunker

import shared "../shared"

// INIT_GAME carries the actual lobby config as its seventh argument. Comp
// presets and custom hosts can change these independently of the map/mode.
krunker_world_apply_game_config :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) {
	state.game_config = shared.DEFAULT_GAME_CONFIG
	state.has_game_config = true
	if len(packet) <= 7 { return }
	entries, ok := packet[7].([]Krunker_Msgpack_Map_Entry)
	if !ok { return }
	config := &state.game_config
	for entry in entries {
		key, textual := entry.key.(string)
		if !textual { continue }
		switch key {
		case "fixMov": config.fixed_movement = krunker_world_bool(entry.value)
		case "strafeSpd": config.strafe_speed = krunker_world_f32(entry.value, 1.2)
		case "gravMlt": config.gravity_mlt = krunker_world_f32(entry.value, 1)
		case "jumpMlt": config.jump_mlt = krunker_world_f32(entry.value, 1)
		case "deltaMlt": config.delta_mlt = krunker_world_f32(entry.value, 1)
		case "slidTime": config.slide_time = krunker_world_f32(entry.value, 1)
		case "slidSpd": config.slide_speed = krunker_world_f32(entry.value, 1)
		case "wallJP": config.wall_jump = krunker_world_f32(entry.value, 1)
		case "canSlide": config.can_slide = krunker_world_bool(entry.value)
		case "autoJump": config.auto_jump = krunker_world_bool(entry.value)
		case "airStrf": config.air_strafe = krunker_world_bool(entry.value)
		case "throwMel": config.throwable_melees = krunker_world_bool(entry.value)
		}
	}
}
