package main

import "core:math"
import "core:fmt"
import shared "../shared"
import kproto "../krunker"

// Integer milliseconds match Krunker's simulation clock. This is close to the
// browser's default 144 Hz input rate, independently of rendering and sending.
KRUNKER_INPUT_SECONDS :: 0.007
KRUNKER_SEND_SECONDS :: 1.0 / 30.0

Krunker_Render_Sample :: struct {
	position: shared.Vec3,
	aim: f32,
}

krunker_client_render_sample :: proc(client: ^Client) -> Krunker_Render_Sample {
	state := &client.krunker
	if !state.render_sample_ready { return {client.me.position, client.me.aim_val} }
	alpha := clamp(f32(state.input_elapsed / KRUNKER_INPUT_SECONDS), 0, 1)
	return {
		state.render_previous.position + (state.render_current.position - state.render_previous.position) * alpha,
		state.render_previous.aim + (state.render_current.aim - state.render_previous.aim) * alpha,
	}
}

krunker_client_reset_prediction :: proc(client: ^Client) {
	clear(&client.predicted_inputs)
	clear(&client.krunker.input_commands)
	client.krunker.input_elapsed = 0
	client.krunker.send_elapsed = 0
	client.krunker.input_swap = 0
	client.krunker.render_sample_ready = false
}

// Store and predict exactly the commands that q will transmit. Rendering frames
// never acquire sequence numbers or enter the authoritative replay history.
krunker_client_predict_input :: proc(client: ^Client, frame: ^shared.Input) {
	state := &client.krunker
	if frame.swap != 0 { state.input_swap = frame.swap }
	look := shared.Vec2{clamp(frame.x_dir, -math.PI/2, math.PI/2), frame.y_dir}
	if !state.bootstrapped || !state.spawned {
		client.me.direction = look
		return
	}
	if !state.render_sample_ready {
		state.render_previous = {client.me.position, client.me.aim_val}
		state.render_current = state.render_previous
		state.command_direction = client.me.direction
		state.render_sample_ready = true
	}
	// Bound catch-up after a paused/stalled window, as the browser bounds delta.
	state.input_elapsed += f64(clamp(frame.delta, 0, 0.1))
	state.send_elapsed += f64(clamp(frame.delta, 0, 0.1))
	// Frame delta originates as f32; tolerate its sub-microsecond rounding at
	// an exact command boundary without losing an entire 7 ms command.
	for state.input_elapsed + 1e-7 >= KRUNKER_INPUT_SECONDS {
		command := frame^
		command.seq = state.input_sequence
		command.delta = f32(clamp(i32(math.round(KRUNKER_INPUT_SECONDS * 1000 * f64(client.game.config.delta_mlt))), 1, 33)) / 1000
		command.x_dir = math.round(look.x * 1000) / 1000
		command.y_dir = math.round(shared.normalize_angle(look.y) * 1000) / 1000
		command.swap = state.input_swap
		state.input_swap = 0
		if client.krunker_world.move_lock { command.move_dir = -1; command.jump = false }
		append(&state.input_commands, command)
		state.render_previous = {client.me.position, client.me.aim_val}
		client.me.direction = state.command_direction
		shared.player_proc_input(client.me, &command, true, client.krunker_world.move_lock, true, true)
		// Keep client-only impulse metadata produced by prediction for replay.
		append(&client.predicted_inputs, command)
		if len(client.predicted_inputs) > MAX_PREDICTED_INPUTS { ordered_remove(&client.predicted_inputs, 0) }
		state.command_direction = client.me.direction
		state.render_current = {client.me.position, client.me.aim_val}
		state.input_sequence += 1
		state.input_elapsed = max(0, state.input_elapsed - KRUNKER_INPUT_SECONDS)
	}
	// Mouse look remains responsive on every display frame.
	client.me.direction = look
}

