package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:encoding/json"
import "core:strings"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import stbi "vendor:stb/image"
import shared "../shared"

Client :: struct {
	window: glfw.WindowHandle,
	camera: Camera,
	scene:  ^Scene,
	fps_scene: ^Scene,
	ui:     ^UI,

	mouse_state: struct {
		locked:  bool,
		last_pos: shared.Vec2,
	},

	windowed_rect: struct {
		x, y, width, height: i32,
	},

	last_noclip_key:   bool,
	last_debug_key:    bool,
	last_freecam_key:  bool,
	last_fullscreen_key: bool,
	last_swap_key:     u8,
	last_mouse_button: bool,
	in_game:           bool,
	selected_class:    i32,
	class_picker_open: bool,
	freecam_enabled:   bool,

	game: shared.Game,
	me:   ^shared.Player,
	impact_markers: [dynamic]Impact_Marker,
	show_fps:       bool,
	fps_value:      u32,
	fps_frames:     u32,
	fps_elapsed:    f32,
}

g_client: ^Client

Client_Options :: struct {
	map_name: string,
	class_name: string,
	show_help: bool,
	show_fps:  bool,
}

print_client_help :: proc() {
	fmt.println("KrunkNative Odin client")
	fmt.println()
	fmt.printf("Usage: %s [options]\n", os.args[0])
	fmt.println()
	fmt.println("Options:")
	fmt.println("  -h, --help            Show this help message")
	fmt.println("  -m, --map <name>      Load a map by name (for example: burg)")
	fmt.println("  -c, --class <name>    Spawn as the given class (for example: hunter)")
	fmt.println("      --fps             Show an FPS meter")
	fmt.println()
	fmt.println("Available maps:")

	for name in shared.DEFAULT_MAP_NAMES {
		fmt.printf("  %s\n", name)
	}
	fmt.println("  ss_v3 (sandstorm_v3)")
	fmt.println()
	fmt.println("Available classes:")

	for i in 0 ..< shared.class_config_name_count() {
		fmt.printf("  %s\n", shared.class_config_name(i))
	}
}

normalize_map_name :: proc(name: string) -> string {
	if strings.has_suffix(name, ".json") {
		return name[:len(name) - len(".json")]
	}

	return name
}

map_name_is_valid :: proc(name: string) -> bool {
	if name == "ss_v3" {
		return true
	}

	for available in shared.DEFAULT_MAP_NAMES {
		if name == available {
			return true
		}
	}

	return false
}

map_asset_name :: proc(name: string) -> string {
	if name == "ss_v3" {
		return "sandstorm_v3"
	}

	return name
}

parse_client_options :: proc() -> (options: Client_Options, ok: bool) {
	ok = true

	for i := 1; i < len(os.args); i += 1 {
		arg := os.args[i]

		switch arg {
		case "-h", "--help":
			options.show_help = true
		case "--fps", "--show-fps":
			options.show_fps = true
		case "-m", "--map":
			if i + 1 >= len(os.args) {
				fmt.eprintf("Missing map name after %s.\n\n", arg)
				return options, false
			}

			i += 1
			options.map_name = normalize_map_name(os.args[i])
		case "-c", "--class":
			if i + 1 >= len(os.args) {
				fmt.eprintf("Missing class name after %s.\n\n", arg)
				return options, false
			}

			i += 1
			options.class_name = os.args[i]
		case:
			if strings.has_prefix(arg, "--map=") {
				options.map_name = normalize_map_name(arg[len("--map="):])
			} else if strings.has_prefix(arg, "--class=") {
				options.class_name = arg[len("--class="):]
			} else {
				fmt.eprintf("Unknown option: %s\n\n", arg)
				return options, false
			}
		}
	}

	if len(options.map_name) > 0 && !map_name_is_valid(options.map_name) {
		fmt.eprintf("Unknown map: %s\n\n", options.map_name)
		return options, false
	}

	if len(options.class_name) > 0 && shared.class_config_index(options.class_name) < 0 {
		fmt.eprintf("Unknown class: %s\n\n", options.class_name)
		return options, false
	}

	return options, true
}

