package main

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:os"
import "core:testing"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import shared "../shared"

when ODIN_TEST {
	@(test)
	trooper_blaster_render :: proc(t: ^testing.T) {
		context = runtime.default_context()
		if !testing.expect(t, bool(glfw.Init()), "GLFW initialization failed") do return
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(960, 540, "Trooper render regression", nil, nil)
		if !testing.expect(t, window != nil, "hidden OpenGL window failed") do return
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
		client := Client{window = window, scene = scene_init(), fps_scene = scene_init()}
		g_client = &client
		defer { g_client = nil }
		config := shared.config_load_gameplay()
		defer shared.config_destroy_gameplay(config)
		map_inst := shared.Map{death_y = -1000}
		maps := []^shared.Map{&map_inst}
		shared.game_configure(&client.game, &config.game, maps, nil, config.weapons, config.classes)
		shared.game_init(&client.game, 0, 0, true)
		defer {
			client_clear_players(&client)
			shared.game_destroy(&client.game)
			scene_fini(client.fps_scene)
			scene_fini(client.scene)
			resource_cache_fini()
		}
		player := shared.player_init(&client.game)
		shared.game_players_add(&client.game, player)
		shared.player_spawn(player, 13)
		player.is_you = true
		player.position = {}
		player.swap_timer = 0
		player_generate_meshes(player, true)
		mesh := cast(^Player_Mesh)player.mesh
		if !testing.expect(t, mesh != nil && len(mesh.arms) == 2 && mesh.arms[0].weapon_right != nil, "Trooper must load its Blaster mesh") do return
		gun := mesh.arms[0].weapon_right
		testing.expect(t, gun.geometry.index_count > 0 && (cast(^Basic_Material)gun.material).texture != 0, "Blaster geometry and texture must load")
		sight := mesh.arms[0].attachment
		if !testing.expect(t, sight != nil && sight.geometry.index_count > 0 && (cast(^Basic_Material)sight.material).texture != 0, "Blaster must load its reflex sight model and texture") do return
		testing.expect(t, sight.transform.parent == &mesh.arms[0].anchor && abs(sight.transform.position.y - 0.45) < 0.0001 && abs(sight.transform.position.z - 0.73) < 0.0001, "reflex sight must use the reference attachment mount")
		scene_add_player_mesh(client.fps_scene, mesh, int(player.loadout_size))
		client.camera = camera_init(110 * math.PI / 180)
		client.camera.position.y = player.height - shared.GAME_CONSTANTS.camera_height
		gl.Viewport(0, 0, 960, 540)
		pixels := make([]u8, 960 * 540 * 3)
		defer delete(pixels)
		aims := [?]f32{0, 1}
		for aim in aims {
			player.aim_val = aim
			client.camera.zoom = 1 + (player.weapon.zoom - 1) * aim
			weapon_camera := camera_for_viewmodel(&client.camera)
			testing.expect(t, abs(weapon_camera.fov * 180 / math.PI - 95) < 0.0001 && weapon_camera.zoom == client.camera.zoom && weapon_camera.position == client.camera.position && weapon_camera.rotation == client.camera.rotation, "weapon projection must use Krunker's independent 95-degree FOV and share pose/ADS zoom")
			testing.expect(t, abs(client.camera.fov * 180 / math.PI - 110) < 0.0001, "weapon FOV must not change world projection")
			player_update_meshes(player, false)
			if aim == 1 {
				testing.expect(t, abs(mesh.arms[0].anchor.position.y - (-0.722)) < 0.0001, "Blaster ADS must include both the reflex and weapon aim offsets")
				testing.expect(t, abs(mesh.arms[0].anchor.rotation.x - (-0.02056)) < 0.0001, "ADS rig must match reference rotation without inverted animation weight")
			}
			gl.ClearColor(0, 0, 0, 1)
			gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
			scene_render(client.fps_scene, &weapon_camera, 960, 540)
			gl.ReadPixels(0, 0, 960, 540, gl.RGB, gl.UNSIGNED_BYTE, raw_data(pixels))
			visible := 0
			for i := 0; i < len(pixels); i += 3 {
				if pixels[i] > 0 || pixels[i + 1] > 0 || pixels[i + 2] > 0 { visible += 1 }
			}
			testing.expect(t, visible > 1000 && visible < 960 * 540 / 2, "Blaster view model must be visible at a sensible size, including when aiming")
			when #config(BLASTER_PREVIEW, false) {
				file := make([dynamic]u8)
				defer delete(file)
				header := "P6\n960 540\n255\n"
				append(&file, ..transmute([]u8)header)
				for row := 539; row >= 0; row -= 1 { append(&file, ..pixels[row * 960 * 3:(row + 1) * 960 * 3]) }
				testing.expect(t, os.write_entire_file(fmt.tprintf("bin/blaster_%.0f.ppm", aim), file[:]) == nil, "could not export Blaster preview")
			}
		}
		shared.player_swap_weapon(player, 1, true, true, true)
		player_update_meshes(player, false)
		testing.expect(t, !sight.visible, "Blaster sight must hide when switching to the knife")
		shared.player_swap_weapon(player, 0, true, true, true)
		player_update_meshes(player, false)
		testing.expect(t, sight.visible, "Blaster sight must return with its gun")
		shared.projectile_spawn(player, {0, 0})
		shared.game_tick_projectiles(&client.game, 0.02)
		client_tick_projectiles(&client)
		if !testing.expect(t, len(client.projectile_meshes) == 1, "a fired bolt must create a scene mesh") do return
		bolt := client.projectile_meshes[0]
		mesh_update_transform_matrix(bolt)
		// The cube's long axis is +Y: its tip must coincide with the simulated bolt.
		tip := bolt.transform_matrix * shared.Vec4{0, 1, 0, 1}
		position := client.game.projectiles[0].position
		testing.expect(t, abs(tip.x - position.x) < 0.001 && abs(tip.y - position.y) < 0.001 && abs(tip.z - position.z) < 0.001, "bolt mesh must point along its travel direction")
		scene_render(client.scene, &client.camera, 960, 540)
		testing.expect(t, gl.GetError() == gl.NO_ERROR, "Blaster and bolt render produced an OpenGL error")
		shared.game_tick_projectiles(&client.game, 1)
		client_tick_projectiles(&client)
		testing.expect(t, len(client.projectile_meshes) == 0 && client.scene.mesh_count == 0, "expired bolts must release their meshes")
		client_clear_players(&client)
		testing.expect(t, client.fps_scene.mesh_count == 0, "removing Trooper must detach the sight and all weapon meshes")
	}
}
