package main

import "core:fmt"
import glfw "vendor:glfw"
import shared "../shared"
import kproto "../krunker"

// Live map indexes refer to the complete official registry, not the native
// client's practice rotation. Sandstorm resolves through map_asset_name.
krunker_client_load_world_map :: proc(client: ^Client) -> bool {
	world := &client.krunker_world
	state := &client.krunker
	if world.map_revision == state.rendered_map_revision { return state.render_map_ready }
	state.rendered_map_revision = world.map_revision
	state.render_map_ready = false
	if world.map_index < 0 || int(world.map_index) >= len(shared.DEFAULT_MAP_NAMES) {
		krunker_ws_set_status(client, fmt.tprintf("Lobby map index %d is not available locally; see logs/krunker-network.log", world.map_index))
		return false
	}
	name := shared.DEFAULT_MAP_NAMES[world.map_index]
	kproto.network_log("world-map", fmt.tprintf("loading server map index=%d asset=%s mode=%d revision=%d", world.map_index, shared.map_asset_name(name), world.mode_index, world.map_revision))
	map_inst := shared.load_default_map(int(world.map_index))
	if map_inst == nil { krunker_ws_set_status(client, fmt.tprintf("Could not load lobby map %s; see logs/krunker-network.log", name)); return false }
	client_unload_map(client)
	client_clear_players(client)
	client_clear_impacts(client)
	clear(&state.player_revisions)
	clear(&state.player_loadout_revisions)
	krunker_client_reset_prediction(client)
	state.local_sync_revision = 0
	state.local_ammo_revision = 0
	state.local_position_revision = 0
	if client.game.maps_list_owned { delete(client.game.maps_list) }
	client.game.maps_list = make([]^shared.Map, 1)
	client.game.maps_list[0] = map_inst
	client.game.maps_list_owned = true
	client.game.map_count = 1
	if world.has_game_config { client.game.config = world.game_config }
	shared.game_init(&client.game, 0, world.mode_index, false)
	if !client.game.ready { krunker_ws_set_status(client, "Could not initialize lobby map/mode; see logs/krunker-network.log"); return false }
	client_load_current_map(client)
	client.camera.position = map_inst.camera_position
	client.game.move_lock = world.move_lock
	krunker_client_sync_match(client, glfw.GetTime())
	state.render_map_ready = true
	kproto.network_log("world-movement", fmt.tprintf("fixed=%v strafe=%.3f jump=%.3f gravity=%.3f slide_speed=%.3f delta=%.3f", client.game.config.fixed_movement, client.game.config.strafe_speed, client.game.config.jump_mlt, client.game.config.gravity_mlt, client.game.config.slide_speed, client.game.config.delta_mlt))
	kproto.network_log("world-map", fmt.tprintf("READY asset=%s objects=%d is_local=%v", shared.map_asset_name(name), len(map_inst.objects), client.game.is_local))
	return true
}

// rg changes equipment in place. player_spawn also chooses an offline spawn,
// so preserve the currently displayed coordinates and mouse look explicitly.
krunker_client_regenerate_loadout :: proc(client: ^Client, player: ^shared.Player, source: ^kproto.Krunker_World_Player) {
	position, direction := player.position, player.direction
	shared.player_spawn(player, source.class_index, source.secondary_id)
	player.position, player.direction = position, direction
	player.on_ground, player.crouch_val, player.aim_val = source.on_ground, source.crouch_val, source.aim_val
	player.swap_timer = 0
	shared.player_update_height(player)
	if player.is_you {
		clear(&client.predicted_inputs)
		client.krunker.render_sample_ready = false
		client.krunker.local_ammo_revision = source.ammo_revision
		// Keep unsent commands and their sequences: dropping them here leaves
		// a gap in q and makes the server reject otherwise valid movement.
	}
}

