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

Display_Mode :: enum {
	Windowed,
	Borderless,
	Fullscreen,
}

Display_Resolution :: struct {
	width, height: i32,
}

DISPLAY_RESOLUTIONS := [?]Display_Resolution{
	{1280, 720},
	{1600, 900},
	{1920, 1080},
	{2560, 1440},
}

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
	last_escape_key:   bool,
	last_swap_key:     u8,
	last_mouse_button: bool,
	in_game:           bool,
	spawn_pending:     bool,
	spawn_retry_timer: f32,
	selected_class:    i32,
	class_picker_open: bool,
	settings_open:     bool,
	display_mode:      Display_Mode,
	resolution_index:  i32,
	sensitivity:       f32,
	freecam_enabled:   bool,
	map_loaded:        bool,
	net:               Net_Client_State,
	net_input_seq:     i32,
	snapshot_send_rate: f32,
	predicted_inputs:  [dynamic]shared.Input,

	game: shared.Game,
	me:   ^shared.Player,
	impact_markers: [dynamic]Impact_Marker,
	tracer_markers: [dynamic]Tracer_Marker,
	show_fps:       bool,
	fps_value:      u32,
	fps_frames:     u32,
	fps_elapsed:    f32,
	viewport_width: i32,
	viewport_height: i32,
}

g_client: ^Client

MAX_PREDICTED_INPUTS :: 256

client_remember_windowed_rect :: proc(client: ^Client) {
	if client.display_mode != .Windowed || glfw.GetWindowMonitor(client.window) != nil {
		return
	}

	client.windowed_rect.x, client.windowed_rect.y = glfw.GetWindowPos(client.window)
	client.windowed_rect.width, client.windowed_rect.height = glfw.GetWindowSize(client.window)
}

client_apply_display_settings :: proc(client: ^Client) {
	monitor := glfw.GetPrimaryMonitor()
	if monitor == nil {
		return
	}

	mode := glfw.GetVideoMode(monitor)
	monitor_x, monitor_y := glfw.GetMonitorPos(monitor)
	resolution := DISPLAY_RESOLUTIONS[client.resolution_index]

	switch client.display_mode {
	case .Windowed:
		glfw.SetWindowAttrib(client.window, glfw.DECORATED, 1)
		x := monitor_x + (mode.width - resolution.width) / 2
		y := monitor_y + (mode.height - resolution.height) / 2
		glfw.SetWindowMonitor(client.window, nil, x, y, resolution.width, resolution.height, 0)
		client.windowed_rect = {x, y, resolution.width, resolution.height}
	case .Borderless:
		glfw.SetWindowMonitor(client.window, nil, monitor_x, monitor_y, mode.width, mode.height, 0)
		glfw.SetWindowAttrib(client.window, glfw.DECORATED, 0)
		glfw.SetWindowPos(client.window, monitor_x, monitor_y)
		glfw.SetWindowSize(client.window, mode.width, mode.height)
	case .Fullscreen:
		glfw.SetWindowAttrib(client.window, glfw.DECORATED, 1)
		glfw.SetWindowMonitor(client.window, monitor, 0, 0, resolution.width, resolution.height, mode.refresh_rate)
	}
}

client_set_display_mode :: proc(client: ^Client, display_mode: Display_Mode) {
	if client.display_mode == display_mode {
		return
	}

	client_remember_windowed_rect(client)
	client.display_mode = display_mode
	client_apply_display_settings(client)
}