client_update_fps :: proc(client: ^Client, delta: f32) {
	if !client.show_fps {
		return
	}

	client.fps_frames += 1
	client.fps_elapsed += delta

	if client.fps_elapsed >= 0.25 {
		client.fps_value = u32(math.round(f32(client.fps_frames) / client.fps_elapsed))
		client.fps_frames = 0
		client.fps_elapsed = 0
	}
}

fps_render :: proc(client: ^Client) {
	if !client.show_fps {
		return
	}

	text := fmt.tprintf("FPS %d", client.fps_value)

	text_size := 20.0 * client.ui.scale
	padding := 12.0 * client.ui.scale
	width := ui_measure_text(client.ui, text, text_size) + padding * 2.0
	height := 38.0 * client.ui.scale
	x := 20.0 * client.ui.scale
	y := 20.0 * client.ui.scale

	ui_round_rect(client.ui, shared.Vec4{0.0, 0.0, 0.0, 0.55}, x, y, width, height, 6.0 * client.ui.scale)
	ui_fill_text(client.ui, shared.Vec4{1.0, 1.0, 1.0, 0.95}, text, x + padding, y + 27.0 * client.ui.scale, text_size)
}

client_load_map :: proc(client: ^Client) {
	if client.game.map_inst == nil {
		return
	}

	for i in 0 ..< len(client.game.map_inst.objects) {
		object := client.game.map_inst.objects[i]
		if object.mesh != nil {
			scene_add_mesh(client.scene, cast(^Mesh)object.mesh)
		}
	}
}

set_window_icon :: proc(client: ^Client) {
	icon_path := shared.concat(shared.assets_path(), "img/icon.png")
	defer delete(icon_path)
	c_icon_path := strings.clone_to_cstring(icon_path)
	defer delete(c_icon_path)

	w, h, channels: i32
	pixels := stbi.load(c_icon_path, &w, &h, &channels, 4)
	if pixels == nil {
		fmt.eprintln("Failed to load window icon: img/icon.png")
		return
	}
	defer stbi.image_free(pixels)

	image := glfw.Image {
		width  = w,
		height = h,
		pixels = pixels,
	}

	glfw.SetWindowIcon(client.window, []glfw.Image{image})
}

client_unload_map :: proc(client: ^Client) {
	if client.game.map_inst == nil {
		return
	}

	for object in client.game.map_inst.objects {
		if object.mesh != nil {
			mesh := cast(^Mesh)object.mesh
			scene_remove_mesh(client.scene, mesh)
			mesh_fini(mesh)
			object.mesh = nil
		}
	}

	resource_trim_texture_cache()
	resource_trim_geometry_cache()
}

client_load_current_map :: proc(client: ^Client) {
	if client.game.map_inst == nil {
		return
	}

	shared.map_load_meshes(client.game.map_inst, prefab_init_cb)
	client_load_map(client)

	renderable := 0
	for object in client.game.map_inst.objects {
		if object.mesh != nil {
			renderable += 1
		}
	}
	fmt.printf(
		"[Map] parsed %d objects, built %d renderable meshes\n",
		len(client.game.map_inst.objects),
		renderable,
	)
	resource_print_stats("map loaded")
}

client_tick_textures :: proc(client: ^Client, now: f32) {
	if client.game.map_inst == nil {
		return
	}

	for object in client.game.map_inst.objects {
		client_animate_object_texture(object, now)
	}
}

