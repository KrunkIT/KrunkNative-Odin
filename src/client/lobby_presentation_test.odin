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
		menu_apply_action(&client, {kind=.SELECT_CLASS,index=4}, class_selection_test_send)
		testing.expect(t, client.menu.page == .CLASSES && client.selected_class == 0 && len(client.selection_status)>0, "restricted selections must leave the picker open")
		menu_apply_action(&client, {kind=.SELECT_CLASS,index=2}, class_selection_test_send)
		testing.expect(t, client.menu.page == .CLASSES && client.selected_class == 0 && client.krunker.class_index == 0 && client.selection_status == "Could not send class selection.",
			"failed sends must preserve the old selection and keep the picker open")
		client.krunker.q_index = 1
		menu_apply_action(&client, {kind=.SELECT_CLASS,index=2}, class_selection_test_send)
		testing.expect(t, client.menu.page == .HOME && client.menu.focus == 1234 && client.selected_class == 2 && client.krunker.class_index == 2 && len(client.selection_status)==0,
			"accepted requests must close the picker and restore its caller's focus")
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
		client.local_practice = false
		client.krunker.connected = true
		view = menu_view(&client)
		testing.expect(t, !view.classes[4].available, "returning to an online lobby must restore its class restrictions")
	}
}
