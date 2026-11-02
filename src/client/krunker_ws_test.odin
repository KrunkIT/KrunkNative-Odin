package main

import "core:strings"
import "core:testing"
import kproto "../krunker"
import shared "../shared"
import menuui "../menu"
import glfw "vendor:glfw"

when ODIN_TEST {
	entry_test_send :: proc(state: ^Krunker_WS_State, opcode: string) -> bool {
		expected := [?]string{"po", "class", "en"}
		if state.q_index >= len(expected) || opcode != expected[state.q_index] { return false }
		state.q_index += 1
		return true
	}

	@(test)
	krunker_entry_has_no_artificial_wait :: proc(t: ^testing.T) {
		client: Client
		defer delete(client.join_status)
		client.krunker.connected = true
		client.krunker.got_load = true
		client.krunker.ready_received = true
		client.spawn_pending = true
		krunker_ws_bootstrap_tick(&client, entry_test_send)
		testing.expect(t, client.krunker.connected && client.krunker.bootstrapped && client.krunker.q_index == 3,
			"one tick must send class then one entry request and finish setup before server start")
		testing.expect(t, client.spawn_pending && !client.krunker.spawned, "entry must still await server spawn confirmation")
		krunker_ws_bootstrap_tick(&client, entry_test_send)
		testing.expect(t, client.krunker.q_index == 3, "finished setup must not issue another entry request")
	}

	@(test)
	krunker_lobby_confirms_connection_uid :: proc(t: ^testing.T) {
		if !testing.expect(t, bool(glfw.Init())) do return
		defer glfw.Terminate()
		client: Client
		defer kproto.krunker_world_reset(&client.krunker_world)
		defer delete(client.selection_status)
		client.krunker.connected = true
		client.krunker_world.local_sid = -1
		client.requested_team = 2
		client.team_pending = true
		client.team_request_time = glfw.GetTime()
		world := &client.krunker_world
		kproto.krunker_world_apply_packet(world, []kproto.Krunker_Msgpack_Value{"uid", "connection-uid"})
		kproto.krunker_world_apply_packet(world, []kproto.Krunker_Msgpack_Value{"io-init", "different-socket-id"})
		other := []kproto.Krunker_Msgpack_Map_Entry{{key="t",value=i64(2)},{key="a",value=true}}
		kproto.krunker_world_apply_packet(world, []kproto.Krunker_Msgpack_Value{"cda", "other-uid", other})
		client_lobby_tick(&client)
		testing.expect(t, client.team_pending && client.lobby_team == 0, "another player's assignment must not confirm our request")
		kproto.krunker_world_apply_packet(world, []kproto.Krunker_Msgpack_Value{"cda", "connection-uid", other})
		client_lobby_tick(&client)
		testing.expect(t, !client.team_pending && client.lobby_team == 2, "server roster must confirm the connection UID despite a different socket ID")
		testing.expect(t, !client.spawn_pending, "confirmation must leave entry under user control")
		client.game.ready = true
		client.selected_class = 5
		client_enter_game(&client)
		testing.expect(t, client.spawn_pending && client.krunker.team == 2 && client.krunker.class_index == 5, "explicit entry must use the confirmed team and selected class")
	}

	lobby_ping_test_send :: proc(state: ^Krunker_WS_State, opcode: string) -> bool {
		if opcode != "po" { return false }
		state.heartbeat_logged += 1
		return true
	}

	@(test)
	krunker_lobby_answers_socket_ping :: proc(t: ^testing.T) {
		client: Client
		defer kproto.krunker_world_reset(&client.krunker_world)
		client.krunker.connected = true
		packet, ok := kproto.krunker_msgpack_encode_packet("pi", nil, 0)
		if !testing.expect(t, ok) do return
		defer delete(packet)
		krunker_ws_apply_world(&client, packet, lobby_ping_test_send)
		testing.expect(t, client.krunker.connected && client.krunker.heartbeat_logged == 1, "pre-spawn socket ping must receive po without waiting for entry")
		testing.expect(t, !client.spawn_pending && !client.krunker.bootstrapped, "ping must not trigger entry")
	}

	join_test_connect :: proc(client: ^Client, link: ^shared.Join_Link) -> bool {
		krunker_ws_set_status(client, "Fixture connection failed. Please try again.")
		return false
	}

	@(test)
	join_invite_status_lifetime :: proc(t: ^testing.T) {
		if !testing.expect(t, bool(glfw.Init()), "GLFW initialization failed") do return
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
		window := glfw.CreateWindow(320, 240, "Invite regression", nil, nil)
		if !testing.expect(t, window != nil, "hidden window failed") do return
		defer glfw.DestroyWindow(window)
		client := Client{window = window}
		defer {
			delete(client.join_status)
			delete(client.selection_status)
			shared.join_link_free(&client.join_link)
		}
		// Exercise the Join handler and its connector handoff without a network
		// request. The test allocator also detects double frees in status updates.
		for invite in ([]string{"https://krunker.io/?game=FRA:fixture", "FRA:fixture", "wss://example.invalid/ws", "https://krunker.io/"}) {
			menuui.set_invite(&client.menu, invite)
			krunker_ws_set_status(&client, "Connecting to lobby...")
			client_join_invite(&client, join_test_connect)
			expected := invite == "https://krunker.io/" ? "The invite URL is missing its game id." : "Fixture connection failed. Please try again."
			testing.expect(t, client.join_status == expected, "join failure must leave a valid status for retry")
		}
	}

	@(test)
	krunker_lobby_waits_for_explicit_entry :: proc(t: ^testing.T) {
		client: Client
		client.krunker.connected=true
		client.krunker.got_load=true
		client.krunker.ready_received=true
		// With no explicit Play request this must never attempt a socket send.
		krunker_ws_bootstrap_tick(&client)
		testing.expect(t, client.krunker.bootstrap_step == 0 && !client.krunker.bootstrapped && !client.spawn_pending, "joining must stay in team/class selection")
		counter: u8
		team_packet := krunker_ws_message("team", &counter, 0, 1, 5)
		defer delete(team_packet)
		messages, _, error := kproto.krunker_msgpack_decode_packet(team_packet[:])
		testing.expect(t, len(error)==0 && len(messages)==1, "team request must encode")
		packet, _ := messages[0].([]kproto.Krunker_Msgpack_Value)
		testing.expect(t, kproto.krunker_world_i32(packet[2], -1) == 1, "request must use the chosen team")
		class_packet := krunker_ws_message("class", &counter, 0, 1, 5)
		defer delete(class_packet)
		class_messages, _, _ := kproto.krunker_msgpack_decode_packet(class_packet[:])
		class_body, _ := class_messages[0].([]kproto.Krunker_Msgpack_Value)
		entries, _ := class_body[2].([]kproto.Krunker_Msgpack_Map_Entry)
		testing.expect(t, kproto.krunker_world_i32(entries[0].value, -1) == 5, "request must use the chosen class")
		entry_packet := krunker_ws_message("en", &counter, 0, 1, 5)
		defer delete(entry_packet)
		entry_messages, _, _ := kproto.krunker_msgpack_decode_packet(entry_packet[:])
		entry_body, _ := entry_messages[0].([]kproto.Krunker_Msgpack_Value)
		loadout, _ := entry_body[1].([]kproto.Krunker_Msgpack_Value)
		testing.expect(t, kproto.krunker_world_i32(loadout[0], -1) == 5, "entry loadout must preserve the selected class")
	}

	@(test)
	krunker_server_disconnect_diagnostics :: proc(t: ^testing.T) {
		client: Client
		defer delete(client.join_status)
		defer delete(client.selection_status)
		defer krunker_ws_disconnect(&client.krunker)
		// A reason can arrive long after the initial packet trace is suppressed.
		client.krunker.connected = true
		client.krunker.rx_logged = 400
		packet, ok := kproto.krunker_msgpack_encode_packet("dc", []kproto.Krunker_Msgpack_Value{"Disconnected due to inactivity", i64(123), "inactivity"}, 0)
		if !testing.expect(t, ok) do return
		defer delete(packet)
		krunker_ws_apply_world(&client, packet)
		testing.expect(t, !client.krunker.connected, "server dc must stop the connection")
		testing.expect(t, strings.contains(client.join_status, "Disconnected due to inactivity"), "server reason must reach the status display")

		client.krunker.connected = true
		error_packet, error_ok := kproto.krunker_msgpack_encode_packet("error", []kproto.Krunker_Msgpack_Value{"Fixture server error"}, 0)
		if !testing.expect(t, error_ok) do return
		defer delete(error_packet)
		krunker_ws_apply_world(&client, error_packet)
		testing.expect(t, client.krunker.connected, "an error message alone does not imply a socket close")
		testing.expect(t, strings.contains(client.join_status, "Fixture server error"), "server errors must remain visible after the initial trace")
		testing.expect(t, client.krunker.server_error == "Fixture server error", "socket close must retain the server's error")
	}

	@(test)
	krunker_outgoing_counter_parity :: proc(t: ^testing.T) {
		// Independent reference: the Rust hoster emits (x,y) before updating
		// y by 5 and x by 2 plus its carry. Exercise multiple complete cycles,
		// interleaving control packets, bootstrap q and the live q encoder.
		x, y: u8 = 2, 5
		counter: u8
		for index in 0 ..< 600 {
			expected := (x << 4) | y
			opcodes := [?]string{"load", "po", "team", "class", "en", "q", "v"}
			opcode := opcodes[index % len(opcodes)]
			packet: []byte
			if index % 2 == 0 {
				counter = kproto.krunker_msgpack_counter_next(counter, "q")
				input := shared.Input{seq = i32(index), move_dir = -1}
				encoded, ok := kproto.krunker_input_encode(&input, 34, counter, false)
				if !testing.expect(t, ok) do return
				packet = encoded
			} else {
				encoded := krunker_ws_message(opcode, &counter, 0)
				packet = encoded[:]
			}
			decoded, _, ok := kproto.krunker_msgpack_decode_trailer(packet)
			testing.expect(t, ok && decoded == expected && counter == expected, "all send paths must follow the reference hoster's counter, including wraps")
			delete(packet)
			testing.expect(t, kproto.krunker_msgpack_counter_next(counter, "cptR") == counter, "CAPTCHA replies preserve the current counter")
			x = (x + (y + 5 >= 16 ? 3 : 2)) & 15
			y = (y + 5) & 15
		}
	}
}
