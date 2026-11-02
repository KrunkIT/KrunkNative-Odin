package main

import "core:math"
import "core:testing"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import shared "../shared"
import kproto "../krunker"

when ODIN_TEST {
	@(test)
	krunker_health_updates_target_players :: proc(t: ^testing.T) {
		world := kproto.Krunker_World_State{local_sid = 7}
		defer kproto.krunker_world_reset(&world)
		append(&world.players,
			kproto.Krunker_World_Player{sid = 7, health = 100, max_health = 100, active = true, sync_revision = 4},
			kproto.Krunker_World_Player{sid = 8, health = 170, max_health = 170, active = true})
		testing.expect(t, kproto.krunker_world_apply_packet(&world, []kproto.Krunker_Msgpack_Value{"h", i64(85), i64(8)}))
		testing.expect(t, world.players[1].health == 85 && world.players[1].max_health == 170 && world.players[0].health == 100,
			"remote health changes must target the supplied SID and preserve class maximum health")
		kproto.krunker_world_apply_packet(&world, []kproto.Krunker_Msgpack_Value{"h", i64(45), kproto.Krunker_Msgpack_Nil{}})
		testing.expect(t, world.players[0].health == 45 && world.players[0].sync_revision == 4,
			"a nil SID targets local health without replaying an old movement correction")
		kproto.krunker_world_apply_packet(&world, []kproto.Krunker_Msgpack_Value{"h", i64(80), i64(8), i64(0), i64(0), true, true})
		testing.expect(t, world.players[1].health == 80 && world.players[1].max_health == 80, "server maximum-health resets must update the bar denominator")
		kproto.krunker_world_apply_packet(&world, []kproto.Krunker_Msgpack_Value{"h", i64(120), i64(8)})
		testing.expect(t, world.players[1].max_health == 120, "server overheal must raise maximum health")
		testing.expect(t, !kproto.krunker_world_apply_packet(&world, []kproto.Krunker_Msgpack_Value{"h", i64(-5), i64(8)}) && world.players[1].health == 120,
			"invalid health must not overwrite a valid player state")
		kproto.krunker_world_apply_packet(&world, []kproto.Krunker_Msgpack_Value{i64(3), i64(8)})
		testing.expect(t, !world.players[1].active && world.players[1].health == 0, "death messages must remove a remote health bar")
		kproto.krunker_world_apply_packet(&world, []kproto.Krunker_Msgpack_Value{"2", i64(7)})
		testing.expect(t, !world.players[0].active, "disconnected players must not leave stale bars")
		roster: [53]kproto.Krunker_Msgpack_Value
		roster[1], roster[6], roster[8] = i64(8), i64(3), i64(170)
		kproto.krunker_world_apply_packet(&world, []kproto.Krunker_Msgpack_Value{i64(0), roster[:]})
		testing.expect(t, world.players[1].active && world.players[1].health == 170 && world.players[1].max_health == 170,
			"a nil roster health on respawn must mean full class health instead of preserving the previous dead state")
	}

	healthbar_test_colors :: proc(client: ^Client, pixels: []u8) -> (red, green: int) {
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
		scene_render(client.scene, &client.camera, f32(client.viewport_width), f32(client.viewport_height))
		player_healthbars_render(client)
		gl.ReadPixels(0, 0, client.viewport_width, client.viewport_height, gl.RGB, gl.UNSIGNED_BYTE, raw_data(pixels))
		for i := 0; i < len(pixels); i += 3 {
			if pixels[i] > 200 && pixels[i+1] < 120 && pixels[i+2] < 120 { red += 1 }
			if pixels[i] < 190 && pixels[i+1] > 200 && pixels[i+2] < 140 { green += 1 }
		}
		return
	}

	@(test)
	healthbars_render_above_players_and_respect_world_depth :: proc(t: ^testing.T) {
		if !testing.expect(t, bool(glfw.Init())) { return }
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(640, 360, "Overhead health bar regression", nil, nil)
		if !testing.expect(t, window != nil) { return }
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
		gl.Viewport(0, 0, 640, 360)
		gl.ClearColor(0, 0, 0, 1)
		local := shared.Player{active = true, is_you = true, team = 1, position = {0, 0, -80}, height = 11, health = 100, max_health = 100}
		enemy := shared.Player{active = true, team = 2, position = {-20, 0, -80}, height = 11, health = 100, max_health = 100}
		ally := shared.Player{active = true, team = 1, position = {20, 0, -80}, height = 11, health = 100, max_health = 100}
		client := Client{in_game = true, viewport_width = 640, viewport_height = 360, me = &local}
		client.mouse_state.locked = true
		client.camera = camera_init(math.PI/2)
		client.camera.position = {0, 12.8, 0}
		client.scene, client.ui = scene_init(), ui_init()
		append(&client.game.players, &local, &enemy, &ally)
		defer {
			delete(client.game.players)
			ui_fini(client.ui)
			scene_fini(client.scene)
			resource_cache_fini()
		}
		pixels := make([]u8, 640*360*3, context.temp_allocator)
		red, green := healthbar_test_colors(&client, pixels)
		testing.expect(t, red > 20 && green > 20 && abs(red-green) < 5, "both enemies and teammates must have visible, equally sized bars in their team colors")
		enemy.health = 50
		half_red, same_green := healthbar_test_colors(&client, pixels)
		testing.expect(t, half_red > red/3 && half_red < red*2/3 && same_green == green, "taking damage must shrink only the affected player's fill")
		depth: f32
		gl.GetUniformfv(quad_shader_program, u_quad.depth, &depth)
		testing.expect(t, depth == 0, "world depth must not leak into later HUD draws")
		material := basic_material_init()
		material.unlit, material.no_fog, material.color = true, true, {0.1, 0.1, 0.1, 1}
		wall := mesh_init(create_cube_geo(), &material.base)
		wall.transform.position, wall.transform.scale = {0, -100, -40}, {200, 200, 1}
		scene_add_mesh(client.scene, wall)
		defer mesh_fini(wall)
		occluded_red, occluded_green := healthbar_test_colors(&client, pixels)
		testing.expect(t, occluded_red == 0 && occluded_green == 0, "map walls must occlude overhead bars using the world depth buffer")
		scene_remove_mesh(client.scene, wall)
		client.mouse_state.locked = false
		menu_red, menu_green := healthbar_test_colors(&client, pixels)
		testing.expect(t, menu_red == 0 && menu_green == 0, "bars must disappear while the menu is open")
		client.mouse_state.locked = true
		client.in_game = false
		lobby_red, lobby_green := healthbar_test_colors(&client, pixels)
		testing.expect(t, lobby_red == 0 && lobby_green == 0, "bars must only render during gameplay")
		client.in_game = true
		enemy.position.z, ally.position.z = 80, 80
		behind_red, behind_green := healthbar_test_colors(&client, pixels)
		testing.expect(t, behind_red == 0 && behind_green == 0, "players behind the camera must not produce mirrored bars")
		enemy.position.z, ally.position.z = -80, -80
		enemy.active, ally.health = false, 0
		dead_red, dead_green := healthbar_test_colors(&client, pixels)
		testing.expect(t, dead_red == 0 && dead_green == 0, "inactive/dead players and the local player must not get overhead bars")
		testing.expect(t, gl.GetError() == gl.NO_ERROR, "health bar and world rendering must preserve valid OpenGL state")
	}
}
