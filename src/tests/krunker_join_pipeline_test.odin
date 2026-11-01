package main

import "core:fmt"
import krunker "../krunker"
import shared "../shared"

test_krunker_reduce_bytes :: proc(world: ^krunker.Krunker_World_State, packet: []byte) -> bool {
	values, _, err := krunker.krunker_msgpack_decode_packet(packet)
	if len(err) > 0 { fmt.eprintln("Reassembled packet decode failed:", err); return false }
	for value in values {
		if array, ok := value.([]krunker.Krunker_Msgpack_Value); ok {
			if !krunker.krunker_world_apply_packet(world, array) { fmt.eprintln("Fixture packet did not apply"); return false }
		}
	}
	return true
}

test_krunker_join_pipeline :: proc() -> bool {
	world: krunker.Krunker_World_State
	krunker.krunker_world_reset(&world)
	defer krunker.krunker_world_reset(&world)
	assembly: krunker.Krunker_WS_Message
	defer delete(assembly.buffer)
	io_args := []krunker.Krunker_Msgpack_Value{"fixture-socket-id"}
	io, _ := krunker.krunker_msgpack_encode_packet("io-init", io_args, 0)
	defer delete(io)
	if !test_krunker_reduce_bytes(&world, io) || world.local_sid != -1 { fmt.eprintln("Socket ID must be retained as a string until ADD_PLAYERS"); return false }
	init_args := []krunker.Krunker_Msgpack_Value{i64(2), i64(4), i64(0)}
	init, _ := krunker.krunker_msgpack_encode_packet("init", init_args, 0)
	defer delete(init)
	if !test_krunker_reduce_bytes(&world, init) || world.map_index != 2 || !world.ready { return false }
	start_args := []krunker.Krunker_Msgpack_Value{"04:00", i64(2), false, false, false, i64(0), krunker.Krunker_Msgpack_Nil{}, i64(2)}
	start, _ := krunker.krunker_msgpack_encode_packet("start", start_args, 0)
	defer delete(start)
	if !test_krunker_reduce_bytes(&world, start) || krunker.krunker_world_can_render_local(&world) { fmt.eprintln("Start without a local player position must not enter first person"); return false }
	// A record large enough to reproduce the live log's 52 KB message; the
	// integer opcode and distinct socket ID/SID are both essential.
	padding := make([]byte, 52000)
	defer delete(padding)
	for &b in padding { b = 'x' }
	records: [53]krunker.Krunker_Msgpack_Value
	for &record in records { record = krunker.Krunker_Msgpack_Nil{} }
	records[0] = "fixture-socket-id"
	records[1] = i64(7)
	records[2] = f64(120)
	records[3] = f64(30)
	records[4] = f64(-80)
	records[5] = string(padding)
	records[6] = i64(2)
	records[7] = i64(100)
	records[8] = i64(100)
	records[9] = i64(2)
	records[18] = f64(-1.5)
	records[20] = i64(999) // cosmetic, never class index
	root := []krunker.Krunker_Msgpack_Value{i64(0), records[:]}
	large: [dynamic]byte
	defer delete(large)
	if !krunker.krunker_msgpack_write_value(&large, root) { return false }
	append(&large, 0, 0)
	// Chunk sizes include the non-4096 read observed in the user's logs.
	position := 0
	for position < len(large) {
		count := position == 12288 ? 4092 : 4096
		end := min(len(large), position + count)
		payload, complete, err := krunker.krunker_ws_message_feed(&assembly, large[position:end], i64(position), i64(len(large)-end), false)
		if len(err) > 0 || complete != (end == len(large)) { fmt.eprintln("Partial WebSocket message completed too early or failed"); return false }
		if complete && !test_krunker_reduce_bytes(&world, payload) { return false }
		position = end
	}
	if !krunker.krunker_world_can_render_local(&world) || world.local_sid != 7 || len(world.players) != 1 { fmt.eprintln("Spawn/ownership handoff failed after full message"); return false }
	local := &world.players[0]
	if local.class_index != 2 || local.team != 2 || local.position != (shared.Vec3{120, 30, -80}) || local.direction.y != -1.5 { fmt.eprintln("Authoritative spawn fields mapped incorrectly"); return false }
	// The trailer itself may cross receive calls. The next frame must not
	// contain stale data from the previous large frame.
	part, done, err := krunker.krunker_ws_message_feed(&assembly, start[:len(start)-1], 0, 1, false)
	if len(part) != 0 || done || len(err) > 0 { return false }
	part, done, err = krunker.krunker_ws_message_feed(&assembly, start[len(start)-1:], i64(len(start)-1), 0, false)
	if !done || len(err) > 0 || len(part) != len(start) { fmt.eprintln("Split trailer assembly failed"); return false }
	// Multiple protocol frames form one message when CURLWS_CONT is set.
	_, done, err = krunker.krunker_ws_message_feed(&assembly, start[:3], 0, 0, true)
	if done || len(err) > 0 { return false }
	part, done, err = krunker.krunker_ws_message_feed(&assembly, start[3:], 0, 0, false)
	if !done || len(err) > 0 || len(part) != len(start) { fmt.eprintln("Fragmented WebSocket message failed"); return false }
	_, _, err = krunker.krunker_ws_message_feed(&assembly, start[:1], 4, 0, false)
	if len(err) == 0 { fmt.eprintln("Out-of-order chunk accepted"); return false }
	_, _, err = krunker.krunker_ws_message_feed(&assembly, start[:1], 0, krunker.KRUNKER_MSGPACK_MAX_BYTES + 2, false)
	if len(err) == 0 { fmt.eprintln("Oversize message accepted"); return false }
	// Local sync indexes follow the actual browser receiver (not k's layout).
	sync: [18]krunker.Krunker_Msgpack_Value
	for &value in sync { value = krunker.Krunker_Msgpack_Nil{} }
	sync[0] = i64(20)
	sync[2] = f64(200); sync[3] = f64(40); sync[4] = f64(-100)
	sync[5] = f64(2); sync[6] = f64(3); sync[7] = f64(4)
	sync[8] = f64(0.75); sync[9] = true
	sync[15] = f64(0.25); sync[16] = f64(0.5); sync[17] = i64(3)
	sync_packet := []krunker.Krunker_Msgpack_Value{"l", sync[:]}
	if !krunker.krunker_world_apply_packet(&world, sync_packet) || local.position != (shared.Vec3{200, 40, -100}) || local.velocity != (shared.Vec3{3, 2, 4}) || !local.on_ground || local.weapon != 3 || local.aim_val != 0.25 || local.crouch_val != 0.5 || local.ack_seq != 20 { fmt.eprintln("Local sync pose/ack mapping failed"); return false }
	fmt.println("Krunker chunked/fragmented receive, numeric opcode, ownership and spawn pipeline tests OK")
	return true
}

