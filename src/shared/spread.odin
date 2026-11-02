package shared

import "core:math"

// Browser combat constants: game.deob.js spreadPlus / spread / projSpreads.
// Native aim_val is reversed: 1 means fully aimed.
player_update_spread :: proc(player: ^Player, distance, vertical_distance, delta: f32) {
	if player == nil || player.weapon == nil { return }
	weapon := player.weapon
	player.spread_plus += (distance * 25 + abs(vertical_distance) * 30) * weapon.move_spread
	player.spread_plus *= math.pow(f32(0.985), max(0, delta) * 1000)
	player.spread = weapon.no_spread ? 0 : max(weapon.min_spread,
		(weapon.spread * (1 - 0.55 * player.crouch_val) + player.recoil_anim * 240 + player.spread_plus) *
		(1 - player.aim_val + player.aim_val * weapon.aim_spread))
}

PROJECTILE_SPREADS := [?]f32{0.1, -0.8, 0.3, 1, 0.1, -0.4, -0.1, 0.3, 0.5, -0.45, 0.2, -0.2}

player_projectile_angles :: proc(player: ^Player) -> Vec2 {
	pattern := player.weapon.no_projectile_spread ? 0 : PROJECTILE_SPREADS[player.projectile_shot_seq % u32(len(PROJECTILE_SPREADS))]
	spread := (player.spread + player.weapon.inaccuracy) * GAME_CONSTANTS.spread_adjustment * pattern
	return player.direction + Vec2{player.recoil_anim_y * GAME_CONSTANTS.recoil_mlt + spread, spread}
}

player_hitscan_angles :: proc(player: ^Player, pellet: i32) -> Vec2 {
	angles := player.direction
	if pellet >= 0 {
		weapon := player.weapon
		ammo := player.ammo[player.loadout_index]
		seed := u64(ammo) + u64(pellet)
		if len(weapon.custom_spread) > 0 {
			// The browser alternates its two shotgun patterns with ammo % 2.
			// Only complete configured patterns participate; short patterns repeat
			// safely, including unlimited ammo and enlarged custom magazines.
			shots := int(max(weapon.shots, 1))
			patterns := max(1, len(weapon.custom_spread) / shots)
			index := (int(ammo % u32(patterns)) * shots + int(pellet)) % len(weapon.custom_spread)
			spread := weapon.custom_spread[index]
			scale := spread_random(seed, 0.3, 0.32)
			angles += Vec2{spread.y, spread.x} * scale
		} else {
			spread := (player.spread + weapon.inaccuracy) * GAME_CONSTANTS.spread_adjustment
			angles += Vec2{spread_random(seed + 1, -spread, spread), spread_random(seed, -spread, spread)}
		}
	}
	angles.x += player.recoil_anim_y * GAME_CONSTANTS.recoil_mlt
	return angles
}

// The browser uses a fixed ARC4("KRUNKER") lookup, indexed by remaining
// ammo + pellet. Matching it keeps prediction independent of global RNG calls.
spread_random :: proc(seed: u64, low, high: f32) -> f32 {
	return SPREAD_RANDOM_TABLE[seed % u64(len(SPREAD_RANDOM_TABLE))] * (high - low) + low
}

Spread_RNG :: struct {
	s: [256]u32,
	i, j: u32,
}

spread_rng_bytes :: proc "contextless" (rng: ^Spread_RNG, count: int) -> f64 {
	value: f64
	for _ in 0 ..< count {
		rng.i = (rng.i + 1) & 255
		t := rng.s[rng.i]
		// Preserve the browser generator's assignment order.
		rng.s[rng.j] = t
		rng.j = (rng.j + t) & 255
		rng.s[rng.i] = rng.s[rng.j]
		value = value * 256 + f64(rng.s[(rng.s[rng.i] + t) & 255])
	}
	return value
}

spread_random_table :: proc "contextless" () -> (table: [1000]f32) {
	rng: Spread_RNG
	seed := "KRUNKER"
	for i in 0 ..< 256 { rng.s[i] = u32(i) }
	j: u32
	for i in 0 ..< 256 {
		t := rng.s[i]
		j = (j + u32(seed[i % len(seed)]) + t) & 255
		rng.s[i] = rng.s[j]
		rng.s[j] = t
	}
	spread_rng_bytes(&rng, 256)
	for &value in table {
		n := spread_rng_bytes(&rng, 6)
		d: f64 = 281474976710656 // 2^48
		x: f64
		for n < 4503599627370496 { // 2^52
			n = 256 * (n + x)
			d *= 256
			x = spread_rng_bytes(&rng, 1)
		}
		for n >= 9007199254740992 { // 2^53
			n /= 2
			d /= 2
			x = f64(u32(x) >> 1)
		}
		value = f32((n + x) / d)
	}
	return
}

SPREAD_RANDOM_TABLE := spread_random_table()
