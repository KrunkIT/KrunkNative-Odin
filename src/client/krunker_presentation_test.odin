package main

import "core:math"
import "core:testing"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import shared "../shared"
import kproto "../krunker"

when ODIN_TEST {
	krunker_presentation_fixture :: proc(client: ^Client, map_inst: ^shared.Map) {
		map_inst^ = {death_y = -1000, config = {speed = {1, 1, 1}, air_accel = 1}}
		shared.game_configure(&client.game, nil, []^shared.Map{map_inst}, nil, nil, nil)
		shared.game_init(&client.game, 0, 0, false)
		client.me = shared.player_init(&client.game)
		shared.game_players_add(&client.game, client.me)
		shared.player_spawn(client.me, 2)
		client.me.uid, client.me.is_you, client.me.noclip = 7, true, true
		client.me.swap_timer = 0
		client.krunker_world.local_sid = 7
		client.krunker.spawned, client.krunker.bootstrapped = true, true
		client.krunker.input_sequence = 13
	}

	krunker_presentation_cleanup :: proc(client: ^Client) {
		shared.game_destroy(&client.game)
		delete(client.predicted_inputs)
		krunker_ws_disconnect(&client.krunker)
		kproto.krunker_world_reset(&client.krunker_world)
	}

	@(test)
	krunker_live_shots_ammo_reload_and_replay :: proc(t: ^testing.T) {
		client: Client
		map_inst: shared.Map
		krunker_presentation_fixture(&client, &map_inst)
		defer krunker_presentation_cleanup(&client)
		victim := shared.player_init(&client.game)
		shared.game_players_add(&client.game, victim)
		shared.player_spawn(victim, 2)
		victim.position, victim.scale, victim.height = {0, 0, -100}, 20, 100
		frame := shared.Input{delta = 0.007, move_dir = -1, shoot = true}
		krunker_client_predict_input(&client, &frame)
		testing.expect(t, client.me.ammo[0] == 23 && client.me.shot_seq == 1, "live firing must consume a round immediately")
		if !testing.expect(t, len(client.game.impacts) == 1 && client.game.impacts[0].kind == .Player, "local fire must generate a resolved tracer path") { return }
		testing.expect(t, victim.health == 100 && victim.active, "local shot presentation must never apply server-owned damage")
		source := kproto.Krunker_World_Player{position = client.me.position, weapon_slot = 0, has_ack = true, ack_seq = 12, sync_revision = 1}
		for _ in 0..<3 {
			krunker_client_apply_motion(&client, client.me, &source, false)
			source.sync_revision += 1
		}
		testing.expect(t, client.me.ammo[0] == 23 && client.me.shot_seq == 1 && len(client.game.impacts) == 1,
			"replaying an unacknowledged shoot command must not repeat effects or ammo consumption")
		// The ammo correction must be applied once, even if unrelated snapshots
		// subsequently update the same source player.
		ammo_packet := []kproto.Krunker_Msgpack_Value{"uamo", []kproto.Krunker_Msgpack_Value{i64(10), i64(0)}}
		testing.expect(t, kproto.krunker_world_apply_packet(&client.krunker_world, ammo_packet), "server ammo packet must be recognized")
		ammo_source := &client.krunker_world.players[0]
		krunker_client_apply_ammo(&client, client.me, ammo_source)
		testing.expect(t, client.me.ammo[0] == 10, "server ammo corrections must reach the active magazine")
		client.me.ammo[0] = 9
		krunker_client_apply_ammo(&client, client.me, ammo_source)
		testing.expect(t, client.me.ammo[0] == 9, "an old ammo correction must not undo newer predicted shots")
		frame.shoot, frame.reload = false, true
		krunker_client_predict_input(&client, &frame)
		remaining := client.me.reload_timer
		testing.expect(t, remaining > 0, "live reload input must start a reload")
		krunker_client_apply_motion(&client, client.me, &source, false)
		testing.expect(t, client.me.reload_timer == remaining, "movement ACKs must preserve an ongoing reload")
		frame.reload = false
		for _ in 0..<int(math.ceil(remaining/0.007))+1 { krunker_client_predict_input(&client, &frame) }
		testing.expect(t, client.me.reload_timer == 0 && client.me.ammo[0] == 24, "the magazine must refill when the predicted reload completes")
		shared.player_swap_weapon(client.me, 1, true, true, true)
		before := len(client.game.impacts)
		shared.player_melee(client.me, true)
		testing.expect(t, len(client.game.impacts) == before && victim.health == 100, "predicted knives must create no bullet effects or damage")
	}

	@(test)
	krunker_remote_poses_are_smooth_and_wrap_yaw :: proc(t: ^testing.T) {
		client: Client
		map_inst: shared.Map
		krunker_presentation_fixture(&client, &map_inst)
		defer krunker_presentation_cleanup(&client)
		peer := shared.player_init(&client.game)
		shared.game_players_add(&client.game, peer)
		shared.player_spawn(peer, 2)
		peer.uid, peer.swap_timer = 8, 0
		record := []kproto.Krunker_Msgpack_Value{i64(8), i64(0), i64(0), i64(0), i64(179), i64(0), i64(0), true, f64(0), i64(3), f64(1), kproto.Krunker_Msgpack_Nil{}, i64(20)}
		packet := []kproto.Krunker_Msgpack_Value{"k", record, i64(10), i64(1000)}
		client.krunker_world.received_at = 1
		kproto.krunker_world_apply_packet(&client.krunker_world, packet)
		source := &client.krunker_world.players[0]
		krunker_client_apply_motion(&client, peer, source, true)
		client.krunker_world.received_at = 1.1
		record[1], record[4], record[8], record[10] = i64(10), i64(-179), f64(1), f64(0)
		kproto.krunker_world_apply_packet(&client.krunker_world, packet)
		krunker_client_apply_motion(&client, peer, source, false)
		testing.expect(t, peer.position.x == 0, "a newly arrived k must not snap a visible remote player")
		krunker_client_interpolate_remotes(&client, 1.175, 0.005)
		testing.expect(t, abs(peer.position.x-5) < 0.001 && abs(peer.crouch_val-0.5) < 0.001 && abs(peer.aim_val-0.5) < 0.001,
			"remote position, crouch, and ADS must render between the buffered samples")
		testing.expect(t, abs(abs(peer.direction.y)-math.PI) < 0.001, "yaw interpolation must cross 180 degrees by the short path")
		previous := peer.position.x
		for frame in 1..=9 {
			krunker_client_interpolate_remotes(&client, 1.175+f64(frame)*0.005, 0.005)
			testing.expect(t, peer.position.x > previous && peer.position.x-previous < 0.501, "every display frame must advance smoothly between 10 Hz packets")
			previous = peer.position.x
		}
		krunker_client_interpolate_remotes(&client, 1.8, 0.005)
		testing.expect(t, peer.position.x == 10, "missing updates must hold the newest position instead of extrapolating indefinitely")
		client.krunker_world.received_at = 2
		record[1] = i64(1000)
		kproto.krunker_world_apply_packet(&client.krunker_world, packet)
		krunker_client_interpolate_remotes(&client, 2, 0.005)
		testing.expect(t, peer.position.x == 1000 && source.pose_count == 1, "teleports/reappearances must discard stale interpolation paths")
	}

	@(test)
	krunker_server_tracers_reach_effects_once :: proc(t: ^testing.T) {
		client: Client
		map_inst: shared.Map
		krunker_presentation_fixture(&client, &map_inst)
		defer krunker_presentation_cleanup(&client)
		peer := shared.player_init(&client.game)
		shared.game_players_add(&client.game, peer)
		shared.player_spawn(peer, 2)
		peer.uid = 8
		values := []kproto.Krunker_Msgpack_Value{i64(8), i64(0), i64(10), i64(-200), kproto.Krunker_Msgpack_Nil{}, kproto.Krunker_Msgpack_Nil{}, i64(0), i64(0), i64(0), i64(11), i64(0), i64(0), i64(0)}
		encoded, ok := kproto.krunker_msgpack_encode_packet("9", []kproto.Krunker_Msgpack_Value{values}, 37)
		if !testing.expect(t, ok) { return }
		defer delete(encoded)
		messages, _, err := kproto.krunker_msgpack_decode_packet(encoded)
		if !testing.expect(t, len(err) == 0 && len(messages) == 1) { return }
		testing.expect(t, kproto.krunker_world_apply_packet(&client.krunker_world, messages[0].([]kproto.Krunker_Msgpack_Value)), "wire SHOW_TRACER must enter the live world")
		values[0] = i64(7)
		kproto.krunker_world_apply_packet(&client.krunker_world, []kproto.Krunker_Msgpack_Value{i64(9), values})
		krunker_client_present_shots(&client)
		if !testing.expect(t, len(client.game.impacts) == 1 && len(client.krunker_world.shots) == 0, "remote shots must produce effects and local echoes must not duplicate them") { return }
		testing.expect(t, client.game.impacts[0].shooter_uid == 8 && client.game.impacts[0].weapon_id == 3 && client.game.impacts[0].position.z == -200,
			"remote effects must retain shooter, weapon, and authoritative endpoint")
		krunker_client_present_shots(&client)
		testing.expect(t, len(client.game.impacts) == 1, "a consumed network shot must not render again on the next frame")
	}

	@(test)
	krunker_live_local_and_remote_tracers_render :: proc(t: ^testing.T) {
		if !testing.expect(t, bool(glfw.Init())) { return }
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(640, 360, "Live bullet effects regression", nil, nil)
		if !testing.expect(t, window != nil) { return }
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		client: Client
		map_inst: shared.Map
		krunker_presentation_fixture(&client, &map_inst)
		client.scene = scene_init()
		g_client = &client
		defer {
			client_clear_impacts(&client)
			scene_fini(client.scene)
			resource_cache_fini()
			krunker_presentation_cleanup(&client)
			g_client = nil
		}
		client.camera = camera_init(math.PI/2)
		client.camera.position = {0, 20, 40}
		client.me.position = {40, 10, -80}
		frame := shared.Input{delta = 0.007, move_dir = -1, y_dir = math.PI/2, shoot = true}
		krunker_client_predict_input(&client, &frame)
		client_tick_impacts(&client, 0.02)
		testing.expect(t, len(client.tracer_markers) == 1, "a live local input must create a world tracer mesh")
		pixels := make([]u8, 640*360*3, context.temp_allocator)
		for pass in 0..<2 {
			gl.Viewport(0, 0, 640, 360)
			gl.ClearColor(0, 0, 0, 1)
			gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
			scene_render(client.scene, &client.camera, 640, 360)
			gl.ReadPixels(0, 0, 640, 360, gl.RGB, gl.UNSIGNED_BYTE, raw_data(pixels))
			visible := 0
			for i := 0; i < len(pixels); i += 3 {
				if pixels[i] > 0 || pixels[i+1] > 0 || pixels[i+2] > 0 { visible += 1 }
			}
			testing.expect(t, visible > 3, pass == 0 ? "locally fired tracers must produce visible pixels" : "server-received tracers must produce visible pixels")
			client_clear_impacts(&client)
			if pass == 1 { break }
			peer := shared.player_init(&client.game)
			shared.game_players_add(&client.game, peer)
			shared.player_spawn(peer, 2)
			peer.uid = 8
			values := []kproto.Krunker_Msgpack_Value{i64(8), i64(100), i64(20), i64(-80), kproto.Krunker_Msgpack_Nil{}, kproto.Krunker_Msgpack_Nil{}, i64(0), i64(-100), i64(10), i64(11), i64(-80), i64(0), i64(0)}
			kproto.krunker_world_apply_packet(&client.krunker_world, []kproto.Krunker_Msgpack_Value{"9", values})
			krunker_client_present_shots(&client)
			client_tick_impacts(&client, 0.02)
			testing.expect(t, len(client.tracer_markers) == 1, "a server tracer packet must create a world tracer mesh")
		}
		testing.expect(t, gl.GetError() == gl.NO_ERROR, "live tracer rendering must not produce OpenGL errors")
	}
}