client_tick_impacts :: proc(client: ^Client, delta: f32) {
	for impact in client.game.impacts {
		material := basic_material_init()
		if material == nil {
			continue
		}

		material.color = shared.Vec4{0.045, 0.04, 0.035, 1.0}

		mesh := mesh_init(create_plane_geo(), &material.base)
		mesh.transform.position = impact.position + impact.normal * 0.02
		mesh.transform.scale = shared.Vec3{0.16, 0.01, 0.16}

		// Plane geometry faces +Y. Rotate it onto the hit face normal.
		if impact.normal.x > 0 {
			mesh.transform.rotation.z = -math.PI * 0.5
		} else if impact.normal.x < 0 {
			mesh.transform.rotation.z = math.PI * 0.5
		} else if impact.normal.z > 0 {
			mesh.transform.rotation.x = math.PI * 0.5
		} else if impact.normal.z < 0 {
			mesh.transform.rotation.x = -math.PI * 0.5
		} else if impact.normal.y < 0 {
			mesh.transform.rotation.x = math.PI
		}

		scene_add_mesh(client.scene, mesh)
		append(&client.impact_markers, Impact_Marker{mesh = mesh, lifetime = 8.0})
	}
	clear(&client.game.impacts)

	for i := len(client.impact_markers) - 1; i >= 0; i -= 1 {
		marker := &client.impact_markers[i]
		marker.lifetime -= delta

		if marker.lifetime <= 0 {
			scene_remove_mesh(client.scene, marker.mesh)
			mesh_fini(marker.mesh)
			unordered_remove(&client.impact_markers, i)
		}
	}
}

client_clear_impacts :: proc(client: ^Client) {
	for marker in client.impact_markers {
		scene_remove_mesh(client.scene, marker.mesh)
		mesh_fini(marker.mesh)
	}
	delete(client.impact_markers)
	clear(&client.game.impacts)
}

client_update_freecam :: proc(client: ^Client, mouse_delta: shared.Vec2, delta: f32) {
	client.camera.rotation.x -= mouse_delta.y * shared.GAME_CONSTANTS.mouse_sensitivity / client.camera.zoom
	client.camera.rotation.y -= mouse_delta.x * shared.GAME_CONSTANTS.mouse_sensitivity / client.camera.zoom
	client.camera.rotation.x = max(-math.PI * 0.5, min(math.PI * 0.5, client.camera.rotation.x))
	client.camera.rotation.y = math.mod(client.camera.rotation.y, 2.0 * math.PI)

	forward := glfw.GetKey(client.window, glfw.KEY_W) == glfw.PRESS
	back := glfw.GetKey(client.window, glfw.KEY_S) == glfw.PRESS
	left := glfw.GetKey(client.window, glfw.KEY_A) == glfw.PRESS
	right := glfw.GetKey(client.window, glfw.KEY_D) == glfw.PRESS
	up := glfw.GetKey(client.window, glfw.KEY_SPACE) == glfw.PRESS
	down := glfw.GetKey(client.window, glfw.KEY_LEFT_CONTROL) == glfw.PRESS

	move := shared.Vec3{}
	if forward != back {
		move.x += forward ? -math.sin(client.camera.rotation.y) : math.sin(client.camera.rotation.y)
		move.z += forward ? -math.cos(client.camera.rotation.y) : math.cos(client.camera.rotation.y)
	}
	if left != right {
		move.x += left ? -math.cos(client.camera.rotation.y) : math.cos(client.camera.rotation.y)
		move.z += left ? math.sin(client.camera.rotation.y) : -math.sin(client.camera.rotation.y)
	}
	if up != down {
		move.y = up ? 1.0 : -1.0
	}

	length := math.sqrt(move.x * move.x + move.y * move.y + move.z * move.z)
	if length > 0.0 {
		move /= length
		client.camera.position += move * (20.0 * delta)
	}
}

client_enter_game :: proc(client: ^Client) {
	if !client.game.ready || client.in_game {
		return
	}

	client.in_game = true

	if client.game.is_local {
		if client.me == nil {
			client.me = shared.player_init(&client.game)

			if client.me == nil {
				client.in_game = false
				return
			}

			shared.game_players_add(&client.game, client.me)
		}

		client.me.is_you = true
		shared.player_spawn(client.me, client.selected_class)
		player_generate_meshes(client.me, true)
		shared.player_swap_weapon(client.me, 0, true, false, false)
		scene_add_player_mesh(client.fps_scene, cast(^Player_Mesh)client.me.mesh, int(client.me.loadout_size))
	}
}

