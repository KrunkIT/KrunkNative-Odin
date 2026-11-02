package main

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:testing"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import shared "../shared"

when ODIN_TEST {
	@(test)
	all_weapon_models_render :: proc(t: ^testing.T) {
		context = runtime.default_context()
		if !testing.expect(t, bool(glfw.Init()), "GLFW initialization failed") do return
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(640, 360, "Weapon models", nil, nil)
		if !testing.expect(t, window != nil, "hidden OpenGL window failed") do return
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
		gl.Viewport(0, 0, 640, 360)
		client := Client{scene = scene_init(), fps_scene = scene_init()}
		g_client = &client
		defer { g_client = nil }
		config := shared.config_load_gameplay()
		defer shared.config_destroy_gameplay(config)
		for class in config.classes {
			for id in class.loadout {
				testing.expect(t, id >= 0 && int(id) < len(config.weapons) && config.weapons[id] != nil,
					fmt.tprintf("%s must have its configured primary instead of falling back to a knife", class.name))
			}
		}
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
		manifest, manifest_ok := shared.read_file("assets/config/weapon-assets.txt")
		if !testing.expect(t, manifest_ok, "weapon packaging manifest must exist") do return
		defer delete(manifest)
		pixels := make([]u8, 640 * 360 * 3)
		defer delete(pixels)
		supported := 0
		for weapon, id in config.weapons {
			if weapon == nil { continue }
			supported += 1
			primary := [?]i32{i32(id)}
			config.classes[0].loadout = primary[:]
			config.classes[0].secondary = false
			views := [?]bool{true, false}
			for first_person in views {
				player := shared.player_init(&client.game)
				shared.game_players_add(&client.game, player)
				shared.player_spawn(player, 0)
				player.is_you = first_person
				player.position = {}
				player.swap_timer = 0
				player_generate_meshes(player, first_person)
				rig := cast(^Player_Mesh)player.mesh
				if !testing.expect(t, rig != nil && len(rig.arms) > 0 && rig.arms[0].weapon_right != nil, fmt.tprintf("weapon %d %s must load a model", id, weapon.name)) do return
				arms := rig.arms[0]
				gun := arms.weapon_right
				model := "models/melee/melee_0.obj" if weapon.melee else fmt.tprintf("models/weapons/%s.obj", weapon.src)
				texture := "textures/melee/melee_0.png" if weapon.melee else fmt.tprintf("textures/weapons/%s.png", weapon.src)
				icon := fmt.tprintf("textures/%s/%s.png", "melee" if weapon.melee else "weapons", weapon.icon)
				testing.expect(t, strings.has_suffix(gun.geometry.cache_key, model) && gun.geometry.index_count > 0, fmt.tprintf("weapon %d must use its current base geometry", id))
				testing.expect(t, (cast(^Basic_Material)gun.material).texture != 0, fmt.tprintf("weapon %d must load a texture", id))
				assets := [?]string{model, texture, icon}
				for asset in assets {
					testing.expect(t, strings.contains(string(manifest), asset), fmt.tprintf("packagers must include %s", asset))
				}
				testing.expect(t, (arms.attachment != nil) == (weapon.has_attachment && first_person), fmt.tprintf("weapon %d must use the correct sight in each view", id))
				testing.expect(t, (arms.weapon_left != nil) == weapon.akimbo, "Akimbo must include both guns")
				if first_person && id == 4 {
					testing.expect(t, abs(arms.right.anchor.position.z - 5.1) < 0.0001, "Revolver hand offset must affect the arms without moving the gun")
				}
				scene := client.fps_scene if first_person else client.scene
				scene_add_player_mesh(scene, rig, int(player.loadout_size))
				camera := camera_init(DEFAULT_WEAPON_FOV)
				camera.position.y = player.height - shared.GAME_CONSTANTS.camera_height
				if !first_person {
					camera.position = {14, 11, 20}
					camera.rotation = {-0.15, math.atan2(f32(14), f32(20)), 0}
				}
				aims := [?]f32{0, 1}
				for aim in aims {
					if aim == 1 && (!first_person || weapon.no_aim || weapon.melee) { continue }
					player.aim_val = aim
					camera.zoom = 1 + (weapon.zoom - 1) * aim
					player_update_meshes(player, false)
					scoped := first_person && weapon.scope && aim == 1
					testing.expect(t, gun.visible != scoped, "ADS must hide scoped first-person weapons and restore them when unscoped")
					if scoped {
						for mesh in scene.meshes {
							testing.expect(t, !mesh.visible, "scoping must hide the hands as well as the weapon")
						}
					}
					// Isolate the weapon: visible hands/body must not mask a missing gun.
					for mesh in scene.meshes { mesh.visible = mesh.visible && (mesh == gun || mesh == arms.weapon_left || mesh == arms.attachment) }
					gl.ClearColor(0, 0, 0, 1)
					gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
					scene_render(scene, &camera, 640, 360)
					if first_person && aim == 1 {
						// Sight/weapon pose in camera space must remain stable when
						// looking around; testing only straight ahead hides rig errors.
						reference := camera.world_inverse_matrix * gun.transform_matrix * shared.Vec4{0, 0, 0, 1}
						for direction in ([]shared.Vec2{{0.6, 1.4}, {-0.5, -2.8}}) {
							player.direction = direction
							camera.rotation = {direction.x, direction.y, 0}
							player_update_meshes(player, false)
							camera_update_world_inverse_matrix(&camera)
							mesh_update_transform_matrix(gun)
							actual := camera.world_inverse_matrix * gun.transform_matrix * shared.Vec4{0, 0, 0, 1}
							testing.expect(t, abs(actual.x-reference.x) < 0.001 && abs(actual.y-reference.y) < 0.001 && abs(actual.z-reference.z) < 0.001,
								fmt.tprintf("weapon %d ADS pose must follow the camera at any pitch/yaw", id))
						}
						player.direction, camera.rotation = {}, {}
						player_update_meshes(player, false)
					}
					gl.ReadPixels(0, 0, 640, 360, gl.RGB, gl.UNSIGNED_BYTE, raw_data(pixels))
					visible := 0
					for i := 0; i < len(pixels); i += 3 {
						if pixels[i] > 0 || pixels[i + 1] > 0 || pixels[i + 2] > 0 { visible += 1 }
					}
					testing.expect(t, (scoped && visible == 0) || (!scoped && visible > 20 && visible < 640 * 360 * 0.8), fmt.tprintf("weapon %d %s must render at a sensible size (first person=%v aim=%v pixels=%d)", id, weapon.name, first_person, aim, visible))
					testing.expect(t, gl.GetError() == gl.NO_ERROR, fmt.tprintf("weapon %d must render without OpenGL errors", id))
					when #config(WEAPON_PREVIEW, false) {
						if first_person {
							file := make([dynamic]u8)
							defer delete(file)
							append(&file, "P6\n640 360\n255\n")
							for row := 359; row >= 0; row -= 1 { append(&file, ..pixels[row * 640 * 3:(row + 1) * 640 * 3]) }
							testing.expect(t, os.write_entire_file(fmt.tprintf("bin/weapon_%02d_aim_%.0f.ppm", id, aim), file[:]) == nil, "could not export weapon preview")
						}
					}
				}
				player.aim_val = 0
				player_update_meshes(player, false)
				testing.expect(t, gun.visible, "weapon must reappear when leaving ADS")
				client_clear_players(&client)
				testing.expect(t, scene.mesh_count == 0, "removing a weapon must detach all meshes")
			}
		}
		testing.expect(t, supported == 18, "render check must cover all 18 supported weapons")
	}
}