Client_Options :: struct {
	map_name: string,
	class_name: string,
	show_help: bool,
	show_fps:  bool,
	offline:   bool,
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
	fmt.println("      --offline         Run the local authoritative simulation")
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
		case "--offline":
			options.offline = true
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

client_find_player :: proc(client: ^Client, uid: i32) -> ^shared.Player {
	for player in client.game.players {
		if player.uid == uid {
			return player
		}
	}
	return nil
}

client_clear_players :: proc(client: ^Client) {
	for player in client.game.players {
		if player.mesh != nil {
			scene_remove_player_mesh(player.render_you ? client.fps_scene : client.scene, cast(^Player_Mesh)player.mesh, int(player.loadout_size))
			player_meshes_fini(player)
		}
		shared.player_destroy(player)
	}
	clear(&client.game.players)
	client.game.player_count = 0
	client.me = nil
	client.in_game = false
	client.spawn_pending = false
	clear(&client.predicted_inputs)
}

client_discard_acked_inputs :: proc(client: ^Client, ack_seq: i32) {
	for len(client.predicted_inputs) > 0 && client.predicted_inputs[0].seq <= ack_seq {
		ordered_remove(&client.predicted_inputs, 0)
	}
}

client_apply_movement_state :: proc(player: ^shared.Player, state: ^shared.Packet_Player_State) {
	player.on_ground = state.on_ground
	player.on_ladder = state.on_ladder
	player.on_ramp = state.on_ramp
	player.on_terrain = state.on_terrain
	player.terrain_slipping = state.terrain_slipping
	player.did_jump = state.did_jump
	player.did_wall_jump = state.did_wall_jump
	player.can_slide = state.can_slide
	player.on_wall = state.on_wall
	player.crouch_val = state.crouch_val
	player.aim_val = state.aim_val
	player.slide_timer = state.slide_timer
	player.jump_timer = state.jump_timer
	shared.player_update_height(player)

	if !state.on_ramp && player.ramp_fix != nil {
		free(player.ramp_fix)
		player.ramp_fix = nil
	}
}

client_reconcile_local_player :: proc(client: ^Client, player: ^shared.Player, state: ^shared.Packet_Player_State, was_active: bool) {
	client_discard_acked_inputs(client, state.ack_seq)
	player.interpolate = false
	player.position = state.position
	player.velocity = state.velocity
	client_apply_movement_state(player, state)

	if !was_active {
		player.direction = {state.x_dir, state.y_dir}
	}

	// Reapply inputs the server had not processed when it produced this
	// snapshot. `recon=true` runs deterministic movement/collision code while
	// suppressing duplicate shots, reloads, and recoil effects.
	for &input in client.predicted_inputs {
		shared.player_proc_input(player, &input, true, client.game.move_lock)
	}
}

client_apply_match_state :: proc(client: ^Client, state: ^shared.Packet_Match_State) {
	if (!client.map_loaded || state.map_index != client.game.current_map_index) && state.map_index >= 0 && state.map_index < client.game.map_count {
		if client.map_loaded {
			client_unload_map(client)
		}
		client_clear_players(client)
		if !client.game.ready || state.map_index != client.game.current_map_index {
			shared.game_init(&client.game, state.map_index, 0, false)
		}
		client_load_current_map(client)
		fmt.printf("[Net Client] Loaded authoritative server map slot %d\n", state.map_index)
	}
	shared.packet_apply_match_state(&client.game, state)
	client.snapshot_send_rate = state.send_rate > 0 ? state.send_rate : 32
	client_reconcile_players(client, state)
}

// client_reconcile_players drops remote players the server no longer tracks.
// The server removes a player from its sim the moment the client disconnects,
// so the roster in MATCH_STATE is the source of truth; without this a departed
// player would stay frozen in the world forever.
client_reconcile_players :: proc(client: ^Client, state: ^shared.Packet_Match_State) {
	for i := len(client.game.players) - 1; i >= 0; i -= 1 {
		player := client.game.players[i]
		if player.is_you || player == client.me {
			continue
		}
		found := false
		for j in 0 ..< state.player_count {
			if state.player_ids[j] == u32(player.uid) {
				found = true
				break
			}
		}
		if found {
			continue
		}
		if player.mesh != nil {
			scene_remove_player_mesh(player.render_you ? client.fps_scene : client.scene, cast(^Player_Mesh)player.mesh, int(player.loadout_size))
			player_meshes_fini(player)
		}
		shared.player_destroy(player)
		unordered_remove(&client.game.players, i)
	}
	client.game.player_count = i32(len(client.game.players))
}

client_apply_player_state :: proc(client: ^Client, state: ^shared.Packet_Player_State) {
	if state.class_id < 0 || state.class_id >= i32(len(client.game.classes)) || state.player_id == 0 || state.team < 0 || state.team > 2 {
		fmt.eprintf("[Net Client] Rejected invalid player state id=%d class=%d team=%d\n", state.player_id, state.class_id, state.team)
		return
	}
	if state.health < 0 || state.health > f32(state.max_health) || state.max_health <= 0 || state.max_health > 10000 {
		fmt.eprintf("[Net Client] Rejected invalid health state for player %d\n", state.player_id)
		return
	}
	if state.crouch_val < 0 || state.crouch_val > 1 || state.aim_val < 0 || state.aim_val > 1 || state.slide_timer < 0 || state.jump_timer < 0 {
		fmt.eprintf("[Net Client] Rejected invalid movement state for player %d\n", state.player_id)
		return
	}

	// The server reports its snapshot cadence in MATCH_STATE. Until the first
	// one arrives (or if it is missing) fall back to the default 32 Hz rate.
	send_rate := client.snapshot_send_rate
	if send_rate <= 0 {
		send_rate = 32
	}

	player := client_find_player(client, i32(state.player_id))
	if state.is_you && client.me != nil && client.me.uid != i32(state.player_id) {
		fmt.eprintf("[Net Client] Rejected duplicate local ownership for player %d (local is %d)\n", state.player_id, client.me.uid)
		return
	}
	if !state.is_you && client.me != nil && client.me.uid == i32(state.player_id) {
		fmt.eprintf("[Net Client] Rejected ownership loss for local player %d\n", state.player_id)
		return
	}
	if player == nil {
		player = shared.player_init(&client.game)
		player.uid = i32(state.player_id)
		player.team = state.team
		shared.game_players_add(&client.game, player)
		shared.player_spawn(player, state.class_id)
		player.swap_timer = 0
		player.active = false
	}

	was_active := player.active
	previous_shot_seq := player.shot_seq
	if player.class_index != state.class_id {
		if player.mesh != nil {
			scene_remove_player_mesh(player.render_you ? client.fps_scene : client.scene, cast(^Player_Mesh)player.mesh, int(player.loadout_size))
			player_meshes_fini(player)
		}
		shared.player_spawn(player, state.class_id)
		player.swap_timer = 0
		was_active = false
	}

	player.team = state.team
	player.active = state.active
	if state.is_you {
		if state.active {
			client_reconcile_local_player(client, player, state, was_active)
		} else {
			clear(&client.predicted_inputs)
			player.interpolate = false
			player.position = state.position
			player.velocity = state.velocity
			client_apply_movement_state(player, state)
		}
	} else if was_active {
		// Interpolate from the previously displayed position toward the fresh
		// authoritative one. Between snapshots the client lerps, so a moving
		// player no longer steps/jerks and never desyncs visually.
		player.interpolate = true
		player.dt = 0
		player.send_rate = send_rate
		player.interp_pos_start = player.position
		player.interp_pos_end = state.position
		player.interp_dir_start = player.direction
		player.interp_dir_end = {state.x_dir, state.y_dir}
		player.velocity = state.velocity
		client_apply_movement_state(player, state)
	} else {
		// Fresh spawn or re-appearance: snap, then interpolate from here.
		player.position = state.position
		player.direction = {state.x_dir, state.y_dir}
		player.interpolate = true
		player.dt = 0
		player.send_rate = send_rate
		player.interp_pos_start = player.position
		player.interp_pos_end = state.position
		player.interp_dir_start = player.direction
		player.interp_dir_end = player.direction
		player.velocity = state.velocity
		client_apply_movement_state(player, state)
	}
	player.health = state.health
	player.max_health = state.max_health
	player.input_seq = state.ack_seq
	ownership_changed := player.mesh != nil && player.render_you != state.is_you
	if ownership_changed {
		scene_remove_player_mesh(player.render_you ? client.fps_scene : client.scene, cast(^Player_Mesh)player.mesh, int(player.loadout_size))
		player_meshes_fini(player)
		was_active = false
	}
	player.is_you = state.is_you
	player.render_you = state.is_you
	weapon_found := false
	for weapon_id, loadout_index in player.loadout {
		if weapon_id == i32(state.weapon_id) {
			weapon_found = true
			weapon := client.game.weapons[weapon_id]
			if state.active_ammo > weapon.ammo {
				fmt.eprintf("[Net Client] Rejected invalid ammo %d for player %d weapon %d\n", state.active_ammo, state.player_id, state.weapon_id)
				return
			}
			if player.loadout_index != i32(loadout_index) {
				shared.player_swap_weapon(player, i32(loadout_index), true, true, true)
			}
			player.ammo[loadout_index] = state.active_ammo
			break
		}
	}
	if !weapon_found {
		fmt.eprintf("[Net Client] Rejected weapon %d outside player %d loadout\n", state.weapon_id, state.player_id)
		return
	}
	new_shots: u32
	if was_active && state.active && state.shot_seq > previous_shot_seq {
		// Cap a pathological jump while still preserving the authoritative
		// sequence value, so a malformed snapshot cannot create an unbounded loop.
		new_shots = min(state.shot_seq - previous_shot_seq, u32(16))
	}
	player.shot_seq = state.shot_seq
	for _ in 0 ..< int(new_shots) {
		shared.player_apply_recoil(player)
	}

	if state.active && (!was_active || player.mesh == nil) {
		if player.mesh == nil {
			player_generate_meshes(player, state.is_you)
		}
		scene_add_player_mesh(state.is_you ? client.fps_scene : client.scene, cast(^Player_Mesh)player.mesh, int(player.loadout_size))
	} else if !state.active && was_active && player.mesh != nil {
		scene_remove_player_mesh(player.render_you ? client.fps_scene : client.scene, cast(^Player_Mesh)player.mesh, int(player.loadout_size))
	}

	if state.is_you {
		client.me = player
		if state.active {
			client.in_game = true
			client.spawn_pending = false
			client.spawn_retry_timer = 0
		}
	}
	if player.mesh != nil && player.active {
		player_update_meshes(player, false)
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
	if client.game.map_inst == nil || !client.map_loaded {
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
	client.map_loaded = false
}

client_load_current_map :: proc(client: ^Client) {
	if client.game.map_inst == nil {
		return
	}

	shared.map_load_meshes(client.game.map_inst, prefab_init_cb)
	client_load_map(client)
	client.map_loaded = true

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

client_update_objective_visuals :: proc(client: ^Client, now: f32) {
	if client.game.map_inst == nil {
		return
	}

	active := client.game.match.objective.active_object_index
	for object, index in client.game.map_inst.objects {
		if (!object.score_zone && !object.objective) || object.mesh == nil {
			continue
		}

		mesh := cast(^Mesh)object.mesh
		material := cast(^Basic_Material)mesh.material
		is_active := i32(index) == active
		mesh.visible = is_active
		if !is_active {
			continue
		}

		pulse := 0.08 * (1.0 + math.sin(now * 4.0))
		state := &client.game.match.objective
		if state.contested {
			material.color = shared.Vec4{1.0, 0.7, 0.1, 0.32 + pulse}
			material.emissive = shared.Vec4{0.3, 0.16, 0.0, 1.0}
		} else if state.owner_team == 1 {
			material.color = shared.Vec4{0.15, 0.45, 1.0, 0.30 + pulse}
			material.emissive = shared.Vec4{0.0, 0.12, 0.35, 1.0}
		} else if state.owner_team == 2 {
			material.color = shared.Vec4{1.0, 0.2, 0.2, 0.30 + pulse}
			material.emissive = shared.Vec4{0.35, 0.02, 0.02, 1.0}
		} else {
			material.color = shared.Vec4{0.75, 0.8, 0.85, 0.20 + pulse}
			material.emissive = shared.Vec4{0.08, 0.08, 0.08, 1.0}
		}
	}
}

client_update_impact_billboard :: proc(marker: ^Impact_Marker, camera: ^Camera) {
	to_camera := camera.position - marker.position
	distance := math.sqrt(to_camera.x * to_camera.x + to_camera.y * to_camera.y + to_camera.z * to_camera.z)
	if distance <= 0.0001 {
		return
	}

	facing := to_camera / distance
	depth_offset := clamp(distance * distance * 0.000001, 0.04, 0.5)
	marker.mesh.transform.position = marker.position + facing * depth_offset
	marker.mesh.transform.rotation_order = .EXTRINSIC
	// The shared plane faces +Y, so rotate +Y onto the camera direction.
	marker.mesh.transform.rotation.x = math.atan2(math.sqrt(facing.x * facing.x + facing.z * facing.z), facing.y)
	marker.mesh.transform.rotation.y = math.atan2(facing.x, facing.z)
	marker.mesh.transform.rotation.z = 0
}

client_add_tracer :: proc(client: ^Client, impact: ^shared.Bullet_Impact) {
	direction := impact.position - impact.origin
	length := math.sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
	if length <= 0.01 {
		return
	}
	direction /= length

	start_offset := min(1.2, length * 0.15)
	visible_length := length - start_offset
	if visible_length <= 0.01 {
		return
	}

	fade_time: f32 = 0.08

	material := basic_material_init()
	if material == nil {
		return
	}
	material.base.transparent = true
	material.color = shared.Vec4{1.0, 0.78, 0.20, 0.95}
	material.emissive = shared.Vec4{0.6, 0.4, 0.1, 1.0}

	mesh := mesh_init(create_cube_geo(), &material.base)
	start_position := impact.origin + direction * start_offset
	mesh.transform.position = start_position
	mesh.transform.scale = shared.Vec3{0.045, visible_length, 0.045}
	mesh.transform.rotation_order = .EXTRINSIC
	mesh.transform.rotation.x = math.atan2(math.sqrt(direction.x * direction.x + direction.z * direction.z), direction.y)
	mesh.transform.rotation.y = math.atan2(direction.x, direction.z)
	mesh.transform.rotation.z = 0

	if len(client.tracer_markers) >= 256 {
		oldest := client.tracer_markers[0]
		scene_remove_mesh(client.scene, oldest.mesh)
		mesh_fini(oldest.mesh)
		ordered_remove(&client.tracer_markers, 0)
	}

	scene_add_mesh(client.scene, mesh)
	append(&client.tracer_markers, Tracer_Marker{
		mesh = mesh,
		direction = direction,
		start_position = start_position,
		travel_distance = visible_length,
		distance = visible_length,
		segment_length = visible_length,
		speed = 0,
		lifetime = fade_time,
		total_lifetime = fade_time,
		fade_lifetime = fade_time,
	})
}

client_tick_impacts :: proc(client: ^Client, delta: f32) {
	for &impact in client.game.impacts {
		client_add_tracer(client, &impact)
		if !impact.hit {
			continue
		}

		material := basic_material_init()
		if material == nil {
			continue
		}

		material.base.transparent = true
		material.color = shared.Vec4{1.0, 1.0, 1.0, 1.0}
		material.texture = impact_texture_get()

		mesh := mesh_init(create_plane_geo(), &material.base)
		mesh.transform.position = impact.position
		mesh.transform.scale = shared.Vec3{0.32, 0.01, 0.32}

		scene_add_mesh(client.scene, mesh)
		append(&client.impact_markers, Impact_Marker{
			mesh = mesh,
			position = impact.position,
			lifetime = 8.0,
		})
	}
	clear(&client.game.impacts)

	for i := len(client.impact_markers) - 1; i >= 0; i -= 1 {
		marker := &client.impact_markers[i]
		client_update_impact_billboard(marker, &client.camera)
		marker.lifetime -= delta

		if marker.lifetime <= 0 {
			scene_remove_mesh(client.scene, marker.mesh)
			mesh_fini(marker.mesh)
			unordered_remove(&client.impact_markers, i)
		}
	}

	for i := len(client.tracer_markers) - 1; i >= 0; i -= 1 {
		tracer := &client.tracer_markers[i]
		tracer.lifetime -= delta
		material := cast(^Basic_Material)tracer.mesh.material
		material.color.w = clamp(tracer.lifetime / tracer.fade_lifetime, 0.0, 1.0) * 0.95

		if tracer.lifetime <= 0 {
			scene_remove_mesh(client.scene, tracer.mesh)
			mesh_fini(tracer.mesh)
			unordered_remove(&client.tracer_markers, i)
		}
	}
}

client_clear_impacts :: proc(client: ^Client) {
	for marker in client.impact_markers {
		scene_remove_mesh(client.scene, marker.mesh)
		mesh_fini(marker.mesh)
	}
	delete(client.impact_markers)
	for tracer in client.tracer_markers {
		scene_remove_mesh(client.scene, tracer.mesh)
		mesh_fini(tracer.mesh)
	}
	delete(client.tracer_markers)
	clear(&client.game.impacts)
}

client_update_freecam :: proc(client: ^Client, mouse_delta: shared.Vec2, delta: f32) {
	client.camera.rotation.x -= mouse_delta.y * shared.GAME_CONSTANTS.mouse_sensitivity * client.sensitivity / client.camera.zoom
	client.camera.rotation.y -= mouse_delta.x * shared.GAME_CONSTANTS.mouse_sensitivity * client.sensitivity / client.camera.zoom
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
	if !client.game.ready || client.in_game || client.spawn_pending {
		return
	}
	if client.net.connected && !client.net.match_state_received {
		return
	}

	if client.game.is_local {
		client.in_game = true
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
	} else if client.net.connected {
		client.spawn_pending = true
		client.spawn_retry_timer = 0.5
		net_client_send_spawn(&client.net, client.selected_class)
	}
}

client_tick :: proc(client: ^Client, now, delta: f32) {
	if client.net.connected {
		net_client_poll(client)
	}
	if !client.game.ready {
		return
	}

	client_update_fps(client, delta)
	if client.spawn_pending && client.net.connected {
		client.spawn_retry_timer = max(0.0, client.spawn_retry_timer - delta)
		if client.spawn_retry_timer == 0 {
			net_client_send_spawn(&client.net, client.selected_class)
			client.spawn_retry_timer = 0.5
		}
	}

	debug_key := glfw.GetKey(client.window, glfw.KEY_GRAVE_ACCENT) == glfw.PRESS
	freecam_key := glfw.GetKey(client.window, glfw.KEY_RIGHT_BRACKET) == glfw.PRESS

	if debug_key && !client.last_debug_key && !client.net.connected {
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
		client_set_display_mode(client, client.display_mode == .Windowed ? .Fullscreen : .Windowed)
	}

	client.last_fullscreen_key = fullscreen_key
	client.mouse_state.locked = glfw.GetInputMode(client.window, glfw.CURSOR) == glfw.CURSOR_DISABLED

	left_down := glfw.GetMouseButton(client.window, glfw.MOUSE_BUTTON_LEFT) == glfw.PRESS

	escape_key := glfw.GetKey(client.window, glfw.KEY_ESCAPE) == glfw.PRESS
	if !client.mouse_state.locked && escape_key && !client.last_escape_key && client.settings_open {
		client.settings_open = false
	} else if client.mouse_state.locked && escape_key {
		glfw.SetInputMode(client.window, glfw.CURSOR, glfw.CURSOR_NORMAL)
		client.mouse_state.locked = false
	} else if !client.mouse_state.locked && left_down && !client.last_mouse_button {
		clicked_ui := false

		if client.settings_open {
			clicked_ui = settings_handle_click(client, f32(x), f32(y))
		} else if client.class_picker_open {
			// Class picker screen: clicking a class selects it, clicking BACK
			// returns to the spawn screen.
			layout := class_picker_layout(client)
			for i in 0 ..< shared.class_rotation_count() {
				bx, by, bw, bh := class_button_rect(layout, i)
				if point_in_rect(f32(x), f32(y), bx, by, bw, bh) {
					client.selected_class = shared.class_rotation_id(i)
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
			// Spawn screen buttons open their respective menus; clicking anywhere
			// else starts or resumes the game.
			bx, by, bw, bh := pick_your_class_button_rect(client)
			if point_in_rect(f32(x), f32(y), bx, by, bw, bh) {
				client.class_picker_open = true
				clicked_ui = true
			} else {
				bx, by, bw, bh = settings_button_rect(client)
				if point_in_rect(f32(x), f32(y), bx, by, bw, bh) {
					client.settings_open = true
					clicked_ui = true
				}
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
	client.last_escape_key = escape_key

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

			input.x_dir -= mouse_delta.y * shared.GAME_CONSTANTS.mouse_sensitivity * client.sensitivity / client.camera.zoom
			input.y_dir -= mouse_delta.x * shared.GAME_CONSTANTS.mouse_sensitivity * client.sensitivity / client.camera.zoom

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

		input.seq = client.net_input_seq
		client.net_input_seq += 1
		if client.net.connected {
			append(&client.predicted_inputs, input)
			if len(client.predicted_inputs) > MAX_PREDICTED_INPUTS {
				ordered_remove(&client.predicted_inputs, 0)
			}
			shared.player_proc_input(client.me, &input, true, client.game.move_lock)
			net_client_send_input(&client.net, &input)
		} else {
			shared.player_queue_input(client.me, &input)
		}

	} else if !client.spawn_pending {
		// Freecam is only valid while the player is spawned.
		client.freecam_enabled = false
	}

	client.mouse_state.last_pos.x = f32(x)
	client.mouse_state.last_pos.y = f32(y)
	client.last_noclip_key = noclip_key

	if !client.net.connected {
		shared.game_tick(&client.game, now, delta)
	} else {
		// The local player is predicted above. Remote players remain one snapshot
		// behind and interpolate between authoritative samples.
		for player in client.game.players {
			if player.active {
				player.idle_anim += shared.GAME_CONSTANTS.idle_anim_speed * delta
				// player_update is not called for predicted players in net mode;
				// advance the cosmetic melee timer here so swings animate online.
				if player.melee_anim_timer > 0.0 {
					player.melee_anim_timer = max(0.0, player.melee_anim_timer - delta)
				}
				shared.player_update_recoil(player, delta)
				if player != client.me {
					shared.player_interpolate(player, delta)
				}
				if player.mesh != nil {
					player_update_meshes(player, false)
				}
			}
		}
	}
	client_update_objective_visuals(client, now)

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

		if client.me.mesh != nil && !client.net.connected {
			player_update_meshes(client.me, false)
		}
	}
	client_tick_impacts(client, delta)

	client_tick_textures(client, now)

	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
	scene_render(client.scene, &client.camera, f32(client.viewport_width), f32(client.viewport_height))

	gl.Clear(gl.DEPTH_BUFFER_BIT)
	scene_render(client.fps_scene, &client.camera, f32(client.viewport_width), f32(client.viewport_height))

	ui_update(client.ui, f32(client.viewport_width), f32(client.viewport_height))

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
	if g_client != nil {
		g_client.viewport_width = width
		g_client.viewport_height = height
	}
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
	client.display_mode = .Windowed
	client.resolution_index = 0
	client.sensitivity = 1.0

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
	client.viewport_width = 1280
	client.viewport_height = 720
	client.windowed_rect.x, client.windowed_rect.y = glfw.GetWindowPos(client.window)
	client.windowed_rect.width, client.windowed_rect.height = glfw.GetWindowSize(client.window)

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
	// Explicit map selection is a local/custom-map workflow unless a future
	// server handshake advertises that exact content.
	if !options.offline && len(options.map_name) == 0 {
		client.net, _ = net_client_connect("127.0.0.1", 21015)
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
		shared.game_configure(&client.game, &gameplay_config.game, maps, nil, gameplay_config.weapons, gameplay_config.classes)
		shared.game_init(&client.game, 0, -1, !client.net.connected)
	} else {
		shared.load_default_maps()
		shared.game_configure(&client.game, &gameplay_config.game, nil, nil, gameplay_config.weapons, gameplay_config.classes)
		shared.game_init(&client.game, client.net.connected ? 0 : -1, -1, !client.net.connected)
	}

	if client.game.ready && !client.net.connected {
		client_load_current_map(client)
	}

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
	net_client_disconnect(&client.net)
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
	delete(client.predicted_inputs)
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
