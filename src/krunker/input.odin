package krunker

import "core:math"
import shared "../shared"

// One sample is a valid batch in the browser's q compressor. Always include
// both absolute angles and all controls, so no previous batch is required.
krunker_input_encode :: proc(input: ^shared.Input, elapsed_ms: i32, counter: u8, move_lock: bool) -> ([]byte, bool) {
	durations := []Krunker_Msgpack_Value{i64(clamp(elapsed_ms, 1, 100))}
	angles := []Krunker_Msgpack_Value{i64(math.round(input.x_dir * 1000)), i64(math.round(input.y_dir * 1000))}
	move := move_lock ? -1 : input.move_dir
	values := [?]i64{i64(move), i64(input.shoot), i64(input.scope), i64(input.jump && !move_lock), i64(input.reload), i64(input.crouch), 0, i64(input.swap), 0, 0, 0}
	keys := [?]string{"0-4", "0-5", "0-6", "0-7", "0-8", "0-9", "0-10", "0-11", "0-12", "0-13", "0-14"}
	controls: [len(keys)]Krunker_Msgpack_Map_Entry
	for value, i in values { controls[i] = {keys[i], value} }
	args := []Krunker_Msgpack_Value{i64(0), i64(input.seq), durations, i64(0), angles, controls[:]}
	return krunker_msgpack_encode_packet("q", args, counter)
}
