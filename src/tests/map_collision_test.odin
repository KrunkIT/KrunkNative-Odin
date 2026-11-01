package main

import "core:encoding/json"
import "core:fmt"
import shared "../shared"

// Exercise actual exported collision objects in isolation, so other map
// geometry cannot mask a missing collider. Use both movement entry points.
test_map_collision_drop :: proc(object: ^shared.Object, config: shared.Map_Config, predicted: bool) -> bool {
	map_inst := shared.Map{death_y = -10000, config = config}
	append(&map_inst.objects, object)
	defer delete(map_inst.objects)
	maps := []^shared.Map{&map_inst}
	game := shared.Game{}
	shared.game_configure(&game, nil, maps, nil, nil, nil)
	shared.game_init(&game, 0, 0, predicted)
	defer shared.game_destroy(&game)
	if !predicted do game.server = rawptr(&game)
	player := shared.player_init(&game)
	shared.game_players_add(&game, player)
	shared.player_spawn(player, 2)
	top := object.position.y + object.scale.y
	player.position = {object.position.x, top + 20, object.position.z}
	player.last_position = player.position
	player.velocity = {}
	player.on_ground = false
	for tick in 0 ..< 128 {
		input := shared.Input{delta = PHYSICS_DT, move_dir = -1}
		if predicted {
			shared.player_proc_input(player, &input, true, false)
		} else {
			shared.player_queue_input(player, &input)
			shared.game_tick(&game, f32(tick + 1) * PHYSICS_DT, PHYSICS_DT)
		}
	}
	if !player.on_ground || abs(player.position.y - top) > 0.01 || abs(player.velocity.y) > 0.001 {
		fmt.eprintf("Sandstorm hidden collider drop failed: object=%v predicted=%v expected_y=%f actual_y=%f grounded=%v\n",
			object.position, predicted, top, player.position.y, player.on_ground)
		return false
	}
	return true
}

test_sandstorm_hidden_colliders :: proc() -> bool {
	path := shared.concat(shared.assets_path(), "maps/sandstorm_v3.json")
	defer delete(path)
	map_inst, loaded := shared.map_load_from_file(path)
	if !loaded {
		fmt.eprintln("Sandstorm collision test: could not load map")
		return false
	}
	defer shared.map_destroy(map_inst)

	hidden_count, drop_count, decoration_count := 0, 0, 0
	for object in map_inst.objects {
		if object.prefab != .CUBE do continue
		raw := object.raw_data.(json.Object)
		if "l" in raw || "col" in raw {
			if object.collision_type != .NONE {
				fmt.eprintf("Sandstorm collision test: decoration became solid at %v\n", object.position)
				return false
			}
			decoration_count += 1
			continue
		}
		if !("v" in raw) do continue
		hidden_count += 1
		if !object.is_border {
			if !test_map_collision_drop(object, map_inst.config, true) || !test_map_collision_drop(object, map_inst.config, false) {
				return false
			}
			drop_count += 1
		}
		if object.collision_type != .BOX {
			fmt.eprintf("Sandstorm collision test: hidden block lost its collision at %v\n", object.position)
			return false
		}
	}
	if hidden_count != 46 || drop_count != 4 || decoration_count != 681 {
		fmt.eprintf("Sandstorm collision coverage changed: hidden=%d drop=%d decoration=%d\n", hidden_count, drop_count, decoration_count)
		return false
	}
	fmt.println("Sandstorm hidden collider landing/prediction/authority tests OK")
	return true
}
