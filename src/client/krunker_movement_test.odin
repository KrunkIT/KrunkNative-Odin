package main

import "core:testing"
import shared "../shared"
import kproto "../krunker"

when ODIN_TEST {
	@(test)
	krunker_lobby_movement_settings :: proc(t: ^testing.T) {
		world := kproto.Krunker_World_State{local_sid = 7}
		defer kproto.krunker_world_reset(&world)
		config := []kproto.Krunker_Msgpack_Map_Entry{
			{"fixMov", true}, {"strafeSpd", f64(1.3)}, {"jumpMlt", f64(1.005)},
			{"slidSpd", f64(0.97)}, {"slidTime", f64(1.5)}, {"deltaMlt", f64(0.8)},
			{"gravMlt", f64(0.9)}, {"wallJP", f64(2)}, {"canSlide", false}, {"autoJump", true},
		}
		init := []kproto.Krunker_Msgpack_Value{"init", i64(2), i64(2), i64(0), i64(0), i64(0), kproto.Krunker_Msgpack_Nil{}, config}
		if !testing.expect(t, kproto.krunker_world_apply_init(&world, init)) { return }
		cfg := world.game_config
		testing.expect(t, world.has_game_config && cfg.fixed_movement && cfg.strafe_speed == 1.3 && cfg.jump_mlt == 1.005 &&
			cfg.slide_speed == 0.97 && cfg.slide_time == 1.5 && cfg.delta_mlt == 0.8 && cfg.gravity_mlt == 0.9 &&
			cfg.wall_jump == 2 && !cfg.can_slide && cfg.auto_jump,
			"movement must use the actual INIT_GAME config, including comp settings and custom overrides")
		// A subsequent lobby may omit values or send no config at all. Do not
		// carry comp velocity integration or modified multipliers into it.
		kproto.krunker_world_apply_init(&world, init[:3])
		testing.expect(t, !world.game_config.fixed_movement && world.game_config.strafe_speed == 1.2 &&
			world.game_config.slide_speed == 1 && world.game_config.jump_mlt == 1 && world.game_config.can_slide,
			"missing lobby settings must use browser defaults, without leaking the previous lobby's options")
	}

	@(test)
	krunker_motion_matches_browser_reference :: proc(t: ^testing.T) {
		// Expected values were evaluated with the actual Default.mov/vel JS
		// functions in game.deob.js:15922-15948, using a Run N Gun SMG and
		// 143 commands of 7 ms. This compares against the browser independently
		// of our encoder or a peer running the same native physics implementation.
		cases := []struct {fixed: bool, direction: i32, position, velocity: shared.Vec2}{
			{false, 0, {-31.437692336, -36.354301297}, {-0.032377790, -0.037441423}},
			{false, 1, {4.171881044, -57.523414090}, {0.004296635, -0.059243567}},
			{true, 0, {-30.357318012, -35.104964887}, {-0.032377790, -0.037441423}},
			{true, 1, {4.028511960, -55.546588980}, {0.004296635, -0.059243567}},
		}
		for c in cases {
			floor := shared.Object{active = true, collision_type = .BOX, position = {0, 0, 0}, scale = {10000, 1, 10000}}
			map_inst := shared.Map{death_y = -1000, config = {speed = {1, 1, 1}, air_accel = 1}}
			append(&map_inst.objects, &floor)
			defer delete(map_inst.objects)
			game: shared.Game
			shared.game_configure(&game, nil, []^shared.Map{&map_inst}, nil, nil, nil)
			shared.game_init(&game, 0, 0, false)
			defer shared.game_destroy(&game)
			game.config.fixed_movement = c.fixed
			player := shared.player_init(&game)
			shared.game_players_add(&game, player)
			shared.player_spawn(player, 2)
			player.position = {0, 1, 0}
			input := shared.Input{delta = 0.007, move_dir = c.direction, y_dir = 0.713}
			for _ in 0..<143 { shared.player_proc_input(player, &input, true, false) }
			testing.expect(t, abs(player.position.x-c.position.x) < 0.001 && abs(player.position.z-c.position.y) < 0.001 &&
				abs(player.velocity.x-c.velocity.x) < 0.00001 && abs(player.velocity.z-c.velocity.y) < 0.00001,
				"forward and diagonal travel must match browser physics in both normal and fixMov lobbies")
			// realMov disables the diagonal multiplier.
			if c.direction == 1 {
				player.position, player.velocity = {0, 1, 0}, {}
				game.mode.config.real_movement = true
				for _ in 0..<143 { shared.player_proc_input(player, &input, true, false) }
				testing.expect(t, abs(player.position.x-c.position.x/1.2) < 0.001 && abs(player.position.z-c.position.y/1.2) < 0.001,
					"realMov must disable the browser's diagonal acceleration bonus")
			}
		}
	}

	@(test)
	krunker_fixed_movement_flight_matches_browser :: proc(t: ^testing.T) {
		for fixed in ([]bool{false, true}) {
			map_inst := shared.Map{death_y = -1000, config = {speed = {1, 1, 1}, air_accel = 1}}
			game: shared.Game
			shared.game_configure(&game, nil, []^shared.Map{&map_inst}, nil, nil, nil)
			shared.game_init(&game, 0, 0, false)
			defer shared.game_destroy(&game)
			game.config.fixed_movement = fixed
			player := shared.player_init(&game)
			shared.game_players_add(&game, player)
			shared.player_spawn(player, 2)
			player.position, player.velocity, player.on_ground = {0, 1000, 0}, {0.1, -0.04, -0.1}, false
			input := shared.Input{delta = 0.007, move_dir = -1}
			for _ in 0..<100 { shared.player_proc_input(player, &input, true, false) }
			// These falling positions/velocities also come from Default.vel in
			// the browser. fixMov uses drag vertically as well as horizontally.
			expected_y: f32 = fixed ? 946.161251699 : 934.8825
			expected_vy: f32 = fixed ? -0.107299680 : -0.145
			expected_x: f32 = fixed ? 61.052434390 : 61.137964801
			testing.expect(t, abs(player.position.y-expected_y) < 0.003 && abs(player.velocity.y-expected_vy) < 0.00001 &&
				abs(player.position.x-expected_x) < 0.001 && abs(player.position.z+expected_x) < 0.001,
				"flight must use the lobby's velocity integration instead of accumulating vertical correction errors")
		}
	}

	@(test)
	krunker_sync_selects_weapon_by_loadout_slot :: proc(t: ^testing.T) {
		map_inst := shared.Map{death_y = -1000, config = {speed = {1, 1, 1}, air_accel = 1}}
		client: Client
		shared.game_configure(&client.game, nil, []^shared.Map{&map_inst}, nil, nil, nil)
		shared.game_init(&client.game, 0, 0, false)
		defer shared.game_destroy(&client.game)
		defer krunker_ws_disconnect(&client.krunker)
		defer delete(client.predicted_inputs)
		client.me = shared.player_init(&client.game)
		shared.game_players_add(&client.game, client.me)
		shared.player_spawn(client.me, 2)
		client.me.is_you = true
		world := kproto.Krunker_World_State{local_sid = 7}
		defer kproto.krunker_world_reset(&world)
		values: [18]kproto.Krunker_Msgpack_Value
		values[0], values[15], values[17] = i64(100), i64(1), i64(1)
		if !testing.expect(t, kproto.krunker_world_apply_sync_player(&world, []kproto.Krunker_Msgpack_Value{"l", values[:]})) { return }
		krunker_client_apply_motion(&client, client.me, &world.players[0], false)
		testing.expect(t, client.me.loadout_index == 1 && client.me.weapon.melee,
			"wire slot 1 must select the SMG class's knife, rather than searching for weapon ID 1")
		values[0], values[17] = i64(101), i64(0)
		kproto.krunker_world_apply_sync_player(&world, []kproto.Krunker_Msgpack_Value{"l", values[:]})
		krunker_client_apply_motion(&client, client.me, &world.players[0], false)
		testing.expect(t, client.me.loadout_index == 0 && client.me.weapon == client.game.weapons[3],
			"wire slot 0 must restore the primary weapon and its movement multiplier")
	}

	@(test)
	krunker_sync_restores_collision_carry_and_slide_cooldown :: proc(t: ^testing.T) {
		world := kproto.Krunker_World_State{local_sid = 7}
		defer kproto.krunker_world_reset(&world)
		values: [25]kproto.Krunker_Msgpack_Value
		values[0], values[3], values[15], values[17] = i64(100), f64(100), i64(1), i64(0)
		values[21], values[22], values[24] = f64(0.25), f64(-0.5), i64(70)
		if !testing.expect(t, kproto.krunker_world_apply_sync_player(&world, []kproto.Krunker_Msgpack_Value{"l", values[:]})) { return }
		player := shared.Player{is_you = true, x_vel_cylinder = 50, z_vel_cylinder = 50}
		client := Client{me = &player}
		defer delete(client.predicted_inputs)
		defer krunker_ws_disconnect(&client.krunker)
		// Empty loadout and no unacknowledged inputs make this a pure restore;
		// shared physics is not invoked and cannot conceal stale carry state.
		krunker_client_apply_motion(&client, &player, &world.players[0], true)
		testing.expect(t, player.x_vel_cylinder == 0.25 && player.z_vel_cylinder == -0.5 && abs(player.can_slide_timer-0.07) < 1e-6,
			"authoritative sync must restore cylinder carry and slide cooldown before replay")
		player.on_ground, player.crouch_val, player.can_slide = true, 1, true
		// No landing may start another slide before the server's cooldown ends.
		game := shared.Game{config = shared.DEFAULT_GAME_CONFIG}
		mode := shared.Game_Mode{}
		game.mode = &mode
		player.game = &game
		shared.player_reset_step(&player, true)
		testing.expect(t, player.can_slide && player.slide_timer == 0, "restored cooldown must prevent an early slide impulse")
	}
}
