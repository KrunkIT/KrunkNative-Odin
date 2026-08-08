package shared

import "core:math/rand"

game_clear_players :: proc(game: ^Game) {
	delete(game.players)
	game.player_count = 0
}

game_is_authority :: proc(game: ^Game) -> bool {
	return game != nil && (game.is_local || game.server != nil)
}

game_init_match :: proc(game: ^Game) {
	delete(game.objective_indices)
	game.match = {}
	game.match.phase = game.config.warmup_time > 0 ? .WARMUP : .LIVE
	game.match.phase_remaining = max(0.0, game.config.warmup_time)
	game.match.time_remaining = max(0.0, f32(game.config.game_time) * 60.0)
	game.match.objective.active_object_index = -1
	game.match.objective.active_zone = -1

	if game.map_inst == nil {
		return
	}

	for object, index in game.map_inst.objects {
		if object.score_zone || object.objective {
			append(&game.objective_indices, i32(index))
		}
	}

	if len(game.objective_indices) > 0 {
		game.match.objective.active_zone = 0
		game.match.objective.active_object_index = game.objective_indices[0]
		game.match.objective.rotation_remaining = max(1.0, game.config.objective_rotation_time)
	}
}

game_rotate_objective :: proc(game: ^Game) {
	if len(game.objective_indices) == 0 {
		return
	}

	next := (game.match.objective.active_zone + 1) % i32(len(game.objective_indices))
	game.match.objective.active_zone = next
	game.match.objective.active_object_index = game.objective_indices[next]
	game.match.objective.owner_team = 0
	game.match.objective.contested = false
	game.match.objective.score_accumulator = 0
	game.match.objective.rotation_remaining = max(1.0, game.config.objective_rotation_time)
}

game_update_objective :: proc(game: ^Game, delta: f32) {
	state := &game.match.objective
	if game.match.phase != .LIVE || state.active_object_index < 0 || state.active_object_index >= i32(len(game.map_inst.objects)) {
		return
	}

	state.rotation_remaining = max(0.0, state.rotation_remaining - delta)
	if state.rotation_remaining == 0 {
		game_rotate_objective(game)
		state = &game.match.objective
	}

	zone := game.map_inst.objects[state.active_object_index]
	occupants: [3]i32
	for player in game.players {
		if player.active && player.team > 0 && player.team < len(occupants) && player_collides(player, zone, 0.0) {
			occupants[player.team] += 1
		}
	}

	state.contested = occupants[1] > 0 && occupants[2] > 0
	if state.contested || occupants[1] == 0 && occupants[2] == 0 {
		state.owner_team = 0
		state.score_accumulator = 0
		return
	}

	state.owner_team = occupants[1] > 0 ? 1 : 2
	state.score_accumulator += delta * max(0.0, game.config.objective_score_rate)
	points := u32(state.score_accumulator)
	if points == 0 {
		return
	}

	state.score_accumulator -= f32(points)
	game.match.team_scores[state.owner_team] += points
	for player in game.players {
		if player.active && player.team == state.owner_team && player_collides(player, zone, 0.0) {
			player.score += points
		}
	}

	if game.config.score_limit > 0 && game.match.team_scores[state.owner_team] >= u32(game.config.score_limit) {
		game.match.phase = .ENDED
		game.move_lock = true
	}
}

game_update_match :: proc(game: ^Game, delta: f32) {
	if game.match.phase == .ENDED {
		return
	}

	if game.match.phase == .WARMUP {
		game.match.phase_remaining = max(0.0, game.match.phase_remaining - delta)
		if game.match.phase_remaining == 0 {
			game.match.phase = .LIVE
		}
		return
	}

	game.match.time_remaining = max(0.0, game.match.time_remaining - delta)
	game_update_objective(game, delta)
	if game.match.time_remaining == 0 {
		game.match.phase = .ENDED
		game.move_lock = true
	}
}

game_configure :: proc(game: ^Game, config: ^Game_Config, maps: []^Map, modes: []i32, weapons: []^Weapon, classes: []Class_Config) {
	if game.maps_list_owned {
		delete(game.maps_list)
		game.maps_list_owned = false
	}
	if config != nil {
		game.config = config^
	} else {
		game.config = DEFAULT_GAME_CONFIG
	}

	game.weapons = weapons if len(weapons) > 0 else g_weapons()
	game.classes = classes if len(classes) > 0 else CLASSES_LIST[:]

	// maps/modes handled at game_init via rotation
	game.maps_list = maps
	game.map_count = i32(len(maps))

	game.modes_list = modes if len(modes) > 0 else ROTATION_MODES[:]
	game.mode_count = i32(len(game.modes_list))
}