krunker_client_apply_motion :: proc(client: ^Client, player: ^shared.Player, source: ^kproto.Krunker_World_Player, respawned: bool) {
	state := &client.krunker
	is_you := player.is_you
	if is_you && source.position_revision != state.local_position_revision {
		// lm is an explicit server reset, not an ACK to replay past inputs over.
		krunker_client_reset_prediction(client)
		state.input_reset = true
		state.local_position_revision = source.position_revision
		state.local_sync_revision = source.sync_revision
		player.position, player.velocity, player.direction = source.position, source.velocity, source.direction
		player.crouch_val, player.on_ground, player.on_ladder = source.crouch_val, source.on_ground, source.on_ladder
		shared.player_update_height(player)
		state.command_direction = source.direction
		return
	}
	if !is_you {
		// Remote poses are sampled from their timestamped buffer each display
		// frame. Metadata and shot packets must never snap them to the latest k.
		if respawned {
			player.position, player.direction = source.position, source.direction
			player.crouch_val, player.aim_val = source.crouch_val, source.aim_val
			player.on_ground = source.on_ground
			shared.player_update_height(player)
		}
		player.interpolate = false
		if player.loadout_index != source.weapon_slot { shared.player_swap_weapon(player, source.weapon_slot, true, true, true) }
		return
	}
	fresh_sync := source.has_ack && source.sync_revision != state.local_sync_revision
	// Roster/remote updates cannot replay an old local l snapshot.
	if is_you && !respawned && !fresh_sync { return }
	predicted_aim, predicted_aim_time := player.aim_val, player.aim_time
	predicted_direction := player.direction
	predicted_position := player.position
	predicted_weapon := player.weapon
	reload_timer, swap_timer := player.reload_timer, player.swap_timer
	did_shoot, burst_count := player.did_shoot, player.burst_count
	player.position = source.position
	player.velocity = source.velocity
	if !is_you || respawned { player.direction = source.direction }
	player.on_ground = source.on_ground
	player.on_ladder = source.on_ladder
	player.on_terrain = source.on_terrain
	player.did_jump = source.did_jump
	player.did_wall_jump = source.did_wall_jump
	player.on_wall = u8(clamp(source.on_wall, 0, 255))
	player.slide_timer = source.slide_timer
	player.can_slide = source.can_slide
	player.can_slide_timer = source.can_slide_timer
	player.x_vel_cylinder, player.z_vel_cylinder = source.cylinder_velocity.x, source.cylinder_velocity.y
	player.crouch_val = clamp(source.crouch_val, 0, 1)
	player.aim_val = clamp(source.aim_val, 0, 1)
	// k/l transmit a loadout slot, not a weapon registry ID. Selecting the
	// wrong weapon also gives prediction the wrong movement multiplier.
	if player.loadout_index != source.weapon_slot { shared.player_swap_weapon(player, source.weapon_slot, true, true, true) }
	shared.player_update_height(player)
	if is_you && source.has_ack {
		state.local_sync_revision = source.sync_revision
		client_discard_acked_inputs(client, source.ack_seq)
		for &input in client.predicted_inputs { shared.player_proc_input(player, &input, true, client.krunker_world.move_lock) }
		state.input_sequence = max(state.input_sequence, source.ack_seq + 1)
	}
	if !is_you { return }
	if !respawned {
		player.direction = predicted_direction
		// View ADS follows current input, without restarting on a delayed ACK.
		if player.weapon == predicted_weapon && !player.weapon.no_aim {
			player.aim_val, player.aim_time = predicted_aim, predicted_aim_time
		}
		if player.weapon == predicted_weapon {
			player.reload_timer, player.swap_timer = reload_timer, swap_timer
			player.did_shoot, player.burst_count = did_shoot, burst_count
		}
	}
	if respawned || !state.render_sample_ready {
		state.render_previous = {player.position, player.aim_val}
		state.render_current = state.render_previous
		state.command_direction = player.direction
		state.render_sample_ready = true
	} else {
		// Preserve interpolation within the current command after a correction.
		correction := player.position - predicted_position
		state.render_previous.position += correction
		state.render_current.position += correction
		state.prediction_corrections += 1
		error := math.sqrt(correction.x*correction.x + correction.y*correction.y + correction.z*correction.z)
		if error >= 2 || state.prediction_corrections <= 3 || state.prediction_corrections % 30 == 0 {
			pending_ms: f32
			for input in client.predicted_inputs { pending_ms += input.delta * 1000 }
			kproto.network_log("prediction", fmt.tprintf("ack=%d correction=%.3f delta=%v server_position=%v pending_commands=%d pending_ms=%.0f unsent=%d next_seq=%d", source.ack_seq, error, correction, source.position, len(client.predicted_inputs), pending_ms, len(state.input_commands), state.input_sequence))
		}
	}
}
