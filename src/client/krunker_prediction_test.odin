package main

import "core:fmt"
import "core:math"
import "core:testing"
import "core:strings"
import shared "../shared"
import kproto "../krunker"

when ODIN_TEST {
	// Decode q using the browser's layout and direction registry, independently
	// of the encoder. Feed these commands to the simulated authoritative peer.
	krunker_test_decode_commands :: proc(t: ^testing.T, packet: []byte) -> []shared.Input {
		messages, _, error_text := kproto.krunker_msgpack_decode_packet(packet)
		if !testing.expect(t, len(error_text) == 0 && len(messages) == 1, "q packet must decode") { return nil }
		root := messages[0].([]kproto.Krunker_Msgpack_Value)
		durations := root[3].([]kproto.Krunker_Msgpack_Value)
		angles := root[5].([]kproto.Krunker_Msgpack_Value)
		controls := root[6].([]kproto.Krunker_Msgpack_Map_Entry)
		commands := make([]shared.Input, len(durations), context.temp_allocator)
		fields := make(map[string]i64, context.temp_allocator)
		for entry in controls { fields[entry.key.(string)] = entry.value.(i64) }
		pitch, yaw: i64
		for &command, i in commands {
			pitch += angles[i*2].(i64)
			yaw += angles[i*2+1].(i64)
			command.seq = i32(root[2].(i64)) + i32(i)
			command.delta = f32(durations[i].(i64)) / 1000
			command.x_dir, command.y_dir = f32(pitch)/1000, f32(yaw)/1000
			wire_move := i32(fields[fmt.tprintf("%d-4", i)])
			// Browser direction i is -PI + (i+1)*PI/4. Native 0 is -PI/2.
			command.move_dir = wire_move < 0 ? -1 : (wire_move + 7) % 8
			command.shoot = fields[fmt.tprintf("%d-5", i)] != 0
			command.scope = fields[fmt.tprintf("%d-6", i)] != 0
			command.jump = fields[fmt.tprintf("%d-7", i)] != 0
			command.reload = fields[fmt.tprintf("%d-8", i)] != 0
			command.crouch = fields[fmt.tprintf("%d-9", i)] != 0
			command.swap = u8(fields[fmt.tprintf("%d-11", i)])
		}
		return commands
	}

	@(test)
	krunker_command_batch_matches_browser :: proc(t: ^testing.T) {
		commands: [9]shared.Input
		for &command, i in commands {
			command = {seq = i32(13+i), delta = 0.007, move_dir = i32(i)-1, x_dir = f32(i)*0.1, y_dir = 3-f32(i)*0.8,
				jump = i%2 == 0, scope = i%3 == 0, crouch = i%4 == 0, reload = i == 4, shoot = i%2 != 0, swap = i == 3 ? 2 : 0}
		}
		packet, ok := kproto.krunker_input_encode_batch(commands[:], 80, false)
		if !testing.expect(t, ok, "multiple commands must encode") { return }
		defer delete(packet)
		decoded := krunker_test_decode_commands(t, packet)
		if !testing.expect(t, len(decoded) == len(commands), "q must preserve every command") { return }
		for command, i in decoded {
			expected := commands[i]
			testing.expect(t, command.seq == expected.seq && command.delta == expected.delta && command.move_dir == expected.move_dir,
				"command sequence, duration, and movement must match after browser decoding")
			testing.expect(t, abs(command.x_dir-expected.x_dir) < 0.0001 && abs(command.y_dir-expected.y_dir) < 0.0001,
				"angle deltas must reconstruct absolute pitch/yaw, including negative angles")
			testing.expect(t, command.jump == expected.jump && command.scope == expected.scope && command.crouch == expected.crouch &&
				command.reload == expected.reload && command.shoot == expected.shoot && command.swap == expected.swap,
				"control changes within a batch must survive transmission")
		}
		// Explicit cardinal checks catch a shared error in the round-trip helpers.
		testing.expect(t, kproto.krunker_input_move_direction(0) == 1 && kproto.krunker_input_move_direction(2) == 3 &&
			kproto.krunker_input_move_direction(4) == 5 && kproto.krunker_input_move_direction(6) == 7,
			"forward/right/back/left must use browser direction IDs 1/3/5/7")
	}

	krunker_test_deliver_commands :: proc(t: ^testing.T, client: ^Client, server: ^shared.Player) -> i32 {
		count := min(len(client.krunker.input_commands), kproto.KRUNKER_MAX_INPUT_BATCH)
		packet, ok := kproto.krunker_input_encode_batch(client.krunker.input_commands[:count], 80, false)
		if !testing.expect(t, ok) { return -1 }
		defer delete(packet)
		ack: i32 = -1
		for &command in krunker_test_decode_commands(t, packet) {
			shared.player_proc_input(server, &command, true, client.krunker_world.move_lock)
			ack = command.seq
		}
		copy(client.krunker.input_commands[:], client.krunker.input_commands[count:])
		resize(&client.krunker.input_commands, len(client.krunker.input_commands)-count)
		client.krunker.send_elapsed = max(0, client.krunker.send_elapsed-KRUNKER_SEND_SECONDS)
		return ack
	}

	@(test)
	krunker_prediction_matches_transmission_across_frame_rates :: proc(t: ^testing.T) {
		config := shared.config_load_gameplay()
		defer shared.config_destroy_gameplay(config)
		baseline: shared.Vec3
		for fps, rate_index in ([]int{50, 144, 700, 1500}) {
			floor := shared.Object{active = true, collision_type = .BOX, position = {0, -1, 0}, scale = {10000, 1, 10000}}
			map_inst := shared.Map{death_y = -1000, config = {speed = {1, 1, 1}, air_accel = 1}}
			append(&map_inst.objects, &floor)
			defer delete(map_inst.objects)
			client: Client
			shared.game_configure(&client.game, &config.game, []^shared.Map{&map_inst}, nil, config.weapons, config.classes)
			shared.game_init(&client.game, 0, 0, false)
			defer shared.game_destroy(&client.game)
			defer delete(client.predicted_inputs)
			defer krunker_ws_disconnect(&client.krunker)
			client.me = shared.player_init(&client.game)
			shared.game_players_add(&client.game, client.me)
			shared.player_spawn(client.me, 2)
			client.me.is_you = true
			client.me.swap_timer = 0
			server := shared.player_init(&client.game)
			defer shared.player_destroy(server)
			shared.player_spawn(server, 2)
			server.swap_timer = 0
			client.krunker.spawned, client.krunker.bootstrapped = true, true
			client.krunker.input_sequence = 13
			snapshot: kproto.Krunker_World_Player
			captured, reconciled := false, false
			elapsed: f64
			last_ack: i32 = 12
			for elapsed < 1.40000001 {
				delta := min(1/f64(fps), 1.40000001-elapsed)
				frame := shared.Input{delta = f32(delta), move_dir = 0, x_dir = 0.123456, y_dir = 0.713876}
				krunker_client_predict_input(&client, &frame)
				elapsed += delta
				if client.krunker.send_elapsed >= KRUNKER_SEND_SECONDS && len(client.krunker.input_commands) > 0 {
					last_ack = krunker_test_deliver_commands(t, &client, server)
				}
				// Real l corrections arrive once per second. Delay this one a
				// further 100 ms, so replay includes both sent and unsent commands.
				if !captured && elapsed >= 1 {
					snapshot = {position = server.position, velocity = server.velocity, on_ground = server.on_ground,
						weapon_slot = 0, can_slide = true, has_ack = true, ack_seq = last_ack, sync_revision = 1}
					captured = true
				}
				if !reconciled && elapsed >= 1.1 {
					before := client.me.position
					krunker_client_apply_motion(&client, client.me, &snapshot, false)
					testing.expect(t, math.abs(client.me.position.x-before.x) < 0.0001 && math.abs(client.me.position.z-before.z) < 0.0001,
						"a delayed authoritative ACK must not teleport a correctly predicted player")
					reconciled = true
				}
			}
			for len(client.krunker.input_commands) > 0 { krunker_test_deliver_commands(t, &client, server) }
			testing.expect(t, client.krunker.input_sequence == 213, "1.4 seconds must produce 200 unique 7 ms commands at every display rate")
			testing.expect(t, abs(client.me.position.x-server.position.x) < 0.0001 && abs(client.me.position.z-server.position.z) < 0.0001,
				"local prediction must match the peer that processed the actual wire commands")
			if rate_index == 0 { baseline = client.me.position }
			testing.expect(t, abs(client.me.position.x-baseline.x) < 0.0001 && abs(client.me.position.z-baseline.z) < 0.0001,
				"movement speed and travel must be independent of rendering FPS")
			testing.expect(t, client.me.direction == (shared.Vec2{0.123456, 0.713876}), "sampling must not quantize the rendered mouse look")
		}
	}

	@(test)
	krunker_input_failure_resumes_server_acknowledgements :: proc(t: ^testing.T) {
		client: Client
		defer delete(client.predicted_inputs)
		defer krunker_ws_disconnect(&client.krunker)
		state := &client.krunker
		state.connected, state.spawned, state.bootstrapped = true, true, true
		// Reproduce the live log: the server stopped at 631 after f(4), while
		// later, otherwise valid q packets continued to be sent indefinitely.
		server_ack: i32 = 631
		state.input_sequence = 650
		state.ah_num = 239
		state.input_elapsed, state.send_elapsed = 0.004, 0.02
		append(&client.predicted_inputs, shared.Input{seq = 648}, shared.Input{seq = 649})
		append(&state.input_commands, shared.Input{seq = 649})
		failure, ok := kproto.krunker_msgpack_encode_packet("f", []kproto.Krunker_Msgpack_Value{i64(4)}, 0)
		if !testing.expect(t, ok) { return }
		defer delete(failure)
		krunker_ws_apply_world(&client, failure)
		testing.expect(t, len(client.predicted_inputs) == 0 && len(state.input_commands) == 0 && state.input_elapsed == 0,
			"INPUT_FAILED must discard rejected prediction and the unsent batch")
		testing.expect(t, state.input_reset && state.input_sequence == 650 && state.ah_num == 239,
			"recovery must request a wire reset without rewinding the monotonic sequence or packet counter")
		for i in 0..<5 {
			command := shared.Input{seq = state.input_sequence, delta = 0.007, move_dir = 0}
			append(&state.input_commands, command)
			append(&client.predicted_inputs, command)
			state.input_sequence += 1
		}
		state.send_elapsed = KRUNKER_SEND_SECONDS
		append(&state.pending, strings.clone("v"))
		krunker_ws_send_input(&client)
		testing.expect(t, state.input_reset && len(state.input_commands) == 5 && state.ah_num == 239,
			"a blocked transport must retain the reset request until it actually sends")
		packet, encoded := krunker_ws_encode_input(state)
		if !testing.expect(t, encoded) { return }
		defer delete(packet)
		retry, retried := krunker_ws_encode_input(state)
		defer delete(retry)
		testing.expect(t, retried && len(packet) == len(retry) && state.input_reset && state.ah_num == 239,
			"encoding/retrying an unsent reset must not consume it or advance the counter")
		for b, i in packet { if !testing.expect(t, b == retry[i], "an unsent retry must keep the same wire bytes") { return } }
		messages, counter, error_text := kproto.krunker_msgpack_decode_packet(packet)
		if !testing.expect(t, len(error_text) == 0 && len(messages) == 1) { return }
		root := messages[0].([]kproto.Krunker_Msgpack_Value)
		// Model the receiving peer's recovery gate independently: only q's
		// leading reset flag allows processing after an input failure.
		server_waiting_for_reset := true
		if root[1].(i64) == 1 { server_waiting_for_reset = false }
		if !server_waiting_for_reset {
			for command in krunker_test_decode_commands(t, packet) { server_ack = command.seq }
		}
		testing.expect(t, server_ack == 654 && counter == 20,
			"the first recovery packet must unblock ACK progress, including at a packet-counter wrap")
		krunker_ws_input_sent(state, 5, counter)
		client_discard_acked_inputs(&client, server_ack)
		testing.expect(t, !state.input_reset && len(state.input_commands) == 0 && len(client.predicted_inputs) == 0,
			"a successful reset and its ACK must retire the recovered commands")
		append(&state.input_commands, shared.Input{seq = 655, delta = 0.007, move_dir = -1})
		normal, normal_ok := krunker_ws_encode_input(state)
		if !testing.expect(t, normal_ok) { return }
		defer delete(normal)
		normal_messages, _, _ := kproto.krunker_msgpack_decode_packet(normal)
		testing.expect(t, normal_messages[0].([]kproto.Krunker_Msgpack_Value)[1].(i64) == 0,
			"normal packets must stop requesting resets after successful recovery")
	}

	@(test)
	krunker_prediction_retains_unsent_controls :: proc(t: ^testing.T) {
		map_inst := shared.Map{death_y = -1000, config = {speed = {1, 1, 1}, air_accel = 1}}
		client: Client
		shared.game_configure(&client.game, nil, []^shared.Map{&map_inst}, nil, nil, nil)
		shared.game_init(&client.game, 0, 0, false)
		defer shared.game_destroy(&client.game)
		defer delete(client.predicted_inputs)
		defer krunker_ws_disconnect(&client.krunker)
		client.me = shared.player_init(&client.game)
		shared.game_players_add(&client.game, client.me)
		shared.player_spawn(client.me, 2)
		client.me.noclip = true
		client.me.swap_timer = 0
		client.krunker.spawned, client.krunker.bootstrapped = true, true
		client.krunker.input_sequence = 13
		frame := shared.Input{delta = 0.001, move_dir = 0, swap = 2}
		krunker_client_predict_input(&client, &frame)
		frame.swap = 0
		for _ in 0..<20 { krunker_client_predict_input(&client, &frame) }
		if !testing.expect(t, len(client.krunker.input_commands) == 3, "render frames must accumulate into command ticks") { return }
		testing.expect(t, client.krunker.input_commands[0].swap == 2 && client.krunker.input_commands[1].swap == 0 && client.me.weapon.melee,
			"a swap pressed between ticks must reach both prediction and the outgoing queue exactly once")
		frame.x_dir, frame.y_dir = 0.2, 0.4
		before := client.me.position
		krunker_client_predict_input(&client, &frame)
		testing.expect(t, client.me.position == before && client.me.direction == (shared.Vec2{0.2, 0.4}),
			"mouse look must update even when no physics command is due")
		sample := krunker_client_render_sample(&client)
		low, high := client.krunker.render_previous.position, client.krunker.render_current.position
		testing.expect(t, sample.position.z <= max(low.z, high.z) && sample.position.z >= min(low.z, high.z),
			"rendering must interpolate inside the current movement step")
		// A pending WebSocket control packet blocks q without dropping predicted
		// commands or consuming their sequence numbers/counter.
		client.krunker.connected = true
		client.krunker.send_elapsed = 0.1
		append(&client.krunker.pending, strings.clone("v"))
		count, sequence := len(client.krunker.input_commands), client.krunker.input_sequence
		krunker_ws_send_input(&client)
		testing.expect(t, len(client.krunker.input_commands) == count && client.krunker.input_sequence == sequence && client.krunker.ah_num == 0,
			"a blocked send must preserve the exact queued commands for retry")
		krunker_client_reset_prediction(&client)
		testing.expect(t, len(client.predicted_inputs) == 0 && len(client.krunker.input_commands) == 0 && client.krunker.input_elapsed == 0,
			"respawns/input resets must discard unsent movement along with prediction history")
	}
}
