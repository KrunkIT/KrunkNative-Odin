package main

import "core:fmt"
import "core:math"
import krunker "../krunker"

test_krunker_world :: proc() -> bool {
	state := krunker.Krunker_World_State{local_sid = 7}
	defer krunker.krunker_world_reset(&state)
	init_packet := []krunker.Krunker_Msgpack_Value{
		krunker.krunker_msgpack_string("init"), krunker.krunker_msgpack_int(3), krunker.krunker_msgpack_int(4),
		krunker.krunker_msgpack_int(5),
	}
	if !krunker.krunker_world_apply_init(&state, init_packet) || !state.ready || state.map_index != 3 { fmt.eprintln("Krunker init mapping failed"); return false }
	start_packet := []krunker.Krunker_Msgpack_Value{
		krunker.krunker_msgpack_string("start"), krunker.krunker_msgpack_string("04:00"), krunker.krunker_msgpack_int(2),
		krunker.krunker_msgpack_bool(false), krunker.krunker_msgpack_bool(false), krunker.krunker_msgpack_bool(false),
		krunker.krunker_msgpack_int(0), krunker.krunker_msgpack_nil(), krunker.krunker_msgpack_int(2),
	}
	if !krunker.krunker_world_apply_start(&state, start_packet) || !state.in_game { fmt.eprintln("Krunker start mapping failed"); return false }
	if len(state.players) != 1 || state.players[0].team != 2 || state.players[0].class_index != 2 { fmt.eprintln("Krunker start player mapping failed"); return false }
	// Remote k angles are degrees, whereas local l yaw is already radians.
	remote := []krunker.Krunker_Msgpack_Value{
		i64(8), i64(10), i64(20), i64(30), i64(90), i64(-30), i64(0), true, f64(0.25), i64(3), f64(0.75), krunker.krunker_msgpack_nil(), i64(40),
	}
	remote_packet := []krunker.Krunker_Msgpack_Value{"k", remote}
	if !krunker.krunker_world_apply_update_players(&state, remote_packet) { return false }
	peer := &state.players[1]
	if abs(peer.direction.x + math.PI/6) > 1e-5 || abs(peer.direction.y - math.PI/2) > 1e-5 || peer.aim_val != 0.25 {
		fmt.eprintln("Remote pose angle/ADS conversion failed"); return false
	}
	remote[4], remote[5], remote[10] = krunker.krunker_msgpack_nil(), krunker.krunker_msgpack_nil(), krunker.krunker_msgpack_nil()
	krunker.krunker_world_apply_update_players(&state, remote_packet)
	if peer.aim_val != 0.25 || abs(peer.direction.x + math.PI/6) > 1e-5 { fmt.eprintln("Omitted pose fields must preserve their previous values"); return false }
	local: [21]krunker.Krunker_Msgpack_Value
	local[0], local[8], local[15], local[17] = i64(13), f64(1.25), i64(1), i64(3)
	local[10], local[11], local[13], local[14] = true, true, i64(2), true
	local[18], local[19], local[20] = i64(250), true, true
	local_packet := []krunker.Krunker_Msgpack_Value{"l", local[:]}
	if !krunker.krunker_world_apply_sync_player(&state, local_packet) { return false }
	you := &state.players[0]
	if you.aim_val != 0 || you.direction.y != 1.25 || you.sync_revision != 1 || you.ack_seq != 13 ||
		!you.did_jump || !you.did_wall_jump || you.on_wall != 2 || !you.on_ladder || you.slide_timer != 0.25 || !you.can_slide || !you.on_terrain {
		fmt.eprintln("Local pose/movement synchronization failed"); return false
	}
	local[15] = i64(0)
	krunker.krunker_world_apply_sync_player(&state, local_packet)
	if you.aim_val != 1 || you.sync_revision != 2 { fmt.eprintln("Local ADS endpoint conversion failed"); return false }
	local[15] = f64(0.4)
	krunker.krunker_world_apply_sync_player(&state, local_packet)
	if abs(you.aim_val - 0.6) > 1e-5 { fmt.eprintln("Local partial ADS conversion failed"); return false }
	remote[10] = i64(0)
	krunker.krunker_world_apply_update_players(&state, remote_packet)
	if peer.aim_val != 1 || you.sync_revision != 3 { fmt.eprintln("Remote update must not advance local snapshot revision"); return false }
	fmt.println("Krunker world mapping tests OK")
	return true
}
