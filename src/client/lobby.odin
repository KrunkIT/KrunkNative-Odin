package main

import "core:fmt"
import "core:math"
import "core:strings"
import "core:encoding/json"
import glfw "vendor:glfw"
import shared "../shared"
import menuui "../menu"
import clay "../third_party/clay"
import kproto "../krunker"

menu_portraits: map[i32]u32

menu_character :: proc "c" (window: glfw.WindowHandle, codepoint: rune) {
	if g_client == nil || g_client.mouse_state.locked || codepoint < 32 || codepoint >= 127 { return }
	client := g_client
	if client.menu_text_length < len(client.menu_text) {
		client.menu_text[client.menu_text_length] = u8(codepoint)
		client.menu_text_length += 1
	}
}

client_selection_status :: proc(client: ^Client, value: string) {
	delete(client.selection_status)
	client.selection_status = kproto.network_log_safe(value)
}

client_leave_session :: proc(client: ^Client, reset_map: bool = true) {
	client_access_cancel(client)
	client.access.retried = false
	audio_stop_all(client.audio)
	if client.audio != nil { client.audio.hit_revision = 0 }
	net_client_disconnect(&client.net)
	krunker_ws_disconnect(&client.krunker)
	kproto.krunker_world_reset(&client.krunker_world)
	client_clear_players(client)
	client.lobby_team = 0
	client.requested_team = 0
	client.team_pending = false
	client.local_practice = false
	client.has_life = false
	client.join_queued = 0
	client_selection_status(client, "")
	glfw.SetInputMode(client.window, glfw.CURSOR, glfw.CURSOR_NORMAL)
	client.mouse_state.locked = false
	if reset_map {
		client_unload_map(client)
		shared.game_init(&client.game, 0, -1, true)
		client_load_current_map(client)
	}
}

client_lobby_tick :: proc(client: ^Client) {
	if client.me != nil && !client.me.active && client.in_game {
		client.in_game = false
		client.krunker.spawned = false
		glfw.SetInputMode(client.window, glfw.CURSOR, glfw.CURSOR_NORMAL)
		client.mouse_state.locked = false
	}
	if client.krunker.connected {
		for player in client.krunker_world.lobby_players {
			if player.id == client.krunker_world.local_connection_uid {
				client.lobby_team = player.team
				if client.team_pending && player.team == client.requested_team {
					client.team_pending = false
					client_selection_status(client, "Team confirmed by server.")
				}
			}
		}
		for player in client.krunker_world.players {
			if player.sid == client.krunker_world.local_sid && len(client.krunker_world.lobby_players) == 0 {
				client.lobby_team = player.team
				if client.team_pending && player.team == client.requested_team {
					client.team_pending = false
					client_selection_status(client, "Team confirmed by server.")
				}
			}
		}
	}
	if client.team_pending && glfw.GetTime() - client.team_request_time > 12 && !client.spawn_pending {
		client.team_pending = false
		client.requested_team = client.lobby_team
		client_selection_status(client, "Team change was not confirmed. Try again.")
	}
	if client.spawn_pending && client.krunker.connected && glfw.GetTime() - client.team_request_time > 20 {
		client.spawn_pending = false
		client.team_pending = false
		client_selection_status(client, "Entry was not confirmed. Check your team and try again.")
	}
	if !client.net.connected && !client.krunker.connected && !client.game.is_local {
		client.spawn_pending = false
		client.team_pending = false
		client.in_game = false
		if client.mouse_state.locked {
			glfw.SetInputMode(client.window, glfw.CURSOR, glfw.CURSOR_NORMAL)
			client.mouse_state.locked = false
		}
	}
}

menu_class_name :: proc(client: ^Client, id: i32) -> string {
	if id >= 0 && int(id) < len(client.game.classes) { return client.game.classes[id].name }
	return "Choosing class"
}

client_secondary_choice :: proc(client: ^Client) -> i32 {
	return shared.secondary_weapon_id(client.game.weapons, client.selected_secondary)
}

client_secondary_request :: proc(client: ^Client, class_id: i32) -> i32 {
	if client.game.config.no_secondaries || client.krunker.connected && client.krunker_world.has_game_config && client.krunker_world.game_config.no_secondaries { return -1 }
	if class_id < 0 || int(class_id) >= len(client.game.classes) || !client.game.classes[class_id].secondary { return -1 }
	return client_secondary_choice(client)
}

