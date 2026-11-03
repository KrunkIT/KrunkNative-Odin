package krunker

import "core:math"
import "core:fmt"
import shared "../shared"

KRUNKER_MAX_INPUT_BATCH :: 32

krunker_display_time :: proc(now: f64, send_rate: f32) -> f64 {
	return now - 1/f64(send_rate > 0 ? send_rate : 10)
}

krunker_input_stamp_shot :: proc(state: ^Krunker_World_State, input: ^shared.Input, now: f64) {
	input.krunker_shot_timed = false
	input.krunker_shot_time, input.krunker_shot_progress = 0, 0
	if !state.has_server_time { return }
	input.krunker_shot_timed = true
	input.krunker_shot_time = state.server_time
	if state.has_previous_sync && state.sync_received_at > state.previous_sync_received_at {
		display_time := krunker_display_time(now, state.send_rate)
		progress := (display_time-state.sync_received_at) / (state.previous_sync_received_at-state.sync_received_at)
		// Keep the browser's negative progress after a late snapshot: the server
		// clamps it to zero. Sending/omitting zero would retain its OLD progress
		// because that receiver only applies truthy values. Cap the older end to
		// match our renderer's held pose. Timing keys use two decimal places.
		input.krunker_shot_progress = math.round(min(progress, 1)*100)/100
	}
}

// Native forward is 0 (-PI/2); the browser's direction table starts at
// -3PI/4, so its forward is 1. Keep -1 as the no-movement sentinel.
krunker_input_move_direction :: proc(direction: i32) -> i32 {
	return direction < 0 ? -1 : (direction + 1) % 8
}

// q contains a duration for every simulated command. Angles are absolute for
// the first command and deltas thereafter; control keys are sample-field pairs.
// Include every control so each packet is independent of earlier packets.
krunker_input_encode_batch :: proc(inputs: []shared.Input, counter: u8, move_lock: bool, reset: bool = false) -> ([]byte, bool) {
	if len(inputs) == 0 || len(inputs) > KRUNKER_MAX_INPUT_BATCH { return nil, false }
	durations: [KRUNKER_MAX_INPUT_BATCH]Krunker_Msgpack_Value
	angles: [KRUNKER_MAX_INPUT_BATCH * 2]Krunker_Msgpack_Value
	controls: [KRUNKER_MAX_INPUT_BATCH * 11]Krunker_Msgpack_Map_Entry
	keys: [KRUNKER_MAX_INPUT_BATCH * 11][12]byte
	timing: [KRUNKER_MAX_INPUT_BATCH * 2]Krunker_Msgpack_Map_Entry
	timing_keys: [KRUNKER_MAX_INPUT_BATCH * 2][12]byte
	timing_count: int
	previous_pitch, previous_yaw: i64
	for input, i in inputs {
		if input.seq != inputs[0].seq + i32(i) { return nil, false }
		if input.krunker_shot_timed {
			key := fmt.bprintf(timing_keys[timing_count][:], "%d", i)
			timing[timing_count] = {key, input.krunker_shot_time}
			timing_count += 1
			if input.krunker_shot_progress != 0 {
				key = fmt.bprintf(timing_keys[timing_count][:], "%dp", i)
				timing[timing_count] = {key, input.krunker_shot_progress}
				timing_count += 1
			}
		}
		durations[i] = i64(clamp(i32(math.round(input.delta * 1000)), 1, 100))
		pitch := i64(math.round(input.x_dir * 1000))
		yaw := i64(math.round(input.y_dir * 1000))
		angles[2*i], angles[2*i+1] = pitch - previous_pitch, yaw - previous_yaw
		previous_pitch, previous_yaw = pitch, yaw
		move := move_lock ? -1 : krunker_input_move_direction(input.move_dir)
		values := [?]i64{i64(move), i64(input.shoot), i64(input.scope), i64(input.jump && !move_lock), i64(input.reload), i64(input.crouch), 0, i64(input.swap), 0, 0, 0}
		for value, field in values {
			index := i*len(values) + field
			key := fmt.bprintf(keys[index][:], "%d-%d", i, field+4)
			controls[index] = {key, value}
		}
	}
	// The browser sets the leading flag after INPUT_FAILED (f). Clearing local
	// history alone leaves the server rejecting every subsequent sequence.
	// The zero is the duration-string digit width (we send an array instead).
	// Shot history timing is the OPTIONAL LAST argument, after the controls.
	args := [7]Krunker_Msgpack_Value{i64(reset), i64(inputs[0].seq), durations[:len(inputs)], i64(0), angles[:len(inputs)*2], controls[:len(inputs)*11], timing[:timing_count]}
	return krunker_msgpack_encode_packet("q", args[:timing_count > 0 ? 7 : 6], counter)
}

// Single-command compatibility helper for bootstrap/protocol checks.
krunker_input_encode :: proc(input: ^shared.Input, elapsed_ms: i32, counter: u8, move_lock: bool) -> ([]byte, bool) {
	command := input^
	command.delta = f32(clamp(elapsed_ms, 1, 100)) / 1000
	return krunker_input_encode_batch(([]shared.Input{command}), counter, move_lock)
}
