package main

import "core:testing"
import shared "../shared"
import kproto "../krunker"

when ODIN_TEST {
	@(test)
	krunker_regen_requires_equipped_confirmation :: proc(t: ^testing.T) {
		world := kproto.Krunker_World_State{local_sid=7}
		defer kproto.krunker_world_reset(&world)
		player := kproto.krunker_world_upsert_player(&world, 7)
		player.active, player.has_position, player.has_ack = true, true, true
		player.class_index, player.secondary_id, player.health = 12, 2, 40
		player.position, player.velocity = {10,20,30}, {1,2,3}
		player.weapon_slot, player.ammo_count = 1, 2
		items: [19]kproto.Krunker_Msgpack_Value
		items[14], items[15] = i64(15), i64(2)
		packet := []kproto.Krunker_Msgpack_Value{"rg", i64(7), false, items[:]}
		testing.expect(t, kproto.krunker_world_apply_packet(&world, packet))
		testing.expect(t, player.class_index == 12 && player.secondary_id == 2 && player.health == 40 && player.has_ack,
			"cosmetic/preference updates must not change the equipped class, refill health, or invalidate movement")
		packet[2] = true
		testing.expect(t, kproto.krunker_world_apply_packet(&world, packet))
		testing.expect(t, player.class_index == 2 && player.secondary_id == 15 && player.loadout_revision == 1 && player.secondary_revision == 1)
		testing.expect(t, player.active && player.health == 100 && player.max_health == 100 && player.position == shared.Vec3{10,20,30},
			"an accepted live change must refill the new class in place")
		testing.expect(t, player.weapon_slot == 0 && player.ammo_count == 0 && !player.has_ack && player.velocity == shared.Vec3{},
			"old weapon/ammo/ACK/movement must not overwrite the new loadout")
		kproto.krunker_world_apply_packet(&world, packet)
		testing.expect(t, player.loadout_revision == 2, "same-class resets must remain observable")
		packet[1] = i64(999)
		testing.expect(t, !kproto.krunker_world_apply_packet(&world, packet) && len(world.players) == 1, "unknown players must not be manufactured by rg")
		packet[1], items[15] = i64(7), i64(999)
		testing.expect(t, !kproto.krunker_world_apply_packet(&world, packet) && player.class_index == 2, "malformed loadouts must leave confirmed state intact")
		items[15] = i64(12)
		player.active, player.life_ended, player.health = false, true, 0
		kproto.krunker_world_apply_packet(&world, packet)
		testing.expect(t, !player.active && player.life_ended && player.health == 0, "regeneration must never resurrect a dead player")
		packet[3] = items[:15]
		testing.expect(t, !kproto.krunker_world_apply_packet(&world, packet))
	}

	@(test)
	krunker_live_class_window_expires :: proc(t: ^testing.T) {
		client := Client{krunker={connected=true}, krunker_world={is_comp=true, countdown_received_at=100, countdown_remaining=15}}
		for phase in ([]kproto.Krunker_Countdown{.WARMUP, .INTERMISSION}) {
			client.krunker_world.countdown = phase
			testing.expect(t, krunker_client_live_class_window(&client, 114.99))
			testing.expect(t, !krunker_client_live_class_window(&client, 115), "the live-change label must expire even before the next packet")
		}
		client.krunker_world.countdown = .STARTING
		testing.expect(t, !krunker_client_live_class_window(&client, 101))
		client.krunker_world.countdown, client.krunker_world.is_comp, client.krunker_world.is_ranked = .WARMUP, false, true
		testing.expect(t, krunker_client_live_class_window(&client, 101))
		client.krunker_world.is_ranked = false
		testing.expect(t, !krunker_client_live_class_window(&client, 101))
	}

	@(test)
	krunker_shot_timing_matches_displayed_history :: proc(t: ^testing.T) {
		client: Client
		map_inst: shared.Map
		krunker_presentation_fixture(&client, &map_inst)
		defer krunker_presentation_cleanup(&client)
		peer := shared.player_init(&client.game)
		shared.game_players_add(&client.game, peer)
		shared.player_spawn(peer, 2)
		peer.uid = 8
		record := []kproto.Krunker_Msgpack_Value{i64(8), i64(0), i64(0), i64(-100), i64(0), i64(0), i64(0), true, f64(0), i64(0), f64(1), kproto.Krunker_Msgpack_Nil{}, i64(20)}
		packet := []kproto.Krunker_Msgpack_Value{"k", record, i64(10), i64(1000)}
		client.krunker_world.received_at = 1
		kproto.krunker_world_apply_packet(&client.krunker_world, packet)
		record[1], packet[3], client.krunker_world.received_at = i64(10), i64(1100), 1.1
		kproto.krunker_world_apply_packet(&client.krunker_world, packet)
		krunker_client_interpolate_remotes(&client, 1.15, 0.007)
		testing.expect(t, abs(peer.position.x-5) < 0.001)
		frame := shared.Input{delta=0.007, move_dir=-1, shoot=true}
		krunker_client_predict_input(&client, &frame, 1.15)
		command := client.krunker.input_commands[0]
		testing.expect(t, command.krunker_shot_timed && command.krunker_shot_time == 1100 && command.krunker_shot_progress == 0.5,
			"actual fire must capture the latest server sample and the displayed interpolation fraction")
		// Browser fetchState selects the latest sample then interpolates toward
		// the older one. Its target must coincide with the native visible model.
		history_x := 10 + (0-10)*command.krunker_shot_progress
		testing.expect(t, abs(f64(peer.position.x)-history_x) < 0.001)
		krunker_client_predict_input(&client, &frame, 1.157)
		testing.expect(t, !client.krunker.input_commands[1].krunker_shot_timed, "holding fire during cooldown must not create another shot timestamp")
		encoded, ok := krunker_ws_encode_input(&client.krunker)
		if !testing.expect(t, ok) { return }
		defer delete(encoded)
		messages, _, err := kproto.krunker_msgpack_decode_packet(encoded)
		if !testing.expect(t, len(err) == 0) { return }
		root := messages[0].([]kproto.Krunker_Msgpack_Value)
		if !testing.expect(t, len(root) == 8, "browser q appends timing AFTER duration width, angles, and controls") { return }
		timing := root[7].([]kproto.Krunker_Msgpack_Map_Entry)
		testing.expect(t, len(timing) == 2 && timing[0].key.(string) == "0" && kproto.krunker_world_f32(timing[0].value) == 1100 &&
			timing[1].key.(string) == "0p" && kproto.krunker_world_f32(timing[1].value) == 0.5)
		// Transport retries must retain the original shot's timing even as new
		// snapshots arrive and the rendering clock advances.
		packet[3], client.krunker_world.received_at = i64(1200), 1.2
		kproto.krunker_world_apply_packet(&client.krunker_world, packet)
		retry, retry_ok := krunker_ws_encode_input(&client.krunker)
		defer delete(retry)
		testing.expect(t, retry_ok && len(encoded) == len(retry))
		for b, i in encoded { if !testing.expect(t, i < len(retry) && b == retry[i]) { break } }
	}

	@(test)
	krunker_timing_anchors_reset_and_bound_stalls :: proc(t: ^testing.T) {
		world: kproto.Krunker_World_State
		defer kproto.krunker_world_reset(&world)
		command: shared.Input
		kproto.krunker_input_stamp_shot(&world, &command, 1)
		testing.expect(t, !command.krunker_shot_timed, "shots before the first k must not invent a server clock")
		empty: [0]kproto.Krunker_Msgpack_Value
		packet := []kproto.Krunker_Msgpack_Value{"k", empty[:], i64(20), i64(500)}
		world.received_at = 1
		kproto.krunker_world_apply_packet(&world, packet)
		kproto.krunker_input_stamp_shot(&world, &command, 1)
		testing.expect(t, command.krunker_shot_time == 500 && command.krunker_shot_progress == 0, "empty k packets still establish timing")
		world.received_at, packet[3] = 1.05, i64(550)
		kproto.krunker_world_apply_packet(&world, packet)
		kproto.krunker_input_stamp_shot(&world, &command, 10)
		testing.expect(t, command.krunker_shot_progress < 0 && clamp(command.krunker_shot_progress, 0, 1.2) == 0,
			"negative browser progress must reset the server's previous fraction to the renderer's held latest pose")
		packet[1], packet[3], world.received_at = kproto.Krunker_Msgpack_Nil{}, i64(600), 1.1
		testing.expect(t, kproto.krunker_world_apply_packet(&world, packet) && world.server_time == 600, "k without visible players still advances the server clock")
		gameplay_packet(&world, "init", i64(2), i64(4))
		testing.expect(t, !world.has_server_time && !world.has_previous_sync && world.server_time == 0, "a new map must not reuse the previous map's server clock")
		kproto.krunker_input_stamp_shot(&world, &command, 2)
		testing.expect(t, !command.krunker_shot_timed && command.krunker_shot_progress == 0)
	}

	@(test)
	krunker_shot_timing_survives_batch_boundaries :: proc(t: ^testing.T) {
		state: Krunker_WS_State
		defer krunker_ws_disconnect(&state)
		for i in 0..<35 {
			append(&state.input_commands, shared.Input{seq=i32(100+i), delta=0.007, move_dir=-1,
				krunker_shot_timed=i == 31 || i == 34, krunker_shot_time=1100, krunker_shot_progress=0.25})
		}
		for batch in 0..<2 {
			encoded, ok := krunker_ws_encode_input(&state)
			if !testing.expect(t, ok) { return }
			defer delete(encoded)
			messages, counter, err := kproto.krunker_msgpack_decode_packet(encoded)
			if !testing.expect(t, len(err) == 0) { return }
			root := messages[0].([]kproto.Krunker_Msgpack_Value)
			if !testing.expect(t, len(root) == 8) { return }
			timing := root[7].([]kproto.Krunker_Msgpack_Map_Entry)
			testing.expect(t, len(timing) == 2 && timing[0].key.(string) == (batch == 0 ? "31" : "2") &&
				timing[1].key.(string) == (batch == 0 ? "31p" : "2p"), "shot keys must index their transmitted batch, including after queue consumption")
			testing.expect(t, root[2].(i64) == (batch == 0 ? 100 : 132) && kproto.krunker_world_f32(timing[0].value) == 1100)
			krunker_ws_input_sent(&state, min(len(state.input_commands), 32), counter)
		}
	}

	@(test)
	krunker_packet_logging_keeps_failures_visible :: proc(t: ^testing.T) {
		for opcode in ([]string{"ai", "k", "l", "h", "s", "pi"}) { testing.expect(t, krunker_ws_routine_packet(opcode)) }
		for opcode in ([]string{"f", "rg", "error", "dc", "start", "rds", "unknown"}) { testing.expect(t, !krunker_ws_routine_packet(opcode)) }
		testing.expect(t, krunker_ws_routine_packet(i64(9)) && !krunker_ws_routine_packet(i64(3)))
	}
}