client_tick :: proc(client: ^Client, now, delta: f32) {
	if !client.game.ready {
		return
	}

	client_update_fps(client, delta)

	debug_key := glfw.GetKey(client.window, glfw.KEY_GRAVE_ACCENT) == glfw.PRESS
	freecam_key := glfw.GetKey(client.window, glfw.KEY_RIGHT_BRACKET) == glfw.PRESS

	if debug_key && !client.last_debug_key {
		client_unload_map(client)

		if client.me != nil {
			scene_remove_player_mesh(client.fps_scene, cast(^Player_Mesh)client.me.mesh, int(client.me.loadout_size))
			player_meshes_fini(client.me)
			shared.player_destroy(client.me)
		}

		client.me = nil
		client.in_game = false

		shared.game_init(&client.game, -1, -1, true)
		client_load_current_map(client)
	}

	client.last_debug_key = debug_key
	if freecam_key && !client.last_freecam_key && client.me != nil && client.me.active {
		client.freecam_enabled = !client.freecam_enabled
	}
	client.last_freecam_key = freecam_key

	x, y := glfw.GetCursorPos(client.window)

	fullscreen_key := glfw.GetKey(client.window, glfw.KEY_F11) == glfw.PRESS

	if fullscreen_key && !client.last_fullscreen_key {
		fullscreen := glfw.GetWindowMonitor(client.window) != nil

		if fullscreen {
			glfw.SetWindowMonitor(client.window, nil,
				client.windowed_rect.x, client.windowed_rect.y,
				client.windowed_rect.width, client.windowed_rect.height, 0,
			)
		} else {
			client.windowed_rect.x, client.windowed_rect.y = glfw.GetWindowPos(client.window)
			client.windowed_rect.width, client.windowed_rect.height = glfw.GetWindowSize(client.window)

			monitor := glfw.GetPrimaryMonitor()
			mode := glfw.GetVideoMode(monitor)

			glfw.SetWindowMonitor(client.window, monitor, 0, 0, mode.width, mode.height, mode.refresh_rate)
		}
	}

	client.last_fullscreen_key = fullscreen_key
	client.mouse_state.locked = glfw.GetInputMode(client.window, glfw.CURSOR) == glfw.CURSOR_DISABLED

	left_down := glfw.GetMouseButton(client.window, glfw.MOUSE_BUTTON_LEFT) == glfw.PRESS

	if client.mouse_state.locked && glfw.GetKey(client.window, glfw.KEY_ESCAPE) == glfw.PRESS {
		glfw.SetInputMode(client.window, glfw.CURSOR, glfw.CURSOR_NORMAL)
		client.mouse_state.locked = false
	} else if !client.mouse_state.locked && left_down && !client.last_mouse_button {
		clicked_ui := false

		if client.class_picker_open {
			// Class picker screen: clicking a class selects it, clicking BACK
			// returns to the spawn screen.
			layout := class_picker_layout(client)
			for i in 0 ..< shared.class_config_name_count() {
				bx, by, bw, bh := class_button_rect(layout, i)
				if point_in_rect(f32(x), f32(y), bx, by, bw, bh) {
					client.selected_class = i32(i)
					clicked_ui = true
					break
				}
			}

			if !clicked_ui {
				bx, by, bw, bh := class_picker_back_rect(client)
				if point_in_rect(f32(x), f32(y), bx, by, bw, bh) {
					client.class_picker_open = false
					clicked_ui = true
				}
			}
		} else {
			// Spawn screen: clicking PICK YOUR CLASS opens the picker; clicking
			// anywhere else starts the game.
			bx, by, bw, bh := pick_your_class_button_rect(client)
			if point_in_rect(f32(x), f32(y), bx, by, bw, bh) {
				client.class_picker_open = true
				clicked_ui = true
			}
		}

		if !clicked_ui {
			glfw.SetInputMode(client.window, glfw.CURSOR, glfw.CURSOR_DISABLED)
			client.mouse_state.locked = true
			client.mouse_state.last_pos.x = f32(x)
			client.mouse_state.last_pos.y = f32(y)
		}
	}

	client.last_mouse_button = left_down

	if client.mouse_state.locked && (client.me == nil || !client.me.active) {
		client_enter_game(client)
	}

	if client.me == nil && client.game.map_inst != nil {
		client.camera.position = client.game.map_inst.camera_position
		client.camera.rotation.y += delta * 0.1
		client.camera.rotation.y = math.mod(client.camera.rotation.y, 2.0 * math.PI)
	}

	noclip_key := glfw.GetKey(client.window, glfw.KEY_N) == glfw.PRESS

	if client.me != nil && client.me.active {
		input := shared.Input{}
		mouse_delta := shared.Vec2{0, 0}

		mouse_delta.x = f32(x) - client.mouse_state.last_pos.x
		mouse_delta.y = f32(y) - client.mouse_state.last_pos.y

		input.move_dir = -1
		input.delta = delta

		input.x_dir = client.me.direction.x
		input.y_dir = client.me.direction.y

		if client.mouse_state.locked && !client.freecam_enabled {
			if noclip_key && !client.last_noclip_key {
				client.me.noclip = !client.me.noclip
			}

			input.x_dir -= mouse_delta.y * shared.GAME_CONSTANTS.mouse_sensitivity / client.camera.zoom
			input.y_dir -= mouse_delta.x * shared.GAME_CONSTANTS.mouse_sensitivity / client.camera.zoom

			input.jump = glfw.GetKey(client.window, glfw.KEY_SPACE) == glfw.PRESS
			input.crouch = glfw.GetKey(client.window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS
			input.reload = glfw.GetKey(client.window, glfw.KEY_R) == glfw.PRESS
			input.shoot = glfw.GetMouseButton(client.window, glfw.MOUSE_BUTTON_LEFT) == glfw.PRESS
			input.scope = glfw.GetMouseButton(client.window, glfw.MOUSE_BUTTON_RIGHT) == glfw.PRESS

			if glfw.GetKey(client.window, glfw.KEY_E) == glfw.PRESS {
				input.swap = 1
			} else if glfw.GetKey(client.window, glfw.KEY_Q) == glfw.PRESS {
				input.swap = 2
			}

			swap_key := input.swap

			if swap_key == client.last_swap_key {
				input.swap = 0
			}
			client.last_swap_key = swap_key

			forward := glfw.GetKey(client.window, glfw.KEY_W) == glfw.PRESS
			back := glfw.GetKey(client.window, glfw.KEY_S) == glfw.PRESS
			left := glfw.GetKey(client.window, glfw.KEY_A) == glfw.PRESS
			right := glfw.GetKey(client.window, glfw.KEY_D) == glfw.PRESS

			if forward != back {
				input.move_dir += forward ? 1 : 5
				if left != right {
					input.move_dir += right ? (forward ? 1 : -1) : (forward ? 7 : 1)
				}
			} else if left != right {
				input.move_dir += right ? 3 : 7
			}
		}

		if client.mouse_state.locked && client.freecam_enabled {
			client_update_freecam(client, mouse_delta, delta)
		}

		shared.player_queue_input(client.me, &input)

	} else {
		// Freecam is only valid while the player is spawned.
		client.freecam_enabled = false
	}

	client.mouse_state.last_pos.x = f32(x)
	client.mouse_state.last_pos.y = f32(y)
	client.last_noclip_key = noclip_key

	shared.game_tick(&client.game, now, delta)
	client_tick_impacts(client, delta)

	// Camera and view-model transforms must use the state produced by this
	// frame's input, otherwise fast mouse movement makes the gun trail and jump.
	if client.me != nil && client.me.active && !client.freecam_enabled {
		third_person := player_uses_third_person_camera(client.me)
		if third_person {
			// Full-body meshes use the map's camera offset. Keeping the camera at
			// the collision origin in this mode places it inside the character.
			client.camera.position = client.me.position + client.me.game.map_inst.config.cam_offset
			client.camera.position.y += client.me.height - shared.GAME_CONSTANTS.camera_height
		} else {
			client.camera.position = client.me.position
			client.camera.position.y += client.me.height - shared.GAME_CONSTANTS.camera_height
		}

		client.camera.rotation.x = client.me.direction.x + client.me.recoil_anim_y * shared.GAME_CONSTANTS.recoil_mlt
		client.camera.rotation.y = client.me.direction.y
		client.camera.zoom = 1.0 + (client.me.weapon.zoom - 1.0) * client.me.aim_val

		if client.me.mesh != nil {
			player_update_meshes(client.me, false)
		}
	}

	client_tick_textures(client, now)

	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
	scene_render(client.scene, &client.camera)

	gl.Clear(gl.DEPTH_BUFFER_BIT)
	scene_render(client.fps_scene, &client.camera)

	ui_update(client.ui)

	if !client.mouse_state.locked {
		hud_render(client, now)
	} else {
		overlay_render(client, delta)
	}
	fps_render(client)
}

resize_viewport :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	if glfw.GetCurrentContext() != window {
		return
	}

	gl.Viewport(0, 0, width, height)
}