test_krunker_live_input :: proc() -> bool {
	input := shared.Input{seq = 21, move_dir = 6, x_dir = 0.25, y_dir = -4.712, shoot = true, jump = true, swap = 2}
	lock_states := []bool{false, true}
	for locked in lock_states {
		packet, ok := krunker.krunker_input_encode(&input, 33, 39, locked)
		if !ok { return false }
		values, counter, err := krunker.krunker_msgpack_decode_packet(packet)
		if len(err) > 0 || counter != 39 || len(values) != 1 { delete(packet); return false }
		root := values[0].([]krunker.Krunker_Msgpack_Value)
		durations := root[3].([]krunker.Krunker_Msgpack_Value)
		angles := root[5].([]krunker.Krunker_Msgpack_Value)
		controls := root[6].([]krunker.Krunker_Msgpack_Map_Entry)
		valid := len(root) == 7 && root[0].(string) == "q" && root[2].(i64) == 21 && durations[0].(i64) == 33 && angles[0].(i64) == 250 && angles[1].(i64) == -4712 && len(controls) == 11
		valid = valid && controls[0].value.(i64) == (locked ? -1 : 6) && controls[3].value.(i64) == (locked ? 0 : 1) && controls[7].value.(i64) == 2
		delete(packet)
		if !valid { fmt.eprintln("Live q batch shape/angles/controls do not match browser compressor"); return false }
	}
	fmt.println("Krunker live input batch and movement-lock tests OK")
	return true
}
