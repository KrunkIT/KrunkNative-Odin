package main

import "core:fmt"
import "core:math"

import shared "../shared"

PHYSICS_DT :: f32(1.0 / 64.0)


physics_game_init :: proc(game: ^shared.Game, map_inst: ^shared.Map, is_local: bool) -> ^shared.Player {
	maps := []^shared.Map{map_inst}
	shared.game_configure(game, nil, maps, nil, nil, nil)
	shared.game_init(game, 0, 0, is_local)

	player := shared.player_init(game)
	shared.game_players_add(game, player)
	shared.player_spawn(player, 0)
	player.swap_timer = 0
	return player
}

test_server_physics :: proc() -> bool {
	map_inst := shared.Map{death_y = -100, config = shared.Map_Config{speed = {1, 1, 1}, air_accel = 1, ladder_accel = 1, slide_time = 1, slide_accel = 1}}
	floor := shared.Object{
		active = true,
		collision_type = .BOX,
		position = {0, 0, 0},
		scale = {100, 1, 100},
	}
	wall := shared.Object{
		active = true,
		collision_type = .BOX,
		position = {0, 1, 0},
		scale = {1, 20, 100},
	}
	append(&map_inst.objects, &floor, &wall)

	game := shared.Game{}
	player := physics_game_init(&game, &map_inst, false)
	// Dedicated servers set this opaque authority handle during startup. The
	// simulation only needs it to distinguish authoritative updates from a
	// non-authoritative client replica.
	game.server = rawptr(&game)
	defer shared.game_destroy(&game)

	// Start airborne and drive toward the wall for exactly two seconds of
	// authoritative 64 Hz ticks. The player must land on the floor and stop at
	// the wall boundary rather than tunnelling through it.
	player.position = {-8, 8, 0}
	player.last_position = player.position
	player.velocity = {0, 0, 0}
	player.on_ground = false
	for tick in 0 ..< 128 {
		input := shared.Input{delta = PHYSICS_DT, move_dir = 3}
		shared.player_queue_input(player, &input)
		shared.game_tick(&game, f32(tick + 1) * PHYSICS_DT, PHYSICS_DT)
	}

	floor_y := floor.position.y + floor.scale.y
	wall_x := wall.position.x - wall.scale.x * 0.5 - player.scale
	landed := math.abs(player.position.y - floor_y) < 0.1 && math.abs(player.velocity.y) < 0.02
	blocked := player.position.x <= wall_x + 0.5 && math.abs(player.velocity.x) < 0.02
	if !landed || !blocked {
		fmt.printf("Server physics collision test failed: pos=%v vel=%v grounded=%v\n", player.position, player.velocity, player.on_ground)
		return false
	}

	fmt.println("Server authoritative physics tests OK")
	return true
}

test_client_physics :: proc() -> bool {
	server_map := shared.Map{death_y = -100, config = shared.Map_Config{speed = {1, 1, 1}, air_accel = 1, ladder_accel = 1, slide_time = 1, slide_accel = 1}}
	client_map := shared.Map{death_y = -100, config = shared.Map_Config{speed = {1, 1, 1}, air_accel = 1, ladder_accel = 1, slide_time = 1, slide_accel = 1}}
	server_floor := shared.Object{
		active = true,
		collision_type = .BOX,
		position = {0, 0, 0},
		scale = {100, 1, 100},
	}
	client_floor := server_floor
	append(&server_map.objects, &server_floor)
	append(&client_map.objects, &client_floor)

	server_game := shared.Game{}
	client_game := shared.Game{}
	server_player := physics_game_init(&server_game, &server_map, true)
	client_player := physics_game_init(&client_game, &client_map, true)
	defer shared.game_destroy(&server_game)
	defer shared.game_destroy(&client_game)

	server_player.position = {-6, 1, 0}
	client_player.position = server_player.position
	server_player.last_position = server_player.position
	client_player.last_position = client_player.position

	// The client prediction path and the authoritative queue/update path must
	// produce the same state for the same fixed-tick input stream.
	for tick in 0 ..< 96 {
		input := shared.Input{
			delta = PHYSICS_DT,
			move_dir = 3,
			jump = tick == 8,
		}
		shared.player_queue_input(server_player, &input)
		shared.game_tick(&server_game, f32(tick + 1) * PHYSICS_DT, PHYSICS_DT)
		shared.player_proc_input(client_player, &input, true, false)
	}

	position_error := math.sqrt(
		(server_player.position.x - client_player.position.x) * (server_player.position.x - client_player.position.x) +
		(server_player.position.y - client_player.position.y) * (server_player.position.y - client_player.position.y) +
		(server_player.position.z - client_player.position.z) * (server_player.position.z - client_player.position.z),
	)
	velocity_error := math.sqrt(
		(server_player.velocity.x - client_player.velocity.x) * (server_player.velocity.x - client_player.velocity.x) +
		(server_player.velocity.y - client_player.velocity.y) * (server_player.velocity.y - client_player.velocity.y) +
		(server_player.velocity.z - client_player.velocity.z) * (server_player.velocity.z - client_player.velocity.z),
	)
	if position_error > 0.001 || velocity_error > 0.001 || server_player.on_ground != client_player.on_ground {
		fmt.printf("Client prediction parity test failed: position_error=%f velocity_error=%f\n", position_error, velocity_error)
		return false
	}

	// Remote interpolation must clamp at the target and take the shortest yaw
	// path across the -PI/PI boundary.
	client_player.interpolate = true
	client_player.send_rate = 32
	client_player.interp_pos_start = {0, 1, 0}
	client_player.interp_pos_end = {10, 1, 0}
	client_player.interp_dir_start = {0, math.PI - 0.1}
	client_player.interp_dir_end = {0, -math.PI + 0.1}
	shared.player_interpolate(client_player, 0.2)
	interpolation_ok :=
		client_player.position == client_player.interp_pos_end &&
		math.abs(shared.normalize_angle(client_player.direction.y - client_player.interp_dir_end.y)) < 0.001
	if !interpolation_ok {
		fmt.eprintln("Client interpolation edge-case test failed")
		return false
	}

	fmt.println("Client prediction/interpolation physics tests OK")
	return true
}
