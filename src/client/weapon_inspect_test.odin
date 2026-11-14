package main

import "core:math"
import "core:testing"
import "base:runtime"
import "core:fmt"
import "core:os"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import menuui "../menu"
import shared "../shared"

when ODIN_TEST {
	@(test)
	inspect_rifle_and_knife_render :: proc(t: ^testing.T) {
		logger := context.logger
		context = runtime.default_context()
		context.logger = logger
		if !testing.expect(t, bool(glfw.Init())) do return
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(960, 540, "Inspect animation", nil, nil)
		if !testing.expect(t, window != nil) do return
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		gl.Viewport(0, 0, 960, 540)
		gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
		client := Client{scene=scene_init(), fps_scene=scene_init(), bindings=menuui.default_bindings(), viewmodel_settings=menuui.DEFAULT_VIEWMODEL_SETTINGS}
		previous_client := g_client
		g_client = &client
		defer { g_client = previous_client }
		config := shared.config_load_gameplay()
		defer shared.config_destroy_gameplay(config)
		map_inst := shared.Map{death_y=-1000}
		shared.game_configure(&client.game, &config.game, []^shared.Map{&map_inst}, nil, config.weapons, config.classes)
		shared.game_init(&client.game, 0, 0, true)
		defer {
			client_clear_players(&client)
			shared.game_destroy(&client.game)
			scene_fini(client.fps_scene)
			scene_fini(client.scene)
			resource_cache_fini()
		}
		pixels, baseline := make([]u8, 960*540*3), make([]u8, 960*540*3)
		defer delete(pixels); defer delete(baseline)
		for id in ([2]i32{1, 12}) {
			loadout := [1]i32{id}
			config.classes[0].loadout, config.classes[0].secondary = loadout[:], false
			player := shared.player_init(&client.game)
			shared.game_players_add(&client.game, player)
			shared.player_spawn(player, 0)
			player.is_you, player.position, player.swap_timer = true, {}, 0
			client.me = player
			client.inspect_pressed = false
			player_generate_meshes(player, true)
			scene_add_player_mesh(client.fps_scene, cast(^Player_Mesh)player.mesh, int(player.loadout_size))
			camera := camera_init(DEFAULT_WEAPON_FOV)
			camera.position.y = player.height-shared.GAME_CONSTANTS.camera_height
			for stage in 0..<3 {
				read_f := proc(window: glfw.WindowHandle, code: i32) -> bool { return code=='F' }
				down := stage==1 && client_action_down(&client, .INSPECT, read_f)
				client_update_inspect(&client, down, true, stage==2, stage==1 ? 1 : 0)
				player_update_meshes(player, false)
				gl.ClearColor(0, 0, 0, 1)
				gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
				scene_render(client.fps_scene, &camera, 960, 540)
				gl.ReadPixels(0, 0, 960, 540, gl.RGB, gl.UNSIGNED_BYTE, raw_data(pixels))
				if stage==0 { copy(baseline, pixels) }
				visible, changed := 0, 0
				for value, i in pixels {
					if value>0 { visible += 1 }
					if value!=baseline[i] { changed += 1 }
				}
				testing.expect(t, visible>300, "rifle and knife must stay visible while inspecting")
				if stage==1 { testing.expect(t, player.inspecting && changed>300, "the F binding must visibly change the rendered pose") }
				if stage==2 { testing.expect(t, !player.inspecting && changed==0, "cancelling must restore the exact original rendered pose") }
				when #config(INSPECT_PREVIEW, false) {
					file := make([dynamic]u8)
					defer delete(file)
					append(&file, "P6\n960 540\n255\n")
					for row:=539; row>=0; row-=1 { append(&file, ..pixels[row*960*3:(row+1)*960*3]) }
					testing.expect(t, os.write_entire_file(fmt.tprintf("bin/inspect_%d_%d.ppm", id, stage), file[:])==nil)
				}
			}
			client_clear_players(&client)
		}
		testing.expect(t, gl.GetError()==gl.NO_ERROR)
	}

	@(test)
	inspect_toggle_cancellation_and_frame_rate :: proc(t: ^testing.T) {
		weapon := shared.WEAPON_AK47
		player := shared.Player{weapon=&weapon, active=true, can_throw=true}
		client := Client{me=&player}
		client_update_inspect(&client, true, true, false, 1.0/60)
		testing.expect(t, player.inspecting && client.inspect_angle>0, "F must begin inspecting")
		for _ in 0..<59 { client_update_inspect(&client, true, true, false, 1.0/60) }
		angle_60 := client.inspect_angle
		testing.expect(t, player.inspecting && abs(angle_60-math.PI/2.8)<0.003, "holding inspect must not repeatedly toggle or restart the animation")
		client_update_inspect(&client, false, true, false, 0)
		client_update_inspect(&client, true, true, false, 0)
		testing.expect(t, !player.inspecting && client.inspect_angle==0, "a second press must restore the hipfire pose")
		client = Client{me=&player}
		for _ in 0..<360 { client_update_inspect(&client, true, true, false, 1.0/360) }
		testing.expect(t, abs(client.inspect_angle-angle_60)<0.00001, "inspect must have the same speed at 60 and 360 FPS")
		for interruption in 0..<7 {
			player.active, player.reload_timer, player.swap_timer, player.aim_val, weapon.no_inspect = true, 0, 0, 0, false
			client_update_inspect(&client, false, true, false, 0)
			if !player.inspecting { client_update_inspect(&client, true, true, false, 0) }
			switch interruption {
			case 0: player.reload_timer = 1
			case 1: player.swap_timer = 1
			case 2: player.aim_val = 0.1
			case 3: player.active = false
			case 4: weapon.no_inspect = true
			case 5: player.loadout_index += 1
			}
			client_update_inspect(&client, true, true, interruption==6, 0)
			testing.expect(t, !player.inspecting && client.inspect_angle==0, "reload, swap, aim, death, unsupported weapons and combat input must cancel inspect")
		}
		player.active, weapon.no_inspect = true, false
		client_update_inspect(&client, false, true, false, 0)
		client_update_inspect(&client, true, false, false, 0)
		client_update_inspect(&client, true, true, false, 0)
		testing.expect(t, !player.inspecting, "holding the bind through a menu/freecam must not start an inspect on resume")
		weapon.melee, player.can_throw = true, false
		client_update_inspect(&client, false, true, false, 0)
		client_update_inspect(&client, true, true, false, 0)
		testing.expect(t, !player.inspecting, "a thrown knife must not be inspected")
	}

	@(test)
	inspect_animates_local_rig_and_restores_pose :: proc(t: ^testing.T) {
		map_inst: shared.Map
		game := shared.Game{map_inst=&map_inst, config=shared.DEFAULT_GAME_CONFIG}
		weapon := shared.WEAPON_AK47
		root, body, upper: Mesh_Transform
		gun: Mesh
		lower: Color_Cube
		right, left := Player_Arm_Mesh{lower=&lower}, Player_Arm_Mesh{lower=&lower}
		arms := Player_Arms{right=&right, left=&left, weapon_right=&gun}
		rig := Player_Mesh{anchor=&root, body_anchor=&body, upper_body_anchor=&upper}
		append(&rig.arms, &arms)
		defer delete(rig.arms)
		player := shared.Player{game=&game, weapon=&weapon, mesh=rawptr(&rig), is_you=true, render_you=true, active=true, loadout_size=1, can_throw=true}
		client := Client{me=&player, viewmodel_settings=menuui.DEFAULT_VIEWMODEL_SETTINGS, crosshair_settings=menuui.DEFAULT_CROSSHAIR_SETTINGS}
		previous_client := g_client
		g_client = &client
		defer { g_client = previous_client }
		client.viewmodel_settings.values[.BOBBING], client.viewmodel_settings.values[.LEANING] = 0, 0
		player_update_meshes(&player, false)
		baseline := arms.anchor
		client_update_inspect(&client, true, true, false, 1)
		player_update_meshes(&player, false)
		testing.expect(t, arms.anchor.rotation.y>1 && arms.anchor.position.x<baseline.position.x && arms.anchor.rotation.z<baseline.rotation.z,
			"inspect must rotate and reposition the actual weapon rig even with bobbing and leaning disabled")
		inspected := arms.anchor
		player_update_meshes(&player, false)
		testing.expect(t, arms.anchor == inspected, "render updates must not accumulate inspect offsets")
		client_update_inspect(&client, true, true, true, 0)
		player_update_meshes(&player, false)
		testing.expect(t, arms.anchor == baseline, "combat cancellation must fully restore the normal weapon transform")
		weapon = shared.WEAPON_KNIFE
		client_update_inspect(&client, false, true, false, 0)
		player_update_meshes(&player, false)
		blade := gun.transform
		client_update_inspect(&client, true, true, false, 1)
		player_update_meshes(&player, false)
		testing.expect(t, player.inspecting && right.pivot.rotation.y>2 && gun.transform.position.y<blade.position.y,
			"the knife must use its hand and blade inspect animation")
		client_update_inspect(&client, false, true, false, 0)
		client_update_inspect(&client, true, true, false, 0)
		player_update_meshes(&player, false)
		testing.expect(t, gun.transform == blade && right.pivot.rotation.y==0, "ending knife inspect must restore its blade and hand")
	}
}
