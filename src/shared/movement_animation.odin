package shared

import "core:math"

// Cosmetic state only: never serialized or used to calculate player movement.
Movement_Ease :: enum { LINEAR, BACK_OUT, ELASTIC_OUT }

Movement_Tween :: struct {
	start, end, via: f32,
	time, duration: f32,
	ease: Movement_Ease,
	active, has_via, then_settle: bool,
}

movement_tween :: proc(from, to, duration: f32, ease: Movement_Ease = .LINEAR) -> Movement_Tween {
	return {start = from, end = to, duration = duration, ease = ease, active = true}
}

movement_tween_advance :: proc(tween: ^Movement_Tween, value: ^f32, delta: f32) -> bool {
	if !tween.active { return false }
	tween.time += max(0, delta)
	k := tween.duration > 0 && tween.time < tween.duration - 0.000001 ? tween.time / tween.duration : f32(1)
	e := k
	switch tween.ease {
	case .BACK_OUT:
		t := k - 1
		e = 1 + t * t * (2.70158 * t + 1.70158)
	case .ELASTIC_OUT:
		if k > 0 && k < 1 {
			e = math.pow(f32(2), -10 * k) * math.sin(5 * (k - 0.1) * math.PI) + 1
		}
	case .LINEAR:
	}
	if tween.has_via {
		// TWEEN.js interpolates [start, via, end] and extrapolates the
		// last segment when Back.Out overshoots.
		if e < 0.5 {
			value^ = tween.start + (tween.via - tween.start) * (2 * e)
		} else {
			value^ = tween.via + (tween.end - tween.via) * (2 * e - 1)
		}
	} else {
		value^ = tween.start + (tween.end - tween.start) * e
	}
	if k < 1 { return false }
	tween.active = false
	return true
}

player_reset_movement_animation :: proc(player: ^Player) {
	player.jump_bob_tween = {}
	player.jump_rotate_tween = {}
	player.land_tween = {}
	player.jump_bob_y = 0
	player.jump_rotate = 0
	player.jump_rotate_mlt = 0
	player.land_bob_y = 0
	player.land_bob_yr = 0
	player.step_val = 0
	player.step_chase = 0
	player.step_dir_neg = false
	player.bob_anim = {}
	player.lean_anim = {}
	player.movement_anim_seed = 0x9e3779b9
}

player_animate_jump :: proc(player: ^Player, wall: bool) {
	roll: f32 = 0.15
	if !wall {
		// Keep cosmetic randomness away from gameplay's random stream.
		seed := player.movement_anim_seed
		seed ~= seed << 13
		seed ~= seed >> 17
		seed ~= seed << 5
		player.movement_anim_seed = seed
		roll = 0.12 + 0.03 * f32(seed >> 8) / 16777216
		player.land_tween = movement_tween(player.land_bob_y, 0, 0.1)
	}
	player.jump_bob_tween = movement_tween(player.jump_bob_y, wall ? 0.26 : 0.22, 0.5, .BACK_OUT)
	player.jump_rotate_tween = movement_tween(player.jump_rotate, 0, 0.9, .BACK_OUT)
	player.jump_rotate_tween.has_via = true
	player.jump_rotate_tween.via = roll
}

player_animate_land :: proc(player: ^Player) {
	player.land_tween = movement_tween(player.land_bob_y, player.velocity.y * 6, 0.1)
	player.land_tween.then_settle = true
	player.jump_bob_tween = movement_tween(player.jump_bob_y, 0, 0.1)
}

player_update_movement_animation :: proc(player: ^Player, delta: f32) {
	if movement_tween_advance(&player.land_tween, &player.land_bob_y, delta) && player.land_tween.then_settle {
		player.land_tween = movement_tween(player.land_bob_y, 0, 1.1, .ELASTIC_OUT)
	}
	movement_tween_advance(&player.jump_bob_tween, &player.jump_bob_y, delta)
	movement_tween_advance(&player.jump_rotate_tween, &player.jump_rotate, delta)
}
