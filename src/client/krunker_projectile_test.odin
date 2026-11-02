package main

import "core:math"
import "core:testing"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import shared "../shared"
import kproto "../krunker"

when ODIN_TEST {
	@(test)
	krunker_live_projectile_ids_and_authority :: proc(t: ^testing.T) {
		client: Client
		map_inst: shared.Map
		krunker_presentation_fixture(&client, &map_inst)
		defer krunker_presentation_cleanup(&client)
		world := &client.krunker_world
		packet := []kproto.Krunker_Msgpack_Value{"pr", i64(0), i64(10), i64(0), f64(0), f64(0), i64(18), i64(23), false, kproto.Krunker_Msgpack_Nil{}, i64(999)}
		testing.expect(t, kproto.krunker_world_apply_packet(world, packet))
		krunker_client_present_projectiles(&client)
		if !testing.expect(t, len(client.game.projectiles) == 1) { return }
		testing.expect(t, client.game.projectiles[0].network_id == 23 && client.game.projectiles[0].networked)
		shared.game_tick_projectiles(&client.game, 0.01)
		testing.expect(t, len(client.game.projectiles) == 1 && abs(client.game.projectiles[0].position.z+10) < 0.001,
			"a remote bolt must advance even before its shooter is in the local roster")
		testing.expect(t, client.me.health == 100 && client.game.match.team_scores == [3]u32{}, "server visuals cannot award damage or points")
		kproto.krunker_world_apply_packet(world, packet)
		krunker_client_present_projectiles(&client)
		testing.expect(t, len(client.game.projectiles) == 1, "duplicate server projectile IDs must not create extra bolts")
		client.me.weapon, client.me.loadout[0], client.me.loadout_index = client.game.weapons[18], 18, 0
		client.me.projectile_shot_seq = 23
		shared.projectile_spawn(client.me, {})
		testing.expect(t, len(client.game.projectiles) == 2)
		gameplay_packet(world, "pre", i64(23), true)
		krunker_client_present_projectiles(&client)
		testing.expect(t, len(client.game.projectiles) == 1 && client.game.projectiles[0].networked,
			"local shot-counter removals must not match an unrelated server SID")
		gameplay_packet(world, "pre", i64(23), false)
		krunker_client_present_projectiles(&client)
		testing.expect(t, len(client.game.projectiles) == 0 && len(world.projectile_events) == 0)
		packet[8] = true
		testing.expect(t, !kproto.krunker_world_apply_packet(world, packet), "scripted projectile IDs cannot be treated as weapon IDs")
		testing.expect(t, !gameplay_packet(world, "pr", i64(0)) && !gameplay_packet(world, "ex", i64(1), i64(2), i64(3), i64(-1)))
	}

	@(test)
	krunker_server_explosions_render_and_expire_without_damage :: proc(t: ^testing.T) {
		if !testing.expect(t, bool(glfw.Init())) { return }
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(320, 180, "Live explosion regression", nil, nil)
		if !testing.expect(t, window != nil) { return }
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
		client: Client
		map_inst: shared.Map
		krunker_presentation_fixture(&client, &map_inst)
		client.scene = scene_init()
		defer {
			client_clear_impacts(&client)
			scene_fini(client.scene)
			resource_cache_fini()
			krunker_presentation_cleanup(&client)
		}
		client.camera = camera_init(math.PI/2)
		client.camera.position = {0,0,20}
		gameplay_packet(&client.krunker_world, "ex", i64(0), i64(0), i64(0), i64(50), i64(0), i64(0))
		krunker_client_present_projectiles(&client)
		krunker_client_tick_explosions(&client, 0.1)
		gl.Viewport(0,0,320,180)
		gl.ClearColor(0,0,0,1)
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
		scene_render(client.scene, &client.camera, 320,180)
		pixels := make([]u8, 320*180*3, context.temp_allocator)
		gl.ReadPixels(0,0,320,180,gl.RGB,gl.UNSIGNED_BYTE,raw_data(pixels))
		visible := 0
		for i := 0; i < len(pixels); i += 3 { if pixels[i] > 0 { visible += 1 } }
		testing.expect(t, visible > 20 && len(client.explosions) == 1, "server explosions must produce a visible world effect")
		krunker_client_tick_explosions(&client, 0.4)
		testing.expect(t, len(client.explosions) == 0 && client.scene.mesh_count == 0 && client.me.health == 100,
			"explosions must release their meshes without applying local damage")
		testing.expect(t, gl.GetError() == gl.NO_ERROR)
	}
}
