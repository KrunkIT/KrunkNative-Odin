package main

import "core:testing"
import "core:strings"
import glfw "vendor:glfw"
import kproto "../krunker"
import menuui "../menu"
import shared "../shared"

when ODIN_TEST {
	@(test)
	krunker_breaks_preserve_objective_clock :: proc(t: ^testing.T) {
		client := Client{krunker={connected=true}}
		defer kproto.krunker_world_reset(&client.krunker_world)
		world := &client.krunker_world
		world.has_match, world.match.phase, world.rounds_total = true, .LIVE, 8
		world.received_at = 100
		gameplay_packet(world, "t", "3:00", i64(0))
		gameplay_packet(world, "obj", i64(1), i64(60000))
		for duration, round in ([2]f64{15,30}) {
			world.received_at += 4
			wins := []kproto.Krunker_Msgpack_Map_Entry{{key="1",value=i64(round+1)}, {key="2",value=i64(0)}}
			testing.expect(t, gameplay_packet(world, "rds", i64(6-round), false, i64(1), wins))
			testing.expect(t, world.match.round_wins[1] == u32(round+1), "round wins must decode the browser's string-keyed object")
			gameplay_packet(world, "obj", i64(round+2), i64(60000))
			gameplay_packet(world, "gmsg", "intermission ", "00:30")
			krunker_client_sync_match(&client, world.received_at+duration/2)
			testing.expect(t, client.game.match.objective.rotation_remaining == 60)
			testing.expect(t, strings.contains(krunker_client_countdown_label(&client, world.received_at+1), "Intermission"))
			// No intervening packets: unlocking must discard the ENTIRE break.
			world.received_at += duration
			gameplay_packet(world, "ulm")
			krunker_client_sync_match(&client, world.received_at)
			testing.expect(t, client.game.match.objective.rotation_remaining == 60 && world.countdown == .NONE)
			krunker_client_sync_match(&client, world.received_at+2)
			testing.expect(t, client.game.match.objective.rotation_remaining == 58)
		}
		world.received_at += 3
		gameplay_packet(world, "gmsg", "match starting in ", "00:05")
		krunker_client_sync_match(&client, world.received_at+2)
		testing.expect(t, krunker_client_countdown_label(&client, world.received_at+2) == "Match starts in 00:03")
		world.received_at += 2
		gameplay_packet(world, "gmsg", "match starting in ", "00:03")
		testing.expect(t, world.countdown_remaining == 3, "repeated gmsg labels must still update the remaining time")
		world.received_at += 3
		gameplay_packet(world, "ulm")
		testing.expect(t, world.match.objective.rotation_remaining == 57)
		gameplay_packet(world, "gmsg", "warmup ends ", "01:00")
		testing.expect(t, krunker_client_countdown_label(&client, world.received_at+1) == "Warmup ends in 00:59")
		gameplay_packet(world, "gmsg", "wt")
		testing.expect(t, krunker_client_countdown_label(&client, world.received_at) == "Waiting for players")
		gameplay_packet(world, "gmsg")
		testing.expect(t, world.countdown == .NONE)
	}

	@(test)
	krunker_final_round_win_is_counted_once :: proc(t: ^testing.T) {
		world := kproto.Krunker_World_State{has_match=true, rounds_total=3}
		defer kproto.krunker_world_reset(&world)
		wins := []kproto.Krunker_Msgpack_Map_Entry{{key="1",value=i64(1)}}
		gameplay_packet(&world, "rds", i64(1), false, i64(1), wins)
		for _ in 0..<2 {
			gameplay_packet(&world, "end", i64(0), true, kproto.Krunker_Msgpack_Nil{}, i64(1), kproto.Krunker_Msgpack_Nil{})
		}
		testing.expect(t, world.match.round_wins == [3]u32{0,2,0}, "normal END replaces the last RDS and must not count twice")
		world.final_round_counted = false
		gameplay_packet(&world, "end", i64(0), false, kproto.Krunker_Msgpack_Nil{}, i64(2), i64(3))
		testing.expect(t, world.match.round_wins == [3]u32{0,2,0}, "abandonment must not award a played round")
	}

	@(test)
	krunker_start_waits_for_fresh_spawn_coordinates :: proc(t: ^testing.T) {
		world := kproto.Krunker_World_State{ready=true, local_sid=7}
		defer kproto.krunker_world_reset(&world)
		local := kproto.krunker_world_upsert_player(&world, 7)
		local.active, local.has_position, local.has_ack = true, true, true
		local.position, local.velocity = {500,5,500}, {1,2,3}
		gameplay_packet(&world, i64(3), i64(7), i64(1))
		gameplay_packet(&world, "start", "3:00", i64(1))
		testing.expect(t, !kproto.krunker_world_can_render_local(&world) && !local.has_ack && local.velocity == shared.Vec3{},
			"START cannot reuse death coordinates or replay the previous life's ACK")
		roster: [53]kproto.Krunker_Msgpack_Value
		roster[1], roster[2], roster[3], roster[4], roster[6], roster[9] = i64(7), i64(10), i64(20), i64(30), i64(2), i64(1)
		gameplay_packet(&world, i64(0), roster[:])
		testing.expect(t, kproto.krunker_world_can_render_local(&world) && local.position == shared.Vec3{10,20,30})
		// The opposite ordering must work too.
		gameplay_packet(&world, "3", i64(7), i64(2))
		gameplay_packet(&world, i64(0), roster[:])
		gameplay_packet(&world, "start", "3:00", i64(1))
		testing.expect(t, kproto.krunker_world_can_render_local(&world) && local.position == shared.Vec3{10,20,30},
			"a roster that arrives before START already provides the new spawn")
	}

	@(test)
	krunker_death_cooldown_gates_all_entry_paths :: proc(t: ^testing.T) {
		client := Client{krunker={connected=true, got_load=true, ready_received=true}, game={ready=true}}
		defer kproto.krunker_world_reset(&client.krunker_world)
		world := &client.krunker_world
		world.local_sid, world.received_at = 7, glfw.GetTime()
		local := kproto.krunker_world_upsert_player(world, 7)
		local.active = true
		gameplay_packet(world, "3", i64(7), i64(1))
		testing.expect(t, abs(krunker_client_respawn_remaining(&client, world.received_at)-2.8) < 0.001)
		client_enter_game(&client)
		testing.expect(t, !client.spawn_pending, "programmatic Play must respect the cooldown")
		client.spawn_pending = true
		krunker_ws_bootstrap_tick(&client, entry_test_send)
		testing.expect(t, client.krunker.bootstrap_step == 0, "queued entry must not bypass the cooldown")
		view := menuui.View{ready=true, has_life=true, respawn_remaining=2.8}
		testing.expect(t, menuui.play_label(view) == "Respawn in 3" && len(menuui.play_reason(view)) > 0)
		world.received_at += 1
		gameplay_packet(world, "3", i64(7), i64(1))
		testing.expect(t, abs(krunker_client_respawn_remaining(&client, world.received_at)-1.8) < 0.001, "duplicate deaths must not restart the cooldown")
		testing.expect(t, krunker_client_respawn_remaining(&client, world.received_at+2) == 0)
		view.respawn_remaining = 0
		testing.expect(t, menuui.play_label(view) == "Respawn" && menuui.play_reason(view) == "")
		world.respawn_available_at = 0
		peer := kproto.krunker_world_upsert_player(world, 8); peer.active = true
		gameplay_packet(world, "3", i64(8), i64(1))
		testing.expect(t, world.respawn_available_at == 0, "remote deaths must not delay local entry")
	}
}
