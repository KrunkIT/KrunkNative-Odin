package main

import "core:fmt"
import "core:math"
import shared "../shared"

test_trooper_blaster :: proc() -> bool {
	config := shared.config_load_gameplay()
	defer shared.config_destroy_gameplay(config)
	if shared.weapon_config_index("blaster") != 18 || len(config.weapons) <= 18 || config.weapons[18] == nil ||
		config.weapons[18].src != "weapon_19" || config.weapons[18].icon != "icon_19" || config.weapons[13] == nil || config.weapons[17] != nil { return false }
	map_inst := shared.Map{death_y = -1000}
	game: shared.Game
	maps := []^shared.Map{&map_inst}
	shared.game_configure(&game, &config.game, maps, nil, config.weapons, config.classes)
	shared.game_init(&game, 0, 0, true)
	defer shared.game_destroy(&game)
	shooter := shared.player_init(&game)
	target := shared.player_init(&game)
	shooter.uid = 1
	target.uid = 2
	shared.game_players_add(&game, shooter)
	shared.game_players_add(&game, target)
	shared.player_spawn(shooter, 13)
	shared.player_spawn(target, 0)
	if shooter.weapon != game.weapons[18] || shooter.loadout_size != 2 || shooter.loadout[0] != 18 || shooter.loadout[1] != 12 || shooter.ammo[0] != 16 {
		fmt.eprintln("Trooper must spawn with Blaster and knife")
		return false
	}
	shooter.position = {0, 0, 0}
	shooter.direction = {0, -math.PI / 2}
	shooter.swap_timer = 0
	// Aim the collision fixture so hip-fire accuracy does not miss the target.
	shooter.aim_val = 1
	target.position = {100, 0, 0}
	input := shared.Input{delta = 0.001, move_dir = -1, y_dir = shooter.direction.y, shoot = true, scope = true}
	shared.player_proc_input(shooter, &input, false, false)
	if shooter.ammo[0] != 15 || shooter.shot_seq != 1 || len(game.projectiles) != 1 || len(game.impacts) != 0 || target.health != 100 {
		fmt.eprintln("Blaster must emit a bolt instead of instant hitscan damage")
		return false
	}
	shared.game_tick_projectiles(&game, 0.05)
	if len(game.projectiles) != 1 || target.health != 100 { return false }
	shared.game_tick_projectiles(&game, 0.05)
	if len(game.projectiles) != 0 || target.health != 55 {
		fmt.eprintln("Blaster bolt travel/damage test failed")
		return false
	}

	// A large tick must still collide with a thin wall before reaching a player.
	wall := shared.Object{active = true, collision_type = .BOX, position = {50, 0, 0}, scale = {0.2, 100, 100}}
	append(&map_inst.objects, &wall)
	defer delete(map_inst.objects)
	target.health = 100
	shared.projectile_spawn(shooter, {0, -math.PI / 2})
	shared.game_tick_projectiles(&game, 0.2)
	if len(game.projectiles) != 0 || target.health != 100 { return false }
	wall.active = false

	// Beyond 500 units the bolt expires, and teammates are protected.
	target.position.x = 600
	shared.projectile_spawn(shooter, {0, -math.PI / 2})
	shared.game_tick_projectiles(&game, 1)
	if len(game.projectiles) != 0 || target.health != 100 { return false }
	target.position.x = 100
	shooter.team = 1
	target.team = 1
	game.mode.config.dmg_team = false
	shared.projectile_spawn(shooter, {0, -math.PI / 2})
	shared.game_tick_projectiles(&game, 0.6)
	if target.health != 100 { return false }
	shooter.team = 0
	target.team = 0

	// Predicted bolts may collide visually but cannot modify authoritative HP.
	game.is_local = false
	shared.projectile_spawn(shooter, {0, -math.PI / 2})
	shared.game_tick_projectiles(&game, 0.2)
	if len(game.projectiles) != 0 || target.health != 100 { return false }
	game.is_local = true
	shared.projectile_spawn(shooter, {0, -math.PI / 2})
	shared.game_players_remove(&game, shooter)
	shared.game_tick_projectiles(&game, 0.01)
	if len(game.projectiles) != 0 { return false }
	shared.game_players_add(&game, shooter)

	shared.player_spawn(shooter, 13)
	shooter.swap_timer = 0
	shooter.ammo[0] = 0
	shared.player_reload(shooter)
	if shooter.reload_timer <= 0 { return false }
	input = {delta = 0.01, move_dir = -1}
	for _ in 0 ..< 200 { shared.player_proc_input(shooter, &input, false, false) }
	if shooter.ammo[0] != 16 {
		fmt.eprintln("Blaster reload must refill its 16-round magazine")
		return false
	}
	shared.player_swap_weapon(shooter, 1, true, true, true)
	if !shooter.weapon.melee { return false }
	shared.player_swap_weapon(shooter, 0, true, true, true)
	if shooter.weapon != game.weapons[18] { return false }
	fmt.println("Trooper Blaster loadout, reload, bolts, collision, range and authority tests OK")
	return true
}
