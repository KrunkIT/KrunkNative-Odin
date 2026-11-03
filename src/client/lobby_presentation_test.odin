package main

import "base:runtime"
import "core:testing"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import kproto "../krunker"
import menuui "../menu"
import shared "../shared"

when ODIN_TEST {
	@(test)
	competitive_lobby_size_reaches_both_rosters :: proc(t: ^testing.T) {
		client := Client{krunker = {connected = true}}
		defer kproto.krunker_world_reset(&client.krunker_world)
		defer { delete(menu_portraits); menu_portraits = nil }
		config := []kproto.Krunker_Msgpack_Map_Entry{{"maxPlayers", i64(10)}, {"tmSize", i64(0)}}
		packet: [18]kproto.Krunker_Msgpack_Value
		packet[0], packet[1], packet[2], packet[7], packet[16] = "init", i64(2), i64(2), config, true
		for size in 0..<4 {
			config[1].value = i64(size)
			testing.expect(t, kproto.krunker_world_apply_init(&client.krunker_world, packet[:]))
			view := menu_view(&client)
			testing.expect(t, view.presentation == .COMPETITIVE && client.krunker_world.lobby_capacity == 10)
			for team in view.teams {
				testing.expect(t, team.capacity == size+1, "1v1 through 4v4 must use tmSize, excluding spectator capacity")
			}
		}
		// Config order must not allow maxPlayers to overwrite team size.
		config[0], config[1] = {"tmSize", i64(1)}, {"maxPlayers", i64(10)}
		kproto.krunker_world_apply_init(&client.krunker_world, packet[:])
		testing.expect(t, menu_view(&client).teams[0].capacity == 2)
		// Servers without tmSize retain the total-player fallback. A new init
		// must clear the previous lobby's explicit team capacity.
		packet[7] = config[1:]
		kproto.krunker_world_apply_init(&client.krunker_world, packet[:])
		for team in menu_view(&client).teams {
			testing.expect(t, team.capacity == 5, "missing tmSize must clear stale team size and fall back to maxPlayers")
		}
		kproto.krunker_world_apply_init(&client.krunker_world, packet[:3])
		testing.expect(t, client.krunker_world.lobby_team_capacity == 0 && menu_view(&client).teams[0].capacity == 0,
			"a short init must clear both capacities")
	}

	@(test)
	lobby_presentation_follows_session_flags :: proc(t: ^testing.T) {
		client: Client
		defer kproto.krunker_world_reset(&client.krunker_world)
		client.local_practice = true
		testing.expect(t, client_lobby_presentation(&client) == .STANDARD)
		client.local_practice = false
		client.net.connected = true
		testing.expect(t, client_lobby_presentation(&client) == .COMPETITIVE)
		client.net.connected = false
		client.krunker.connected = true
		packet: [18]kproto.Krunker_Msgpack_Value
		packet[0], packet[1], packet[2] = "init", i64(2), i64(2)
		for flags in ([?][2]bool{{false,false},{true,false},{false,true},{true,true}}) {
			packet[16], packet[17] = flags[0], flags[1]
			kproto.krunker_world_apply_init(&client.krunker_world, packet[:])
			expected: menuui.Lobby_Presentation = flags[0] || flags[1] ? .COMPETITIVE : .STANDARD
			testing.expect(t, client_lobby_presentation(&client) == expected, "server flags must select the presentation")
		}
		kproto.krunker_world_apply_init(&client.krunker_world, packet[:3])
		testing.expect(t, client_lobby_presentation(&client) == .STANDARD, "a short init must clear flags from the previous lobby")
		testing.expect(t, !client.spawn_pending && !client.krunker.bootstrapped, "presentation routing must not trigger entry")
	}

	class_selection_test_send :: proc(state: ^Krunker_WS_State, opcode: string) -> bool {
		return opcode == "class" && state.q_index == 1
	}

	@(test)
	standard_class_picker_keeps_failed_requests_open :: proc(t: ^testing.T) {
		context = runtime.default_context()
		if !testing.expect(t, bool(glfw.Init())) do return
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(320, 180, "Class selection regression", nil, nil)
		if !testing.expect(t, window != nil) do return
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		client := Client{selected_class=0}
		defer {
			delete(client.selection_status)
			kproto.krunker_world_reset(&client.krunker_world)
			delete(menu_portraits); menu_portraits=nil
			resource_cache_fini()
		}
		client.game.classes = shared.CLASSES_LIST[:]
		client.game.ready = true
		client.krunker.connected = true
		client.krunker_world.ready = true
		client.krunker.render_map_ready = true
		client.menu.page = .CLASSES
		client.menu.return_focus = 1234
		client.menu.focus = 5678
		menu_apply_action(&client, {kind=.SELECT_CLASS,index=4}, class_selection_test_send)
		testing.expect(t, client.menu.page == .CLASSES && client.selected_class == 0 && len(client.selection_status)>0, "restricted selections must leave the picker open")
		menu_apply_action(&client, {kind=.SELECT_CLASS,index=2}, class_selection_test_send)
		testing.expect(t, client.menu.page == .CLASSES && client.selected_class == 0 && client.krunker.class_index == 0 && client.selection_status == "Could not send class selection.",
			"failed sends must preserve the old selection and keep the picker open")
		client.krunker.q_index = 1
		menu_apply_action(&client, {kind=.SELECT_CLASS,index=2}, class_selection_test_send)
		testing.expect(t, client.menu.page == .LOADOUT && client.menu.loadout_parent == .CLASSES && client.menu.loadout_return_focus == 5678 && client.menu.return_focus == 1234 && client.selected_class == 2 && client.krunker.class_index == 2 && len(client.selection_status)==0,
			"accepted class requests must open that class's loadout and retain the path back to its picker")
		testing.expect(t, !client.spawn_pending && !client.team_pending && !client.krunker_world.in_game, "class selection must not spawn or change teams")
		view := menu_view(&client)
		testing.expect(t, view.presentation == .STANDARD && len(menuui.play_reason(view)) == 0, "an automatic-team lobby must allow entry without a manual team")
		client.krunker_world.lobby_select_team = true
		view = menu_view(&client)
		testing.expect(t, view.team_selection && menuui.play_reason(view) == "Choose a team to enter game", "manual teams still require a confirmed team")
		client.lobby_team = 1
		view = menu_view(&client)
		testing.expect(t, len(menuui.play_reason(view)) == 0)
		client.local_practice = true
		client.krunker.connected = false
		view = menu_view(&client)
		testing.expect(t, view.presentation == .STANDARD && view.team_selection)
		for class in view.classes {
			testing.expect(t, class.available && len(class.reason)==0, "Local practice must allow every class")
			menu_apply_action(&client, {kind=.SELECT_CLASS,index=class.id}, class_selection_test_send)
			testing.expect(t, client.selected_class == class.id && len(client.selection_status)==0, "every practice class must be selectable")
		}
		client.menu.page = .HOME
		client.menu.focus = 2468
		menu_apply_action(&client, {kind=.SELECT_CLASS,index=0}, class_selection_test_send)
		testing.expect(t, client.menu.page == .LOADOUT && client.menu.loadout_parent == .HOME && client.menu.return_focus == 2468 && client.menu.loadout_return_focus == 2468,
			"choosing a competitive class tile must also open its loadout and preserve lobby focus")
		client.local_practice = false
		client.krunker.connected = true
		view = menu_view(&client)
		testing.expect(t, !view.classes[4].available, "returning to an online lobby must restore its class restrictions")
		// A custom comp ruleset must replace the built-in rotation, including
		// classes that the default competitive list excludes.
		allowed := []kproto.Krunker_Msgpack_Value{i64(4), i64(2), i64(999), i64(-1)}
		config := []kproto.Krunker_Msgpack_Map_Entry{{"classes", allowed}}
		packet: [18]kproto.Krunker_Msgpack_Value
		packet[0], packet[1], packet[2], packet[7], packet[16] = "init", i64(2), i64(4), config, true
		kproto.krunker_world_apply_init(&client.krunker_world, packet[:])
		view = menu_view(&client)
		visible := menuui.visible_classes(view)
		testing.expect(t, client.krunker_world.has_allowed_classes && !view.classes[0].available && view.classes[4].available &&
			len(visible) == 2 && visible[0].id == 2 && visible[1].id == 4, "competitive selection must follow the server's allowed IDs and retain their stable action IDs")
		view.classes[2].used, view.classes[2].limit = 1, 1
		visible = menuui.visible_classes(view)
		testing.expect(t, len(visible) == 2 && !menuui.class_selectable(view, visible[0]), "an allowed class at capacity stays visible with its restriction")
		client.local_practice = true
		view = menu_view(&client)
		testing.expect(t, len(menuui.visible_classes(view)) == len(shared.CLASSES_LIST), "practice must keep access to every class")
		client.local_practice = false
		config[0].value = allowed[:0]
		kproto.krunker_world_apply_init(&client.krunker_world, packet[:])
		testing.expect(t, len(menuui.visible_classes(menu_view(&client))) == 0, "an explicit empty allowed list must not enable default classes")
		kproto.krunker_world_apply_init(&client.krunker_world, packet[:3])
		view = menu_view(&client)
		testing.expect(t, !client.krunker_world.has_allowed_classes && !view.classes[4].available && view.classes[0].available,
			"a new lobby without an allowed list must clear previous restrictions and restore the fallback")
		// Actual comp configuration can list EVERY class, while classLimN=0
		// removes most of them. This reproduced the user's full-strip screenshot.
		all_classes: [len(shared.CLASSES_LIST)]kproto.Krunker_Msgpack_Value
		for &value, i in all_classes { value = i64(i) }
		limits := []kproto.Krunker_Msgpack_Map_Entry{
			{"classLim2", i64(1)}, {"classes", all_classes[:]}, {"classLim0", i64(1)}, {"limitClasses", true}, {"classLim4", i64(0)}, {"classLim999", i64(2)},
		}
		packet[7] = limits
		kproto.krunker_world_apply_init(&client.krunker_world, packet[:])
		gameplay_packet(&client.krunker_world, "uid", "you")
		roster := []kproto.Krunker_Msgpack_Map_Entry{
			{"you", []kproto.Krunker_Msgpack_Map_Entry{{"a", true}, {"t", i64(1)}, {"c", i64(0)}}},
			{"teammate", []kproto.Krunker_Msgpack_Map_Entry{{"a", true}, {"t", i64(1)}, {"c", i64(2)}}},
			{"opponent", []kproto.Krunker_Msgpack_Map_Entry{{"a", true}, {"t", i64(2)}, {"c", i64(2)}}},
			{"spectator", []kproto.Krunker_Msgpack_Map_Entry{{"a", false}, {"t", i64(1)}, {"c", i64(2)}}},
		}
		gameplay_packet(&client.krunker_world, "cd", roster)
		client.lobby_team = 1
		view = menu_view(&client)
		visible = menuui.visible_classes(view)
		testing.expect(t, len(visible) == 2 && visible[0].id == 0 && visible[1].id == 2 && !view.classes[4].available,
			"zero-limit classes must be hidden even when the server's general allowed list contains them")
		testing.expect(t, view.classes[0].limit == 1 && view.classes[0].used == 1 && menuui.class_selectable(view, view.classes[0]),
			"the current player's assigned class must remain selectable at its limit")
		testing.expect(t, view.classes[2].limit == 1 && view.classes[2].used == 1 && !menuui.class_selectable(view, view.classes[2]),
			"class occupancy must count active teammates, excluding opponents and spectators")
		limits[3].value = false
		kproto.krunker_world_apply_init(&client.krunker_world, packet[:])
		view = menu_view(&client)
		testing.expect(t, len(menuui.visible_classes(view)) == len(all_classes) && view.classes[2].limit == 0,
			"classLimN must have no effect when limitClasses is disabled")
		limits[3].value = true
		kproto.krunker_world_apply_init(&client.krunker_world, packet[:])
		client.local_practice = true
		view = menu_view(&client)
		testing.expect(t, len(menuui.visible_classes(view)) == len(all_classes) && view.classes[2].limit == 0)
		client.local_practice = false
		kproto.krunker_world_apply_init(&client.krunker_world, packet[:3])
		testing.expect(t, !client.krunker_world.limit_classes && client.krunker_world.class_limits == [len(shared.CLASSES_LIST)]i32{},
			"moving to a new lobby must clear class limits")
	}
}
