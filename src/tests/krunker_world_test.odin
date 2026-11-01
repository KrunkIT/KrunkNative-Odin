package main

import "core:fmt"
import krunker "../krunker"

test_krunker_world :: proc() -> bool {
	state := krunker.Krunker_World_State{local_sid = 7}
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
	fmt.println("Krunker world mapping tests OK")
	return true
}
