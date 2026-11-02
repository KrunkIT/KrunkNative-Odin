package main

import "core:math"
import "core:testing"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import shared "../shared"
import kproto "../krunker"

when ODIN_TEST {
	@(test)
	prefab_texture_registry :: proc(t: ^testing.T) {
		testing.expect(t, len(prefab_textures) > 5, "prefab texture registry is missing the default slot")
		testing.expect(t, prefab_textures[5] == "default", "map texture index 5 must remain the untextured default material")
		testing.expect(t, len(prefab_textures) >= 20, "live map texture registry must expose all 20 slots")
		testing.expect(t, prefab_textures[17] == "metal", "map texture index 17 must resolve to metal")
		testing.expect(t, prefab_textures[18] == "sand", "map texture index 18 must resolve to sand")
		 testing.expect(t, prefab_textures[19] == "snow", "map texture index 19 must resolve to snow")
		testing.expect(t, len(prefab_models) >= 99, "live prefab model table must cover current map IDs")
		testing.expect(t, prefab_models[55].filename == "ghost_0", "AI spawner prefab 55 must render its ghost model")
		testing.expect(t, prefab_models[84].filename == "water_tower_0", "water tower prefab 84 must resolve its model")
	}

	@(test)
	prefab_model_variant_registry :: proc(t: ^testing.T) {
		// Texture-only variants keep the base OBJ; `diffM` variants select the
		// matching geometry file as the browser does.
		testing.expect(t, model_geometry_variant(int(shared.Prefab.CRATE), 1) == 0, "crate texture-only variant must keep base geometry")
		testing.expect(t, model_geometry_variant(int(shared.Prefab.CRATE), 2) == 2, "crate diffM variant must select crate_0_2.obj")
		testing.expect(t, model_geometry_variant(int(shared.Prefab.TREE), 8) == 8, "tree HD variant must select tree_0_8.obj")
		testing.expect(t, model_geometry_variant(int(shared.Prefab.VEHICLE), 1) == 0, "vehicle classic texture must keep base geometry")
	}

	@(test)
	sandstorm_v3_texture_metadata :: proc(t: ^testing.T) {
		path := shared.concat(shared.assets_path(), "maps/sandstorm_v3.json")
		map_inst, ok := shared.map_load_from_file(path)
		delete(path)
		if !testing.expect(t, ok && map_inst != nil, "Sandstorm v3 map must load for texture parity checks") do return
		defer shared.map_destroy(map_inst)

		found_dirt_variant := false
		found_lines_variant_2 := false
		found_face_mask := false
		for object in map_inst.objects {
			if object.texture == 1 && object.texture_variant == 1 { found_dirt_variant = true }
			if object.texture == 10 && object.texture_variant == 2 { found_lines_variant_2 = true }
			if object.face_mask != 0x3f { found_face_mask = true }
		}
		testing.expect(t, found_dirt_variant, "Sandstorm v3 dirt tv=1 variant was not parsed")
		testing.expect(t, found_lines_variant_2, "Sandstorm v3 lines tv=2 variant was not parsed")
		testing.expect(t, found_face_mask, "Sandstorm v3 face visibility masks were not parsed")
	}

	// Exercise the actual map/mesh/camera handoff in a hidden GL window. This
	// uses synthetic server state and never connects to a live account/lobby.
	@(test)
	krunker_join_render_handoff :: proc(t: ^testing.T) {
		if !testing.expect(t, bool(glfw.Init()), "GLFW initialization failed") do return
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(320, 240, "Krunker render regression", nil, nil)
		if !testing.expect(t, window != nil, "hidden OpenGL window failed") do return
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		client := Client{window = window}
		g_client = &client
		defer { g_client = nil }
		client.scene = scene_init()
		client.fps_scene = scene_init()
		client.camera.zoom = 1
		client.camera.fov = math.PI/2
		client.camera.near = 0.1
		client.camera.far = 10000
		config := shared.config_load_gameplay("assets/config/game.toml")
		defer shared.config_destroy_gameplay(config)
		shared.game_configure(&client.game, &config.game, nil, nil, config.weapons, config.classes)
		shared.load_default_maps()
		kproto.krunker_world_reset(&client.krunker_world)
		defer {
			client_unload_map(&client)
			client_clear_players(&client)
			shared.game_destroy(&client.game)
			shared.unload_default_maps()
			kproto.krunker_world_reset(&client.krunker_world)
			krunker_ws_disconnect(&client.krunker)
			delete(client.join_status)
			delete(client.predicted_inputs)
			scene_fini(client.fps_scene)
			scene_fini(client.scene)
			resource_cache_fini()
		}
		client.krunker.connected = true
		client.krunker_world.ready = true
		client.krunker_world.map_index = 2
		client.krunker_world.mode_index = 4
		client.krunker_world.map_revision = 1
		client.krunker_world.has_game_config = true
		client.krunker_world.game_config = shared.DEFAULT_GAME_CONFIG
		client.krunker_world.game_config.fixed_movement = true
		client.krunker_world.local_sid = 7
		append(&client.krunker_world.players, kproto.Krunker_World_Player{
			sid = 7, class_index = 2, team = 2, position = {120, 30, -80},
			weapon_slot = 0,
			active = true, has_position = true, health = 100, max_health = 100, revision = 1,
		})
		krunker_client_sync_world(&client)
		testing.expect(t, client.map_loaded && client.game.map_inst == shared.g_maps[2], "server map must load through the Sandstorm v3 alias")
		testing.expect(t, !client.game.is_local, "live session must not run offline simulation")
		testing.expect(t, client.game.config.fixed_movement, "server movement settings must reach the actual prediction game")
		testing.expect(t, client.me == nil && !client.krunker.spawned, "player position alone must not manufacture a server start")
		client.krunker_world.in_game = true
		krunker_client_sync_world(&client)
		if !testing.expect(t, client.me != nil, "server start must attach the local player") do return
		testing.expect(t, client.krunker.spawned && client.in_game && !client.spawn_pending, "spawn flags must follow the rendered player")
		testing.expect(t, client.me.class_index == 2 && client.me.team == 2, "SMG/team selection must survive renderer projection")
		testing.expect(t, client.me.position == (shared.Vec3{120, 30, -80}), "camera target must use the server position")
		testing.expect(t, client.me.mesh != nil && client.fps_scene.mesh_count > 0, "SMG view model must be attached")
		testing.expect(t, client.mouse_state.locked, "confirmed spawn must leave the menu")
		testing.expect(t, client.me.swap_timer == 0 && client.me.ammo[0] == 24, "live spawn must raise the weapon and use the current SMG magazine")
		local_mesh := cast(^Player_Mesh)client.me.mesh
		testing.expect(t, abs(local_mesh.upper_body_anchor.rotation.x - client.me.weapon.y_rotation) < 1e-5,
			"local upper body must not remain bent by the offline spawn animation")

		append(&client.krunker_world.players, kproto.Krunker_World_Player{
			sid = 8, class_index = 3, team = 1, position = {100, 30, -80}, direction = {math.PI/6, math.PI/2},
			weapon_slot = 0, active = true, has_position = true, health = 170, max_health = 170, revision = 1,
		})
		krunker_client_sync_world(&client)
		peer := client_find_player(&client, 8)
		if !testing.expect(t, peer != nil && peer.mesh != nil, "remote player must generate a third person mesh") do return
		peer_mesh := cast(^Player_Mesh)peer.mesh
		testing.expect(t, !peer.render_you && peer.swap_timer == 0 && peer.ammo[0] == 50, "remote spawn must raise the current LMG model")
		testing.expect(t, abs(peer_mesh.upper_body_anchor.rotation.x - (math.PI/12 + peer.weapon.y_rotation)) < 1e-5,
			"remote upper body must follow pitch without a frozen swap bend")

		// Simulate a 200 Hz display with slower, delayed local corrections. ADS
		// must remain monotonic while pressing and releasing the aim button.
		client.me.noclip = true
		local_source := &client.krunker_world.players[0]
		for scope in ([]bool{true, false}) {
			for frame in 0..<40 {
				before := client.me.aim_val
				input := shared.Input{seq = i32(frame/7 + 13), delta = 0.005, move_dir = -1, scope = scope, x_dir = 0.2, y_dir = 0.4}
				append(&client.predicted_inputs, input)
				shared.player_proc_input(client.me, &input, true, false, true)
				if frame % 4 == 0 {
					local_source.aim_val = scope ? 0 : 1
					local_source.has_ack = true
					local_source.ack_seq = i32(frame/7 + 11)
					local_source.sync_revision += 1
					local_source.revision += 1
					krunker_client_sync_world(&client)
				}
				testing.expect(t, scope ? client.me.aim_val >= before : client.me.aim_val <= before,
					"delayed snapshots must not reverse the local ADS transition")
				testing.expect(t, client.me.direction == (shared.Vec2{0.2, 0.4}), "replay must preserve the current camera direction")
			}
			testing.expect(t, client.me.aim_val == (scope ? 1 : 0), "holding/releasing ADS must reach its endpoint")
			clear(&client.predicted_inputs)
		}
		// A roster revision without a fresh local snapshot must leave predicted
		// position and weapon switches alone, even when the old snapshot has ACKs.
		client.me.position.x += 10
		shared.player_swap_weapon(client.me, 1, true, true, true)
		predicted_position := client.me.position
		local_source.revision += 1
		krunker_client_sync_world(&client)
		testing.expect(t, client.me.position == predicted_position && client.me.weapon.melee,
			"unrelated player metadata must not replay a stale local correction")
		local_source.class_index, local_source.weapon_slot = 3, 0
		local_source.revision += 1
		krunker_client_sync_world(&client)
		testing.expect(t, client.me.swap_timer == 0 && client.me.ammo[0] == 50, "class changes must raise the new weapon with its current magazine")
		// Live health changes must reach existing meshes without re-spawning or
		// disturbing interpolation. Death and same-class respawn must also stop
		// and restore the remote bar/model together.
		kproto.krunker_world_apply_packet(&client.krunker_world, []kproto.Krunker_Msgpack_Value{"h", i64(85), i64(8)})
		krunker_client_sync_world(&client)
		testing.expect(t, peer.health == 85 && peer.max_health == 170 && peer.active, "server health must update an existing remote player")
		before_death := client.scene.mesh_count
		kproto.krunker_world_apply_packet(&client.krunker_world, []kproto.Krunker_Msgpack_Value{"3", i64(8)})
		krunker_client_sync_world(&client)
		testing.expect(t, !peer.active && peer.health == 0 && client.scene.mesh_count < before_death, "a death must hide the remote model and health bar")
		roster: [53]kproto.Krunker_Msgpack_Value
		roster[1], roster[6], roster[7], roster[8], roster[9] = i64(8), i64(3), i64(170), i64(170), i64(1)
		roster[2], roster[3], roster[4] = i64(100), i64(30), i64(-80)
		kproto.krunker_world_apply_packet(&client.krunker_world, []kproto.Krunker_Msgpack_Value{i64(0), roster[:]})
		krunker_client_sync_world(&client)
		testing.expect(t, peer.active && peer.health == 170 && peer.mesh != nil && client.scene.mesh_count == before_death, "same-class respawn must restore a full-health remote model without duplicate meshes")
		// Render the map and player view model once to catch GL/resource issues.
		client.camera.position = client.me.position
		client.camera.position.y += client.me.height - shared.GAME_CONSTANTS.camera_height
		scene_render(client.scene, &client.camera, 320, 240)
		scene_render(client.fps_scene, &client.camera, 320, 240)
		testing.expect(t, gl.GetError() == gl.NO_ERROR, "spawned map/view-model render produced an OpenGL error")
	}
}