game_init :: proc(game: ^Game, map_index, mode_index: i32, is_local: bool) {
	game.ready = false
	game.is_local = is_local

	game_clear_players(game)

	if game.map_count == 0 {
		load_default_maps()

		if len(game.maps_list) == 0 {
			game.maps_list = make([]^Map, len(ROTATION_MAPS))
			game.maps_list_owned = true

			for r, i in ROTATION_MAPS {
				game.maps_list[i] = g_maps[r]
			}

			game.map_count = i32(len(game.maps_list))
		}
	}

	if game.map_count == 0 || game.mode_count == 0 {
		return
	}

	map_to_load := map_index if map_index >= 0 && map_index < i32(game.map_count) else rand_map_index(game.map_count)
	game.current_map_index = map_to_load
	if game.maps_list[map_to_load] == nil && game.maps_list_owned {
		game.maps_list[map_to_load] = load_default_map(ROTATION_MAPS[map_to_load])
	}
	map_changed := game.map_inst == nil || game.map_inst != game.maps_list[map_to_load]

	mode_to_load := mode_index if mode_index >= 0 && mode_index < i32(game.mode_count) else game.modes_list[rand.int_max(int(game.mode_count))]

	if map_changed {
		// The configured map list owns its maps. Render resources are released by
		// the client before switching; destroying a map here would leave a dangling
		// pointer in maps_list and make a later rotation unsafe.
		game.map_inst = game.maps_list[map_to_load]
	} else {
		map_reset(game.map_inst)
	}

	new_mode := mode_init(mode_to_load)

	if game.mode != nil {
		mode_fini(game.mode)
	}

	game.mode = new_mode

	if game.vote_kick != nil {
		free(game.vote_kick)
		game.vote_kick = nil
	}

	if game.mode == nil || game.map_inst == nil {
		return
	}

	game.ready = true
	game.move_lock = false
	game_init_match(game)
}

rand_map_index :: proc(map_count: i32) -> i32 {
	return i32(rand.int_max(int(map_count)))
}

game_tick :: proc(game: ^Game, now, delta: f32) {
	if !game.ready {
		return
	}

	if game.is_local || game.server != nil {
		game.now = now
		game_update_match(game, delta)
		if game.end_timer == 0 && game.nuke_timer != 0 {
			game.nuke_timer = max(0.0, game.nuke_timer - delta)

			if game.nuke_timer == 0 {
				nuke_reward := 0

				for player in game.players {
					if !player.active || player == game.nuke_player || (player.team != 0 && game.nuke_player.team == player.team) || player.god_mode {
						continue
					}

					kill_info := Player_Kill_Info{}

					nuke_reward += 50
					player_kill(player, game.nuke_player, &kill_info, true)
				}

				if nuke_reward != 0 {
					// TODO: score
				}
			}
		}

		if game.vote_kick != nil {
			game.vote_kick.timer = max(0.0, game.vote_kick.timer - delta)

			if game.vote_kick.timer == 0 {
				free(game.vote_kick)
				game.vote_kick = nil
			}
		}
	}

	for player in game.players {
		if game_is_authority(game) && !player.active && player.respawn_timer > 0 {
			player.respawn_timer = max(0.0, player.respawn_timer - delta)
			if player.respawn_timer == 0 && game.config.auto_respawn != 0 && game.match.phase == .LIVE {
				player_spawn(player, player.class_index)
			}
		}
		player_update(player, delta * game.config.delta_mlt)

		if player.position.y <= game.map_inst.death_y {
			player_kill(player, nil, nil, false)
		}
	}
}

game_players_add :: proc(game: ^Game, player: ^Player) {
	append(&game.players, player)
	game.player_count = i32(len(game.players))
}

game_players_remove :: proc(game: ^Game, player: ^Player) {
	for other, i in game.players {
		if other == player {
			unordered_remove(&game.players, i)
			game.player_count = i32(len(game.players))
			return
		}
	}
}

game_destroy :: proc(game: ^Game) {
	for player in game.players {
		player_destroy(player)
	}

	game_clear_players(game)
	delete(game.impacts)
	delete(game.objective_indices)

	if game.mode != nil {
		mode_fini(game.mode)
		game.mode = nil
	}

	if game.maps_list_owned {
		delete(game.maps_list)
		game.maps_list_owned = false
	}
}
