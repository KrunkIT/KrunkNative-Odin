package krunker

import shared "../shared"
import "core:strings"

// INIT_GAME carries the actual lobby config as its seventh argument. Comp
// presets and custom hosts can change these independently of the map/mode.
krunker_world_apply_game_config :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value) {
	state.game_config = shared.DEFAULT_GAME_CONFIG
	state.lobby_capacity = 0
	state.lobby_select_team = true
	for &name in state.lobby_team_names { delete(name); name = "" }
	state.has_game_config = true
	if len(packet) <= 7 { return }
	entries, ok := packet[7].([]Krunker_Msgpack_Map_Entry)
	if !ok { return }
	config := &state.game_config
	for entry in entries {
		key, textual := entry.key.(string)
		if !textual { continue }
		switch key {
		case "maxPlayers": state.lobby_capacity = clamp(krunker_world_i32(entry.value), 0, 64)
		case "selTeam": state.lobby_select_team = krunker_world_bool(entry.value)
		case "team1Name", "team2Name":
			if name, named := entry.value.(string); named {
				index := key == "team1Name" ? 0 : 1
				delete(state.lobby_team_names[index]); state.lobby_team_names[index] = strings.clone(name)
			}
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