client_secondary_reason :: proc(client: ^Client) -> string {
	if client.game.config.no_secondaries || client.krunker.connected && client.krunker_world.has_game_config && client.krunker_world.game_config.no_secondaries { return "Secondaries are disabled in this lobby" }
	if client.selected_class < 0 || int(client.selected_class) >= len(client.game.classes) || !client.game.classes[client.selected_class].secondary { return "This class has no secondary weapon" }
	return ""
}

menu_weapon_icon :: proc(client: ^Client, id: i32) -> rawptr {
	if id < 0 || int(id) >= len(client.game.weapons) || client.game.weapons[id] == nil { return nil }
	texture := menu_portraits[-id-1]
	if texture == 0 && client.ui != nil {
		weapon := client.game.weapons[id]
		folder := weapon.melee ? "melee" : "weapons"
		path := shared.concat(shared.assets_path(), fmt.tprintf("textures/%s/%s.png", folder, weapon.icon))
		texture = load_texture(path); delete(path)
		menu_portraits[-id-1] = texture
	}
	return rawptr(uintptr(texture))
}

menu_view :: proc(client: ^Client) -> menuui.View {
	classes := make([]menuui.Class, len(client.game.classes), context.temp_allocator)
	if menu_portraits == nil { menu_portraits = make(map[i32]u32) }
	secondaries := make([dynamic]menuui.Secondary, context.temp_allocator)
	secondary_id := client_secondary_choice(client)
	secondary_name := "None"
	for weapon, id in client.game.weapons {
		if weapon == nil || !weapon.secondary || weapon.melee { continue }
		append(&secondaries, menuui.Secondary{id = i32(id), name = weapon.name, icon = menu_weapon_icon(client, i32(id))})
		if i32(id) == secondary_id { secondary_name = weapon.name }
	}
	secondary_reason := client_secondary_reason(client)
	if len(secondary_reason) > 0 { secondary_name = "None" }
	secondary_pending := false
	if client.me != nil && client.me.active && len(secondary_reason) == 0 {
		secondary_pending = true
		for id in client.me.loadout { if id == secondary_id { secondary_pending = false } }
	}
	for class, i in client.game.classes {
		weapon := "Melee"
		weapon_icon: rawptr
		if len(class.loadout) > 0 {
			id := class.loadout[0]
			if id >= 0 && int(id) < len(client.game.weapons) && client.game.weapons[id] != nil {
				weapon = client.game.weapons[id].name
				weapon_icon = menu_weapon_icon(client, id)
			}
		}
		texture, cached := menu_portraits[class.icon_index]
		if !cached {
			path := shared.concat(shared.assets_path(), fmt.tprintf("textures/classes/icon_%d.png", class.icon_index))
			texture = load_texture(path)
			delete(path)
			menu_portraits[class.icon_index] = texture
		}
		available := client.local_practice || shared.class_is_in_rotation(i32(i))
		if client.krunker.connected && !client.local_practice && client.krunker_world.has_allowed_classes {
			available = i < len(client.krunker_world.allowed_classes) && client.krunker_world.allowed_classes[i]
		}
		classes[i] = {id = i32(i), name = class.name, weapon = weapon, health = class.health, wall_jump = class.wall_jump, available = available, portrait = rawptr(uintptr(texture)), weapon_icon = weapon_icon}
		if !classes[i].available { classes[i].reason = "Outside this lobby's class rotation" }
		if client.krunker.connected && !client.local_practice && client.krunker_world.limit_classes {
			// In the browser's comp selector, a zero classLimN excludes the
			// class even when it appears in the general `classes` array.
			classes[i].limit = int(client.krunker_world.class_limits[i])
			if classes[i].limit == 0 { classes[i].available = false; classes[i].reason = "Disabled by lobby class limits" }
			if client.lobby_team > 0 {
				if len(client.krunker_world.lobby_players) > 0 {
					for player in client.krunker_world.lobby_players {
						if player.active && player.team == client.lobby_team && player.class_index == i32(i) { classes[i].used += 1 }
					}
				} else {
					for player in client.krunker_world.players {
						if player.active && player.team == client.lobby_team && player.class_index == i32(i) { classes[i].used += 1 }
					}
				}
			}
		}
	}
	players := make([dynamic]menuui.Player, 0, len(client.game.players), context.temp_allocator)
	confirmed_class: i32 = -1
	if client.krunker.connected {
		for player in client.krunker_world.players {
			is_you := player.sid == client.krunker_world.local_sid
			if is_you { confirmed_class = player.class_index }
			append(&players, menuui.Player{name = len(player.name) > 0 ? player.name : fmt.tprintf("Player %d", player.sid), class_name = menu_class_name(client, player.class_index), team = player.team, is_you = is_you})
		}
	} else {
		for player in client.game.players {
			if player.is_you { confirmed_class = player.class_index }
			append(&players, menuui.Player{name = player.is_you ? "You" : fmt.tprintf("Player %d", player.uid), class_name = menu_class_name(client, player.class_index), team = player.team, is_you = player.is_you})
		}
	}
	if client.local_practice && client.me == nil && client.lobby_team > 0 {
		append(&players, menuui.Player{name = "You", class_name = "Choosing class", team = client.lobby_team, is_you = true})
	}
	map_name := g_map_name
	if len(map_name) == 0 { map_name = "Current map" }
	if client.game.map_inst != nil {
		if root, ok := client.game.map_inst.raw_data.(json.Object); ok {
			if name, valid := root["name"].(json.String); valid { map_name = string(name) }
		}
	}
	mode := "Hardpoint"
	if client.game.mode != nil && !client.game.mode.config.teams { mode = "Free for all" }
	capacity := int((client.game.config.max_players + 1) / 2)
	team_names := [2]string{"Alpha", "Bravo"}
	if client.game.config.team1_name != "Team 1" && len(client.game.config.team1_name) > 0 { team_names[0] = client.game.config.team1_name }
	if client.game.config.team2_name != "Team 2" && len(client.game.config.team2_name) > 0 { team_names[1] = client.game.config.team2_name }
	online := client.krunker.connected || client.net.connected
	team_selection := (client.local_practice || client.krunker.connected && client.krunker_world.lobby_select_team) && (client.game.mode == nil || client.game.mode.config.teams)
	if client.krunker.connected {
		capacity = int((client.krunker_world.lobby_capacity+1)/2)
		if client.krunker_world.lobby_team_capacity > 0 { capacity = int(client.krunker_world.lobby_team_capacity) }
		for name, i in client.krunker_world.lobby_team_names { if len(name)>0 { team_names[i]=name } }
	}
	if client.net.connected { team_selection = client.net.lobby_received && client.net.lobby.select_team; capacity = int(client.net.lobby.capacity); team_names = client.net.lobby.team_names }
	resolution_options := make([]string, len(DISPLAY_RESOLUTIONS), context.temp_allocator)
	for resolution, i in DISPLAY_RESOLUTIONS { resolution_options[i] = fmt.tprintf("%d x %d", resolution.width, resolution.height) }
	window_resolution := client_window_resolution(client)
	monitor_names := make([dynamic]string, context.temp_allocator)
	if client.window != nil {
		for monitor, i in glfw.GetMonitors() { append(&monitor_names, fmt.tprintf("%d: %s", i+1, glfw.GetMonitorName(monitor))) }
	}
	view := menuui.View{
		live_class_changes = krunker_client_live_class_window(client, glfw.GetTime()),
		presentation = client_lobby_presentation(client), ranked = client.krunker.connected && client.krunker_world.is_ranked,
		team_selection = team_selection,
		classes = classes, selected_class = client.selected_class, confirmed_class = confirmed_class,
		secondaries = secondaries[:], selected_secondary = secondary_id, secondary_name = secondary_name, secondary_reason = secondary_reason, secondary_pending = secondary_pending,
		confirmed_team = client.lobby_team, requested_team = client.requested_team, team_pending = client.team_pending,
		players = players[:], online = online, local_practice = client.local_practice,
		active = (online || client.local_practice) && client.me != nil && client.me.active, class_pending = client.spawn_pending && confirmed_class != client.selected_class, has_life = client.has_life,
		spawn_pending = client.spawn_pending, ready = client.krunker.connected ? client.krunker_world.ready && client.krunker.render_map_ready : client.game.ready && (!client.net.connected || client.net.match_state_received),
		map_name = map_name, mode = mode, lobby_name = online ? (len(client.join_link.game_id) > 0 ? client.join_link.game_id : client.join_link.host) : "Local practice",
		browser_access_supported = ODIN_OS == .Windows, auth_pending = client.access.status == .PENDING,
		connecting = client.join_queued > 0 || client.access.status == .PENDING && client.access.join_after_access, current_invite = client.join_link.raw, join_status = client.join_status, selection_status = client.selection_status,
		fov = client.camera.fov * 180 / math.PI, display_mode = i32(client.display_mode), sensitivity = client.sensitivity, mouse_dpi = client.mouse_dpi, show_fps = client.show_fps,
		ads_sensitivity = client.ads_sensitivity, advanced_sensitivity = client.advanced_sensitivity, invert_mouse = client.invert_mouse,
		resolution_index = client.resolution_index, resolution_options = resolution_options,
		monitor_index = client.monitor_index, monitor_names = monitor_names[:], vsync = client.vsync, bindings = client.bindings, hud = client.hud_settings,
		visuals = client.visual_settings, quality = client_supported_quality(client.quality_settings, client.max_anisotropy), max_anisotropy = client.max_anisotropy,
		audio_volumes = {client.audio_settings.master, client.audio_settings.effects, client.audio_settings.footsteps, client.audio_settings.ui},
		resolution = fmt.tprintf("%d x %d", window_resolution.width, window_resolution.height),
		match_status = client.game.move_lock ? "Waiting for match to start" : "Match in progress",
		respawn_remaining = krunker_client_respawn_remaining(client, glfw.GetTime()),
	}
	if !online && !client.local_practice { view.ready = false }
	if team_selection && client.lobby_team == 0 && !(client.team_pending && client.requested_team > 0) { view.play_reason = "Choose a team to enter game" }
	if client.team_pending && client.requested_team == 0 { view.play_reason = "Leaving team..." }
	if reason := krunker_client_match_reason(client); len(reason) > 0 { view.play_reason, view.match_status = reason, reason }
	else if countdown := krunker_client_countdown_label(client, glfw.GetTime()); len(countdown) > 0 {
		view.match_status = countdown
	}
	for i in 0..<2 {
		view.teams[i] = {id = i32(i+1), name = team_names[i], capacity = capacity, available = team_selection, score = client.game.match.team_scores[i+1]}
		if !team_selection { view.teams[i].reason = "Server assigns teams automatically" }
	}
	if client.krunker.connected && len(client.krunker_world.lobby_players) > 0 {
		view.players = make([]menuui.Player, len(client.krunker_world.lobby_players), context.temp_allocator)
		for player, i in client.krunker_world.lobby_players {
			is_you := player.id == client.krunker_world.local_connection_uid
			if is_you && !view.active { view.confirmed_class = player.class_index }
			view.players[i] = {name = len(player.name)>0 ? player.name : (is_you ? "You" : "Player"), class_name = menu_class_name(client, player.class_index), team = player.team, is_you = is_you}
		}
	}
	if client.net.connected && client.net.lobby_received {
		view.players = make([]menuui.Player, client.net.lobby.count, context.temp_allocator)
		for record, i in client.net.lobby.players[:client.net.lobby.count] {
			view.players[i] = {name = record.id == client.net.lobby.local_id ? "You" : fmt.tprintf("Player %d", record.id), class_name = menu_class_name(client, record.class_id), team = record.team, is_you = record.id == client.net.lobby.local_id}
		}
	}
	view.class_pending = view.confirmed_class != view.selected_class && (view.spawn_pending || view.active && view.live_class_changes)
	return view
}