krunker_client_sync_world :: proc(client: ^Client) {
	world := &client.krunker_world
	state := &client.krunker
	if !world.ready || !krunker_client_load_world_map(client) do return
	client.game.move_lock = world.move_lock
	krunker_client_sync_match(client, glfw.GetTime())
	if !world.in_game && (state.spawned || client.in_game) || world.has_match && world.match.phase == .ENDED && (state.spawned || client.in_game || client.spawn_pending) {
		client.in_game, state.spawned, client.spawn_pending = false, false, false
		krunker_client_reset_prediction(client)
		if client.window != nil { glfw.SetInputMode(client.window, glfw.CURSOR, glfw.CURSOR_NORMAL) }
		client.mouse_state.locked = false
	}
	if state.player_revisions == nil { state.player_revisions = make(map[i32]u64) }
	if state.player_loadout_revisions == nil { state.player_loadout_revisions = make(map[i32]u64) }
	for &source in world.players {
		is_you := source.sid == world.local_sid
		if !source.has_position || is_you && !world.in_game && source.active do continue
		if revision, found := state.player_revisions[source.sid]; found && revision == source.revision do continue
		state.player_revisions[source.sid] = source.revision
		if source.class_index < 0 || int(source.class_index) >= len(client.game.classes) {
			kproto.network_log("world-player", fmt.tprintf("ERROR unsupported class=%d sid=%d", source.class_index, source.sid)); continue
		}
		player := client_find_player(client, source.sid)
		created := player == nil
		was_active := player != nil && player.active
		loadout_changed := !created && source.loadout_revision != state.player_loadout_revisions[source.sid]
		state.player_loadout_revisions[source.sid] = source.loadout_revision
		live_change := loadout_changed && was_active && source.active
		respawned := created || player != nil && (loadout_changed || player.class_index != source.class_index || player.secondary_id != shared.secondary_weapon_id(client.game.weapons, source.secondary_id) || !was_active && source.active)
		if created {
			player = shared.player_init(&client.game)
			if player == nil { kproto.network_log("world-player", "ERROR player allocation failed"); continue }
			player.uid = source.sid
			player.team = source.team
			player.is_you = is_you
			player.render_you = is_you
			shared.game_players_add(&client.game, player)
			shared.player_spawn(player, source.class_index, source.secondary_id)
		} else if respawned {
			if player.mesh != nil {
				scene_remove_player_mesh(player.render_you ? client.fps_scene : client.scene, cast(^Player_Mesh)player.mesh, int(player.loadout_size))
				player_meshes_fini(player)
			}
			if live_change { krunker_client_regenerate_loadout(client, player, &source) }
			else { shared.player_spawn(player, source.class_index, source.secondary_id) }
		}
		if respawned {
			// As with native snapshots, spawning projects a server-owned entity.
			// Its offline spawn/swap timer would never advance during prediction.
			player.swap_timer = 0
			if is_you && !live_change { krunker_client_reset_prediction(client); state.local_ammo_revision = 0 }
		}
		player.team = source.team
		player.active = source.active
		if !player.active && was_active && player.mesh != nil {
			scene_remove_player_mesh(player.render_you ? client.fps_scene : client.scene, cast(^Player_Mesh)player.mesh, int(player.loadout_size))
		}
		krunker_client_apply_metadata(client, player, &source)
		// Only a fresh roster or live regeneration can confirm the requested sidearm. START/SYNC
		// may arrive first and still refer to the previous life's loadout.
		if is_you && state.secondary_response_pending && source.secondary_revision > state.secondary_request_revision {
			state.secondary_response_pending = false
			if client_secondary_request(client, source.class_index) >= 0 && player.secondary_id != client_secondary_choice(client) {
				client_selection_status(client, fmt.tprintf("Server equipped %s; requested secondary was not accepted.", client.game.weapons[player.secondary_id].name))
			}
		}
		krunker_client_apply_motion(client, player, &source, respawned && !live_change)
		if is_you { krunker_client_apply_ammo(client, player, &source) }
		if player.mesh == nil && player.active {
			player_generate_meshes(player, is_you)
			if player.mesh != nil { scene_add_player_mesh(is_you ? client.fps_scene : client.scene, cast(^Player_Mesh)player.mesh, int(player.loadout_size)) }
		}
		if player.mesh != nil { player_update_meshes(player, false) }
		if is_you {
			client.me = player
			if !state.spawned && state.bootstrapped && client.spawn_pending && source.class_index == client.selected_class && (state.team == 0 || source.team == state.team) && kproto.krunker_world_can_render_local(world) {
				state.spawned = true
				client.in_game = true
				client.has_life = true
				client.spawn_pending = false
				client.lobby_team = source.team
				client.team_pending = false
				if client.menu.page == .HOME {
					glfw.SetInputMode(client.window, glfw.CURSOR, glfw.CURSOR_DISABLED)
					client.mouse_state.locked = true
					x, y := glfw.GetCursorPos(client.window)
					client.mouse_state.last_pos = {f32(x), f32(y)}
				}
				kproto.network_log("world-player", fmt.tprintf("LOCAL READY sid=%d class=%d team=%d position=%v mesh=%v", source.sid, source.class_index, source.team, source.position, player.mesh != nil))
				krunker_ws_set_status(client, "Server confirmed entry.")
			}
		}
	}
	krunker_client_present_shots(client)
	krunker_client_present_projectiles(client)
}