main :: proc() {
	options, options_ok := parse_client_options()
	if options.show_help {
		print_client_help()
		return
	}
	if !options_ok {
		print_client_help()
		return
	}

	if !bool(glfw.Init()) {
		fmt.eprintln("Failed to init GLFW")
		return
	}
	defer glfw.Terminate()

	client := new(Client)
	defer free(client)
	g_client = client
	client.show_fps = options.show_fps

	client.camera.zoom = 1.0
	client.camera.fov = math.PI / 2.0
	client.camera.near = 0.1
	client.camera.far = 10000.0

	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)

	client.window = glfw.CreateWindow(1280, 720, "KrunkNative", nil, nil)
	if client.window == nil {
		fmt.eprintln("Failed to create window")
		return
	}
	defer glfw.DestroyWindow(client.window)

	set_window_icon(client)

	glfw.SetFramebufferSizeCallback(client.window, resize_viewport)
	glfw.MakeContextCurrent(client.window)

	if bool(glfw.RawMouseMotionSupported()) {
		glfw.SetInputMode(client.window, glfw.RAW_MOUSE_MOTION, 1)
	}

	gl.load_up_to(4, 5, glfw.gl_set_proc_address)

	glfw.SwapInterval(0)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	client.scene = scene_init()
	client.fps_scene = scene_init()
	client.ui = ui_init()

	if client.scene == nil || client.fps_scene == nil || client.ui == nil {
		return
	}

	config_path := shared.concat(shared.assets_path(), "config/game.toml")
	defer delete(config_path)
	gameplay_config := shared.config_load_gameplay(config_path)
	defer shared.config_destroy_gameplay(gameplay_config)

	if len(options.class_name) > 0 {
		client.selected_class = i32(shared.class_config_index(options.class_name))
	}

	if len(options.map_name) > 0 {
		g_map_name = options.map_name
		map_path := shared.concat(shared.assets_path(), fmt.tprintf("maps/%s.json", map_asset_name(options.map_name)))
		selected_map, map_ok := shared.map_load_from_file(map_path)
		delete(map_path)

		if !map_ok {
			fmt.eprintf("Failed to load map: %s\n", options.map_name)
			return
		}

		maps := []^shared.Map{selected_map}
		shared.game_configure(&client.game, nil, maps, nil, gameplay_config.weapons, gameplay_config.classes)
		shared.game_init(&client.game, 0, -1, true)
	} else {
		shared.load_default_maps()
		shared.game_configure(&client.game, nil, nil, nil, gameplay_config.weapons, gameplay_config.classes)
		shared.game_init(&client.game, -1, -1, true)
	}

	client_load_current_map(client)

	print_startup_info(client)
	free_all(context.temp_allocator)

	last_tick := f32(glfw.GetTime())

	for !bool(glfw.WindowShouldClose(client.window)) {
		now := f32(glfw.GetTime())
		delta := now - last_tick

		last_tick = now

		client_tick(client, now, delta)
		glfw.SwapBuffers(client.window)
		glfw.PollEvents()
		free_all(context.temp_allocator)
	}

	client_unload_map(client)
	client_clear_impacts(client)
	if client.me != nil && client.me.mesh != nil {
		scene_remove_player_mesh(client.fps_scene, cast(^Player_Mesh)client.me.mesh, int(client.me.loadout_size))
		player_meshes_fini(client.me)
	}
	game_destroy_maps := len(options.map_name) == 0
	selected_map := client.game.map_inst
	shared.game_destroy(&client.game)
	if game_destroy_maps {
		shared.unload_default_maps()
	} else if selected_map != nil {
		shared.map_destroy(selected_map)
	}
	scene_fini(client.fps_scene)
	scene_fini(client.scene)
	overlay_fini()
	ui_fini(client.ui)
	resource_cache_fini()
}