client_lobby_presentation :: proc(client: ^Client) -> menuui.Lobby_Presentation {
	if client.krunker.connected {
		return client.krunker_world.is_comp || client.krunker_world.is_ranked ? .COMPETITIVE : .STANDARD
	}
	// The native dedicated server currently hosts competitive Hardpoint.
	return client.net.connected ? .COMPETITIVE : .STANDARD
}

menu_apply_action :: proc(client: ^Client, action: menuui.Action, send_class: proc(^Krunker_WS_State, string) -> bool = krunker_ws_send) {
	if action.kind != .NONE && action.kind != .EDIT_INVITE && action.kind != .INSPECT_CLASS && action.kind != .AUDIO_VOLUME && action.kind != .SENSITIVITY {
		audio_play_effect(client.audio, "tick_0", .UI, 0.6)
	}
	switch action.kind {
	case .NONE, .EDIT_INVITE, .INSPECT_CLASS, .SETTINGS_TAB, .SETTINGS_CANCEL, .BIND_KEY, .HUD_TOGGLE, .VSYNC, .MONITOR, .SETTINGS_DROPDOWN, .RESOLUTION_SELECT, .VISUAL_VALUE, .VISUAL_RESET, .TEXTURE_FILTER, .ANISOTROPY, .SETTINGS_NUMBER, .FOV, .ADVANCED_SENSITIVITY, .INVERT_MOUSE:
	case .SETTINGS_SAVE:
		values := client.menu.settings_draft
		mode := Display_Mode(clamp(values.display_mode, 0, 2))
		resolution := clamp(values.resolution_index, 0, i32(len(DISPLAY_RESOLUTIONS))-1)
		if client.display_mode != mode || client.resolution_index != resolution || client.monitor_index != values.monitor_index || mode == .Windowed && client.menu.settings_resolution_selected {
			client_remember_windowed_rect(client)
			client.display_mode, client.resolution_index = mode, resolution
			client.monitor_index = values.monitor_index
			client_apply_display_settings(client)
		}
		client.mouse_dpi = menuui.mouse_dpi_validate(values.mouse_dpi)
		client.sensitivity = menuui.sensitivity_validate(values.sensitivity, client.mouse_dpi)
		client.ads_sensitivity = menuui.ads_sensitivity_validate(values.ads_sensitivity, client.sensitivity, client.mouse_dpi)
		client.advanced_sensitivity, client.invert_mouse = values.advanced_sensitivity, values.invert_mouse
		client.camera.fov = menuui.fov_validate(values.fov) * math.PI / 180
		client.show_fps = values.show_fps
		client.bindings, client.hud_settings = values.bindings, values.hud
		client.visual_settings, client.quality_settings = menuui.visual_settings_validate(values.visuals), menuui.quality_settings_validate(values.quality)
		client.last_swap_key = 0
		if client.vsync != values.vsync {
			client.vsync = values.vsync
			if client.window != nil { glfw.SwapInterval(client.vsync ? 1 : 0) }
		}
		client.settings_dirty = true
		settings := audio_settings_clamp({values.audio_volumes[0], values.audio_volumes[1], values.audio_volumes[2], values.audio_volumes[3]})
		if client.audio_settings != settings {
			client.audio_settings = settings
			audio_set_settings(client.audio, settings)
			client.audio_settings_dirty, client.audio_save_delay = true, 0.5
		}
	case .PASTE:
		menuui.set_invite(&client.menu, glfw.GetClipboardString(client.window))
		client.menu.focus = clay.ID("Invite").id
	case .JOIN_LINK:
		if client.join_queued > 0 || client.access.status == .PENDING { return }
		client.join_queued = 2
		krunker_ws_set_status(client, "Connecting to lobby...")
		client.menu.page = .HOME
	case .LOGIN:
		when ODIN_OS == .Windows { client_access_login(client) }
	case .CANCEL_JOIN:
		login := client.access.status == .PENDING && !client.access.join_after_access
		client_access_cancel(client)
		client.join_queued = 0
		krunker_ws_set_status(client, login ? "Login cancelled." : "Join cancelled.")
	case .FORGET_BROWSER_SESSION:
		client_access_forget(client)
	case .COPY_INVITE:
		value := strings.clone_to_cstring(client.join_link.raw)
		glfw.SetClipboardString(client.window, value)
		delete(value)
		krunker_ws_set_status(client, "Invite copied.")
	case .LEAVE_SESSION:
		client_leave_session(client)
		client.menu.page = .HOME
		krunker_ws_set_status(client, "Left session.")
	case .LOCAL_PRACTICE:
		client_leave_session(client)
		client.local_practice = true
	case .PLAY:
		view := menu_view(client)
		if len(menuui.play_reason(view)) > 0 { return }
		if (client.krunker.connected || client.net.connected) && !view.active {
			client.team_request_time = glfw.GetTime()
			client_enter_game(client)
			return
		}
		glfw.SetInputMode(client.window, glfw.CURSOR, glfw.CURSOR_DISABLED)
		client.mouse_state.locked = true
		x, y := glfw.GetCursorPos(client.window)
		client.mouse_state.last_pos = {f32(x), f32(y)}
	case .SELECT_TEAM:
		view := menu_view(client)
		if client.team_pending || action.index < 0 || action.index > 2 { return }
		team := action.index == 0 ? client.lobby_team : action.index
		if team <= 0 || !view.teams[team-1].available { return }
		client.requested_team = action.index
		client.team_request_time = glfw.GetTime()
		client_selection_status(client, "")
		if client.local_practice {
			client.lobby_team = action.index
			if client.me != nil {
				if client.me.mesh != nil { scene_remove_player_mesh(client.fps_scene, cast(^Player_Mesh)client.me.mesh, int(client.me.loadout_size)) }
				client.me.team = action.index; client.me.active = false; client.in_game = false
			}
		} else if client.krunker.connected {
			client.krunker.team = action.index
			client.team_pending = true
			if !krunker_ws_send(&client.krunker, "team") { client.team_pending = false; client_selection_status(client, "Could not send team request.") }
		} else if client.net.connected {
			client.team_pending = net_client_send_team(&client.net, action.index)
		}
	case .SELECT_CLASS:
		view := menu_view(client)
		for class in view.classes {
			if class.id != action.index { continue }
			if !menuui.class_selectable(view, class) { client_selection_status(client, len(class.reason)>0 ? class.reason : "Class limit reached. Choose another class."); return }
			if client.krunker.connected {
				previous_class := client.krunker.class_index
				previous_secondary := client.krunker.secondary_index
				client.krunker.class_index = action.index
				client.krunker.secondary_index = client_secondary_request(client, action.index)
				if !send_class(&client.krunker, "class") {
					client.krunker.class_index = previous_class
					client.krunker.secondary_index = previous_secondary
					client_selection_status(client, "Could not send class selection.")
					return
				}
			}
			client.selected_class = action.index
			client_selection_status(client, "")
			if client.menu.page != .LOADOUT {
				client.menu.loadout_parent = client.menu.page
				client.menu.loadout_return_focus = client.menu.focus
				if client.menu.page == .HOME { client.menu.return_focus = client.menu.focus }
			}
			client.menu.page = .LOADOUT
			client.menu.focus = clay.ID("LoadoutDone", u32(menuui.Page.HOME)).id
			return
		}
	case .SELECT_SECONDARY:
		if len(client_secondary_reason(client)) > 0 { client_selection_status(client, client_secondary_reason(client)); return }
		if shared.secondary_weapon_id(client.game.weapons, action.index) != action.index { return }
		if client.krunker.connected {
			previous_class, previous_secondary := client.krunker.class_index, client.krunker.secondary_index
			client.krunker.class_index, client.krunker.secondary_index = client.selected_class, action.index
			if !send_class(&client.krunker, "class") {
				client.krunker.class_index, client.krunker.secondary_index = previous_class, previous_secondary
				client_selection_status(client, "Could not send secondary selection.")
				return
			}
		}
		client.selected_secondary = action.index
		// Preserve the current life; offline automatic respawns use this preference.
		if client.local_practice && client.me != nil { client.me.secondary_id = action.index }
		client_selection_status(client, "")
	case .QUIT: glfw.SetWindowShouldClose(client.window, true)
	case .DISPLAY_MODE: client_set_display_mode(client, Display_Mode(action.index))
	case .RESOLUTION:
		client.resolution_index = (client.resolution_index + action.index + i32(len(DISPLAY_RESOLUTIONS))) % i32(len(DISPLAY_RESOLUTIONS))
		client_apply_display_settings(client)
	case .SENSITIVITY: client.sensitivity = menuui.sensitivity_validate(action.value, client.mouse_dpi)
	case .AUDIO_VOLUME:
		switch action.index {
		case 0: client.audio_settings.master = action.value
		case 1: client.audio_settings.effects = action.value
		case 2: client.audio_settings.footsteps = action.value
		case 3: client.audio_settings.ui = action.value
		case: return
		}
		client.audio_settings = audio_settings_clamp(client.audio_settings)
		audio_set_settings(client.audio, client.audio_settings)
		client.audio_settings_dirty, client.audio_save_delay = true, 0.5
	case .FPS: client.show_fps = !client.show_fps
	}
}
