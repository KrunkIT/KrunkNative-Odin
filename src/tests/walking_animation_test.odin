package main

import "core:fmt"
import "core:math"
import shared "../shared"

test_walking_animation :: proc() -> bool {
	// Reference distance samples: swing across both extrema and reverse,
	// rather than wrapping a continuously increasing sine phase.
	sample := shared.Player{render_you = true}
	shared.player_step(&sample, 8)
	if sample.step_val != 2 || !sample.step_dir_neg { return false }
	shared.player_step(&sample, 4)
	if sample.step_val != 1 || !sample.step_dir_neg { return false }
	shared.player_step(&sample, 12)
	if sample.step_val != -2 || sample.step_dir_neg { return false }
	shared.player_step(&sample, 0)
	if sample.step_val != -2 { return false }
	sample = shared.Player{crouch_val = 1}
	shared.player_step(&sample, 4)
	if math.abs(sample.step_val - 1.6) > EPSILON { return false }

	map_inst := shared.Map{death_y = -100, config = shared.Map_Config{speed = {1, 1, 1}, air_accel = 1}}
	floor := shared.Object{active = true, collision_type = .BOX, scale = {10000, 1, 10000}}
	append(&map_inst.objects, &floor)
	defer delete(map_inst.objects)
	game := shared.Game{}
	offline := physics_game_init(&game, &map_inst, true)
	defer shared.game_destroy(&game)
	predicted := shared.player_init(&game)
	shared.game_players_add(&game, predicted)
	shared.player_spawn(predicted, 0)
	for player in ([2]^shared.Player{offline, predicted}) {
		player.is_you = true
		player.render_you = true
		player.position = {0, 1, 0}
		player.on_ground = true
		player.swap_timer = 0
	}
	walk := shared.Input{delta = PHYSICS_DT, move_dir = 3}
	saw_reversal := false
	for tick in 0 ..< 120 {
		shared.player_proc_input(offline, &walk, false, false)
		shared.player_proc_input(predicted, &walk, true, false, true)
		if offline.position != predicted.position || offline.velocity != predicted.velocity ||
		   offline.step_val != predicted.step_val || offline.step_chase != predicted.step_chase ||
		   offline.step_dir_neg != predicted.step_dir_neg || offline.bob_anim != predicted.bob_anim || offline.lean_anim != predicted.lean_anim {
			fmt.printf("Walking animation prediction parity failed at tick %d\n", tick)
			return false
		}
		saw_reversal ||= offline.step_dir_neg
	}
	if !saw_reversal || offline.step_chase == 0 || offline.bob_anim.z <= 0 || offline.lean_anim.z == 0 {
		fmt.eprintln("Walking displacement did not reach the rig animation state")
		return false
	}

	// Reprocessing an input may change physics, but must neither advance
	// nor damp already predicted cosmetic state.
	phase, chase, reverse := predicted.step_val, predicted.step_chase, predicted.step_dir_neg
	bob, lean := predicted.bob_anim, predicted.lean_anim
	shared.player_proc_input(predicted, &walk, true, false)
	if predicted.step_val != phase || predicted.step_chase != chase || predicted.step_dir_neg != reverse || predicted.bob_anim != bob || predicted.lean_anim != lean {
		fmt.eprintln("Reconciliation replay changed walking animation")
		return false
	}

	// Released movement settles the first-person rig back to rest.
	idle := shared.Input{delta = PHYSICS_DT, move_dir = -1}
	for tick in 0 ..< 240 { shared.player_proc_input(offline, &idle, false, false) }
	if math.abs(offline.step_val) > EPSILON || math.abs(offline.step_chase) > EPSILON ||
	   math.abs(offline.bob_anim.z) > EPSILON || math.abs(offline.lean_anim.z) > EPSILON {
		fmt.eprintln("Walking animation did not settle after stopping")
		return false
	}

	// Air movement and locked movement must not start a footstep cycle.
	for locked in ([2]bool{false, true}) {
		shared.player_reset_movement_animation(offline)
		offline.position = {0, locked ? 1 : 100, 0}
		offline.velocity = {}
		offline.on_ground = locked
		shared.player_proc_input(offline, &walk, false, locked)
		if offline.step_val != 0 || offline.step_chase != 0 { return false }
	}

	// Walking into a wall must stop advancing the phase once blocked.
	wall := shared.Object{active = true, collision_type = .BOX, position = {10, 1, 0}, scale = {1, 100, 10000}}
	append(&map_inst.objects, &wall)
	offline.position = {0, 1, 0}
	offline.velocity = {}
	offline.on_ground = true
	straight := walk
	straight.move_dir = 2
	for tick in 0 ..< 120 { shared.player_proc_input(offline, &straight, false, false) }
	blocked_phase := offline.step_val
	blocked_position := offline.position
	shared.player_proc_input(offline, &straight, false, false)
	if offline.position != blocked_position || offline.step_val != blocked_phase {
		fmt.eprintln("Blocked movement advanced the walking animation")
		return false
	}

	shared.player_spawn(offline, 0)
	if offline.step_val != 0 || offline.step_chase != 0 || offline.step_dir_neg || offline.bob_anim != {} || offline.lean_anim != {} { return false }
	fmt.println("Walking cadence/prediction/replay/settling/blocked/respawn tests OK")
	return true
}
