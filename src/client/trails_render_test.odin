package main

import "base:runtime"
import "core:math"
import "core:testing"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import shared "../shared"
import menuui "../menu"

when ODIN_TEST {
	@(test)
	bullet_trails_render :: proc(t: ^testing.T) {
		context = runtime.default_context()
		if !testing.expect(t, bool(glfw.Init()), "GLFW initialization failed") do return
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(640, 360, "Bullet trails regression", nil, nil)
		if !testing.expect(t, window != nil, "hidden OpenGL window failed") do return
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
		client := Client{window = window, scene = scene_init()}
		g_client = &client
		defer { g_client = nil }
		weapons := shared.WEAPONS_LIST
		client.game.weapons = weapons[:]
		map_inst: shared.Map
		client.game.map_inst = &map_inst
		defer {
			client_clear_tracers(&client)
			delete(client.game.players)
			delete(map_inst.objects)
			scene_fini(client.scene)
			resource_cache_fini()
		}

		// Hits, player hits, and misses all use their resolved shot endpoint;
		// the bright part is a short moving segment rather than a full ray.
		impact := shared.Bullet_Impact{origin = {-100, 0, -80}, position = {100, 0, -80}, shooter_uid = 7, weapon_id = 1}
		client_add_tracer(&client, &impact)
		if !testing.expect(t, len(client.tracer_markers) == 1 && len(client.bullet_trails) == 0, "automatic rifles need a tracer without sniper smoke") do return
		client_tick_tracers(&client, 0.02)
		tracer := &client.tracer_markers[0]
		testing.expect(t, abs(tracer.distance - 60) < 0.001 && abs(tracer.mesh.transform.position.x - (-48)) < 0.001, "tracer must move at the current browser speed of 3000 units/sec")
		testing.expect(t, tracer.mesh.transform.scale == (shared.Vec3{0.5, 8, 0.5}), "tracer must use the current browser width and length")
		material := cast(^Basic_Material)tracer.mesh.material
		testing.expect(t, material.unlit && material.no_fog && !material.transparent && material.color == shared.hex_to_vec(0xffffdb), "tracers must retain their pale color independent of world lighting and fog")
		mesh_update_transform_matrix(tracer.mesh)
		tip := tracer.mesh.transform_matrix * shared.Vec4{0, 1, 0, 1}
		testing.expect(t, abs(tip.x - (-40)) < 0.001 && abs(tip.z + 80) < 0.001, "tracer geometry must align with its exact shot path")

		client.camera = camera_init(math.PI / 2)
		client.camera.position = {0, 0, 40}
		gl.Viewport(0, 0, 640, 360)
		gl.ClearColor(0, 0, 0, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
		scene_render(client.scene, &client.camera, 640, 360)
		pixels := make([]u8, 640 * 360 * 3)
		defer delete(pixels)
		gl.ReadPixels(0, 0, 640, 360, gl.RGB, gl.UNSIGNED_BYTE, raw_data(pixels))
		visible := 0
		for i := 0; i < len(pixels); i += 3 {
			if pixels[i] > 0 || pixels[i + 1] > 0 || pixels[i + 2] > 0 { visible += 1 }
		}
		testing.expect(t, visible > 3 && visible < 1000, "the moving tracer must produce a short visible streak in the world render")
		testing.expect(t, gl.GetError() == gl.NO_ERROR, "bullet tracer render produced an OpenGL error")
		client_tick_tracers(&client, 0.02)
		testing.expect(t, abs(client.tracer_markers[0].mesh.transform.position.x - 12) < 0.001, "a second frame must advance the streak rather than fade a static beam")
		client_tick_tracers(&client, 1)
		mesh_update_transform_matrix(client.tracer_markers[0].mesh)
		tip = client.tracer_markers[0].mesh.transform_matrix * shared.Vec4{0, 1, 0, 1}
		testing.expect(t, abs(tip.x - impact.position.x) < 0.001, "a slow frame must clip the tracer to the wall instead of extending through it")
		client_tick_tracers(&client, 0.001)
		testing.expect(t, len(client.tracer_markers) == 0 && client.scene.mesh_count == 0, "tracers must disappear after reaching the endpoint")

		impact.position.x = impact.origin.x + 19
		client_add_tracer(&client, &impact)
		testing.expect(t, len(client.tracer_markers) == 0, "shots shorter than 20 units do not need a tracer")
		impact.position.x = impact.origin.x + 2000
		client_add_tracer(&client, &impact)
		testing.expect(t, len(client.tracer_markers) == 1 && client.tracer_markers[0].travel_distance == 500, "long and missed shots must cap visible tracer travel at 500 units")
		client_clear_tracers(&client)
		impact.weapon_id = 12
		client_add_tracer(&client, &impact)
		impact.weapon_id = 18
		client_add_tracer(&client, &impact)
		testing.expect(t, len(client.tracer_markers) == 0 && len(client.bullet_trails) == 0, "knives and Blaster bolts must not create hitscan trails")
		original_rifle := weapons[1]
		physical_rifle := original_rifle^
		physical_rifle.projectile = true
		physical_rifle.projectile_disable = true
		weapons[1] = &physical_rifle
		impact.weapon_id = 1
		client_add_tracer(&client, &impact)
		testing.expect(t, len(client.tracer_markers) == 1, "a disabled physical bullet must keep the normal hitscan tracer")
		client_clear_tracers(&client)
		client.game.config.bullet_drop = true
		client_add_tracer(&client, &impact)
		testing.expect(t, len(client.tracer_markers) == 0, "bullet-drop mode must not duplicate an enabled physical bullet with a tracer")
		client.game.config.bullet_drop = false
		weapons[1] = original_rifle

		impact.weapon_id = 0
		impact.position.x = impact.origin.x + 300
		client_add_tracer(&client, &impact)
		if !testing.expect(t, len(client.tracer_markers) == 1 && len(client.bullet_trails) == 1, "snipers need a separate smoke trail behind their tracer") do return
		client_tick_tracers(&client, 0.02)
		testing.expect(t, abs(client.bullet_trails[0].length - 60) < 0.001 && abs(client.bullet_trails[0].width - 0.4428) < 0.001, "sniper smoke must grow with the bullet and shrink over time")
		smoke_material := cast(^Basic_Material)client.bullet_trails[0].mesh.material
		testing.expect(t, smoke_material.transparent && abs(smoke_material.color.w - 0.18) < 0.001, "sniper smoke must remain faint and translucent")
		client_tick_tracers(&client, 0.2)
		testing.expect(t, client.bullet_trails[0].length == 150, "sniper smoke must cap at half the visible tracer range as in the current browser")
		client_tick_tracers(&client, 1.3)
		testing.expect(t, len(client.tracer_markers) == 0 && len(client.bullet_trails) == 0 && client.scene.mesh_count == 0, "all trail meshes must be released when their effects expire")

		// Muzzle offsets belong to the rig anchor, not the scaled OBJ. A nearby
		// wall may obstruct the muzzle even with a clear eye-origin shot.
		arms := Player_Arms{anchor = Mesh_Transform{position = {3, 4, 5}, scale = {1, 1, 1}}}
		rig := Player_Mesh{}
		append(&rig.arms, &arms)
		defer delete(rig.arms)
		loadout := [?]i32{1}
		player := shared.Player{uid = 7, loadout = loadout[:], loadout_size = 1, mesh = &rig}
		append(&client.game.players, &player)
		impact = shared.Bullet_Impact{origin = {0, 0, 0}, position = {0, 0, -100}, shooter_uid = 7, weapon_id = 1}
		start := bullet_tracer_origin(&client, &impact, client.game.weapons[1])
		testing.expect(t, abs(start.x - 3) < 0.001 && abs(start.y - 3.95) < 0.001 && abs(start.z + 0.1) < 0.001, "tracer start must follow the barrel anchor using the weapon's actual muzzle offset")
		arms.anchor.position = {0, 0, -30}
		wall := shared.Object{active = true, collision_type = .BOX, position = {0, -10, -10}, scale = {20, 20, 1}}
		append(&map_inst.objects, &wall)
		start = bullet_tracer_origin(&client, &impact, client.game.weapons[1])
		testing.expect(t, start == impact.origin, "a muzzle beyond a wall must fall back to the unobstructed shot origin")

		// Every event in a batched burst must advance the barrel independently;
		// this also covers peer shots, whose packets do not identify a barrel.
		clear(&map_inst.objects)
		loadout[0] = 9
		impact.weapon_id = 9
		for left_handed in ([]bool{false, true}) {
			player.left_handed = left_handed
			arms.next_left_muzzle = false
			arms.anchor.position = {left_handed ? -1.5 : 1.5, 0, 0}
			for shot in 0..<6 {
				client_add_tracer(&client, &impact)
				tracer := client.tracer_markers[len(client.tracer_markers)-1]
				expected_x: f32 = (shot % 2 == 0 ? 1.5 : -1.5) * (left_handed ? -1.0 : 1.0)
				testing.expect(t, abs(tracer.start_position.x-expected_x) < 0.001 && abs(tracer.start_position.z+3.6) < 0.001,
					"Uzi tracers must alternate between both barrels, including mirrored rigs and queued shots")
			}
			client_clear_tracers(&client)
		}

		// Ownership comes from the shooter UID, including while the local player
		// is inactive. Both switches must filter tracers and sniper smoke without
		// changing the resolved shot or interfering with the opposite category.
		client.me = &player
		impact.weapon_id = 0
		for hide_others in ([2]bool{false,true}) {
			for hide_yours in ([2]bool{false,true}) {
				client.trail_settings = {hide_others=hide_others, hide_yours=hide_yours}
				for shooter in ([2]i32{player.uid,player.uid+1}) {
					impact.shooter_uid = shooter
					original := impact
					client_add_tracer(&client, &impact)
					testing.expect(t, impact == original, "trail visibility must preserve resolved hit and damage information")
				}
				expected := (hide_others ? 0 : 1) + (hide_yours ? 0 : 1)
				testing.expect(t, len(client.tracer_markers) == expected && len(client.bullet_trails) == expected && client.scene.mesh_count == i32(2*expected),
					"each trail switch must independently filter local or remote tracers and smoke")
				client_clear_tracers(&client)
			}
		}
		client.trail_settings = {}
		for shooter in ([2]i32{player.uid,player.uid+1}) {
			impact.shooter_uid = shooter
			client_add_tracer(&client, &impact)
		}
		client.menu.page = .SETTINGS
		menuui.prepare_settings(&client.menu, menuui.View{trails=client.trail_settings})
		menuui.activate(&client.menu, {action={kind=.TRAILS_TOGGLE, index=1}})
		client_tick_tracers(&client, 0)
		for tracer in client.tracer_markers { testing.expect(t, tracer.mesh.visible == !tracer.is_yours, "Your trails must preview immediately on existing tracer meshes") }
		for trail in client.bullet_trails { testing.expect(t, trail.mesh.visible == !trail.is_yours, "Your trails must preview immediately on existing sniper smoke") }
		menuui.activate(&client.menu, {action={kind=.TRAILS_TOGGLE}})
		client_tick_tracers(&client, 0)
		for tracer in client.tracer_markers { testing.expect(t, !tracer.mesh.visible, "turning off both switches must hide every existing tracer") }
		for trail in client.bullet_trails { testing.expect(t, !trail.mesh.visible, "turning off both switches must hide every existing smoke trail") }
		testing.expect(t, len(client.tracer_markers) == 2 && len(client.bullet_trails) == 2 && client.trail_settings == menuui.Trail_Settings{},
			"preview must preserve committed preferences and existing effects for Cancel")
		menuui.activate(&client.menu, {action={kind=.SETTINGS_CANCEL}})
		client_tick_tracers(&client, 0)
		for tracer in client.tracer_markers { testing.expect(t, tracer.mesh.visible, "Cancel must restore existing tracers") }
		for trail in client.bullet_trails { testing.expect(t, trail.mesh.visible, "Cancel must restore existing sniper smoke") }
		client_clear_tracers(&client)
		client.me = nil
		client.trail_settings.hide_yours = true
		impact.shooter_uid = 0
		client_add_tracer(&client, &impact)
		testing.expect(t, len(client.tracer_markers) == 1, "without a local player, UID zero must not be mistaken for one of your shots")
	}
}