prefab_init_cb :: proc(object: ^shared.Object, colors: []shared.Vec4, raw_data: json.Value) -> rawptr {
	return rawptr(prefab_init(object, colors, raw_data))
}

cpu_model_name :: proc() -> string {
	when ODIN_OS == .Windows {
		// /proc/cpuinfo does not exist on Windows; the startup banner falls back
		// to a safe label rather than printing a confusing error.
		return "Windows"
	} else {
		cpuinfo, err := os.read_entire_file_from_path("/proc/cpuinfo", context.temp_allocator)
		if err != nil {
			return "Unknown CPU"
		}

		found: string
		cpuinfo_text := string(cpuinfo)
		for line in strings.split_lines_iterator(&cpuinfo_text) {
			if strings.has_prefix(line, "model name") {
				colon := strings.index(line, ":")
				if colon >= 0 {
					found = strings.clone(strings.trim_space(line[colon + 1:]))
					break
				}
			}
		}

		if len(found) > 0 {
			return found
		}

		return "Unknown CPU"
	}
}

print_startup_info :: proc(client: ^Client) {
	fmt.println("======================================================")
	fmt.println("  KrunkNative (Odin) - Startup Info")
	fmt.println("======================================================")

	major, minor, rev := glfw.GetVersion()
	fmt.printf("  Platform       : GLFW %d.%d.%d\n", major, minor, rev)

	vendor := cstring(gl.GetString(gl.VENDOR))
	renderer := cstring(gl.GetString(gl.RENDERER))
	version := cstring(gl.GetString(gl.VERSION))

	fmt.printf("  GPU Vendor     : %s\n", vendor)
	fmt.printf("  GPU            : %s\n", renderer)
	fmt.printf("  GL Version     : %s\n", version)
	fmt.printf("  CPU            : %s\n", cpu_model_name())

	monitor := glfw.GetPrimaryMonitor()
	if monitor != nil {
		monitor_name := glfw.GetMonitorName(monitor)
		mode := glfw.GetVideoMode(monitor)
		fmt.printf("  Monitor        : %s (%dx%d@%d)\n", monitor_name, mode.width, mode.height, mode.refresh_rate)
	}

	map_name := "default rotation"
	if len(g_map_name) > 0 {
		map_name = g_map_name
	}
	fmt.printf("  Map            : %s\n", map_name)
	fmt.println("======================================================")
}

g_map_name: string
