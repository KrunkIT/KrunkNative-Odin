package shared

import "core:math/rand"

game_clear_players :: proc(game: ^Game) {
	delete(game.players)
	game.player_count = 0
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
}

rand_map_index :: proc(map_count: i32) -> i32 {
	return i32(rand.int_max(int(map_count)))
}

game_tick :: proc(game: ^Game, now, delta: f32) {
	if !game.ready {
		return
	}

	if game.is_local || game.server != nil {
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

game_destroy :: proc(game: ^Game) {
	for player in game.players {
		player_destroy(player)
	}

	game_clear_players(game)
	delete(game.impacts)

	if game.mode != nil {
		mode_fini(game.mode)
		game.mode = nil
	}

	if game.maps_list_owned {
		delete(game.maps_list)
		game.maps_list_owned = false
	}
}
