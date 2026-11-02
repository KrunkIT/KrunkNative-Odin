package main

import "core:fmt"
import "core:math"
import shared "../shared"

test_weapon_spread :: proc() -> bool {
	config := shared.config_load_gameplay()
	defer shared.config_destroy_gameplay(config)
	map_inst := shared.Map{death_y = -1000, config = {speed = {1, 1, 1}, air_accel = 1}}
	game: shared.Game
	shared.game_configure(&game, &config.game, []^shared.Map{&map_inst}, nil, config.weapons, config.classes)
	shared.game_init(&game, 0, 0, true)
	defer shared.game_destroy(&game)
	player := shared.player_init(&game)
	shared.game_players_add(&game, player)
	shared.player_spawn(player, 0)
	weapon := player.weapon
	if abs(player.spread - weapon.spread) > EPSILON {
		fmt.eprintln("Standing hip fire must initialize with the weapon's base spread")
		return false
	}
	player.crouch_val = 1
	shared.player_update_spread(player, 0, 0, 0)
	if abs(player.spread - weapon.spread * 0.45) > EPSILON { return false }
	player.crouch_val = 0
	shared.player_update_spread(player, 2, -3, 0.01)
	expected_plus := f32(140) * math.pow(f32(0.985), f32(10))
	if abs(player.spread_plus - expected_plus) > EPSILON || abs(player.spread - weapon.spread - expected_plus) > EPSILON {
		fmt.eprintln("Movement and vertical displacement must add decaying spread")
		return false
	}
	shared.player_update_spread(player, 0, 0, 0.01)
	if player.spread_plus >= expected_plus { return false }
	player.spread_plus = 0
	player.recoil_anim = 0.2
	shared.player_update_spread(player, 0, 0, 0)
	if abs(player.spread - weapon.spread - 48) > EPSILON { return false }
	player.aim_val = 1
	shared.player_update_spread(player, 0, 0, 0)
	if player.spread != weapon.min_spread { return false }
	weapon.aim_spread = 0.2
	shared.player_update_spread(player, 0, 0, 0)
	if abs(player.spread - (weapon.spread + 48) * 0.2) > EPSILON { return false }
	weapon.aim_spread = 0
	weapon.no_spread = true
	shared.player_update_spread(player, 100, 100, 0)
	if player.spread != 0 { return false }
	weapon.no_spread = false
	shared.player_spawn(player, 0)
	if player.spread_plus != 0 || player.spread != weapon.spread { return false }

	// Reconciliation still updates accuracy from replayed movement, without firing.
	player.noclip = true
	input := shared.Input{delta = 0.01, move_dir = 0, shoot = true}
	shared.player_proc_input(player, &input, true, false)
	if player.spread_plus <= 0 || player.shot_seq != 0 {
		fmt.eprintln("Movement replay must update spread without duplicating a shot")
		return false
	}
	player.noclip = false

	// Browser's seeded lookup makes spread independent of recoil/global RNG.
	if abs(shared.spread_random(0, 0, 1) - 0.9632385264) > 1e-6 ||
		abs(shared.spread_random(1, 0, 1) - 0.2745588900) > 1e-6 ||
		shared.spread_random(1000, 0, 1) != shared.spread_random(0, 0, 1) { return false }
	player.direction = {0, 0}
	player.recoil_anim_y = 0
	player.spread = 100
	player.ammo[0] = 15
	first_angles := shared.player_hitscan_angles(player, 0)
	player.spread = 5
	aim_angles := shared.player_hitscan_angles(player, 0)
	if abs(first_angles.x - aim_angles.x * 20) > EPSILON || abs(first_angles.y - aim_angles.y * 20) > EPSILON ||
		first_angles == (shared.Vec2{}) || aim_angles != shared.player_hitscan_angles(player, 0) { return false }
	player.recoil_anim_y = 0.1
	physical_angles := shared.player_hitscan_angles(player, -1)
	if physical_angles != (shared.Vec2{0.1 * shared.GAME_CONSTANTS.recoil_mlt, 0}) { return false }

	// Both magazine patterns survive larger/unlimited ammo and short overrides.
	shared.player_spawn(player, 4)
	player.direction = {}
	player.recoil_anim_y = 0
	ammo_counts := [?]u32{0, 1, 2, 31, 32, max(u32)}
	for ammo in ammo_counts {
		player.ammo[0] = ammo
		for pellet in 0 ..< 5 {
			angles := shared.player_hitscan_angles(player, i32(pellet))
			point := player.weapon.custom_spread[int(ammo % 2) * 5 + pellet]
			scale := shared.spread_random(u64(ammo) + u64(pellet), 0.3, 0.32)
			if angles != (shared.Vec2{point.y, point.x} * scale) { return false }
		}
	}
	short_pattern := [?]shared.Vec2{{0.1, -0.2}}
	player.weapon.custom_spread = short_pattern[:]
	player.unlimited_ammo = true
	player.ammo[0] = 2
	shared.player_shoot(player)
	if player.ammo[0] != 2 || len(game.impacts) != 5 { return false }
	clear(&game.impacts)

	// Projectiles use their own deterministic twelve-shot sequence, and can opt out.
	shared.player_spawn(player, 13)
	player.direction = {}
	player.spread = 100
	player.recoil_anim_y = 0
	for shot in 1 ..= 24 {
		player.projectile_shot_seq = u32(shot)
		angles := shared.player_projectile_angles(player)
		expected := f32(100) * shared.GAME_CONSTANTS.spread_adjustment * shared.PROJECTILE_SPREADS[shot % 12]
		if angles != (shared.Vec2{expected, expected}) { return false }
	}
	player.weapon.no_projectile_spread = true
	if shared.player_projectile_angles(player) != (shared.Vec2{}) { return false }
	player.weapon.no_projectile_spread = false
	player.unlimited_ammo = false
	shared.player_shoot(player)
	if len(game.projectiles) != 1 || game.projectiles[0].direction.x == 0 || game.projectiles[0].direction.y == 0 { return false }
	if shared.WEAPON_AKIMBO.move_spread != 0.01 || shared.WEAPON_AK47.move_spread != 1 { return false }
	fmt.println("Weapon spread: hip/aim/crouch, movement/fall recovery, recoil, seeded pellets, safe shotgun patterns and projectile cycle OK")
	return true
}
