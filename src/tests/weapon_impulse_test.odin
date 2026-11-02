package main

import "core:fmt"
import "core:math"
import "core:os"
import shared "../shared"

test_weapon_impulses :: proc() -> bool {
	config := shared.config_load_gameplay()
	defer shared.config_destroy_gameplay(config)
	map_inst := shared.Map{death_y = -1000}
	floor := shared.Object{active = true, collision_type = .BOX, position = {0, -10, 0}, scale = {100, 10, 100}}
	append(&map_inst.objects, &floor)
	defer delete(map_inst.objects)
	game: shared.Game
	shared.game_configure(&game, &config.game, []^shared.Map{&map_inst}, nil, config.weapons, config.classes)
	shared.game_init(&game, 0, 0, true)
	defer shared.game_destroy(&game)
	player := shared.player_init(&game)
	shared.game_players_add(&game, player)
	for weapon_id in ([]i32{5, 8, 15}) {
		shared.player_spawn(player, 4)
		player.loadout[0] = weapon_id
		player.weapon = game.weapons[weapon_id]
		player.ammo[0] = player.weapon.ammo
		player.position = {0, 0, 0}
		player.direction = {-math.PI/2, 0}
		player.velocity = {0.02, 0, 0.03}
		player.on_ground = true
		game.config.impulse_mlt = 1.5
		weapon := player.weapon
		if weapon.physical_power <= 0 || weapon.physical_range <= 0 { return false }
		// A predicted shot must move the shooter even though damage is server-owned.
		shared.player_shoot(player, true)
		distance := player.height - shared.GAME_CONSTANTS.camera_height
		expected := weapon.physical_power * (1-distance/weapon.physical_range) * 1.5
		if player.on_ground || abs(player.velocity.y-expected) > 1e-6 ||
			abs(player.velocity.x-0.02) > 1e-6 || abs(player.velocity.z-0.03) > 1e-6 ||
			len(game.impacts) != int(max(weapon.shots, 1)) {
			fmt.eprintf("Weapon %d ground boost mismatch: velocity=%v expected_y=%f\n", weapon_id, player.velocity, expected)
			return false
		}
		clear(&game.impacts)
		player.recoil_anim_y = 0
		player.position.y = 10
		player.velocity = {}
		player.unlimited_ammo = true
		shared.player_shoot(player, true)
		if player.velocity.y <= 0 || player.velocity.y >= expected {
			fmt.eprintln("Surface boost must decay with distance")
			return false
		}
		clear(&game.impacts)
		player.recoil_anim_y = 0
		player.position.y = weapon.physical_range + 100
		player.velocity = {}
		shared.player_shoot(player, true)
		if player.velocity != (shared.Vec3{}) { return false }
		clear(&game.impacts)
		player.position.y = 0
		for flag in 0..<4 {
			floor.no_impulse, floor.no_player_collision, floor.no_shoot = flag == 0, flag == 1, flag == 2
			game.config.impulse_mlt = flag == 3 ? 0 : 1
			player.velocity = {}
			player.on_ground = true
			shared.player_shoot(player, true)
			if player.velocity != (shared.Vec3{}) || !player.on_ground {
				fmt.eprintln("Disabled impulse surfaces/settings must not boost")
				return false
			}
			clear(&game.impacts)
		}
		floor.no_impulse, floor.no_player_collision, floor.no_shoot = false, false, false
		game.config.impulse_mlt = 1

		// Exercise the same queued command path used by offline play and the server.
		shared.player_spawn(player, 4)
		player.loadout[0], player.weapon = weapon_id, game.weapons[weapon_id]
		player.ammo[0] = player.weapon.ammo
		player.position, player.velocity = {}, {}
		player.on_ground, player.swap_timer = true, 0
		command := shared.Input{delta = PHYSICS_DT, move_dir = -1, shoot = true, x_dir = -math.PI/2}
		shared.player_queue_input(player, &command)
		shared.game_tick(&game, 0, PHYSICS_DT)
		if player.velocity.y <= 0 || player.on_ground {
			fmt.eprintf("Weapon %d must boost through authoritative queued input\n", weapon_id)
			return false
		}
		clear(&game.impacts)
	}

	// Configured projectile weapons must boost without adding hitscan damage.
	shared.player_spawn(player, 4)
	projectile_weapon := game.weapons[8]^
	projectile_weapon.projectile = true
	projectile_weapon.projectile_speed, projectile_weapon.projectile_range = 100, 200
	player.loadout[0], player.weapon = 8, &projectile_weapon
	player.ammo[0] = projectile_weapon.ammo
	player.position, player.velocity = {}, {}
	player.direction = {-math.PI/2, 0}
	shared.player_shoot(player, true)
	if player.velocity.y <= 0 || len(game.projectiles) != 1 || len(game.impacts) != 0 {
		fmt.eprintln("Projectile surface boosts must not emit an extra hitscan shot")
		return false
	}
	clear(&game.projectiles)

	// Horizontal wall pushes must be additive and opposite the shot, not its normal.
	shared.player_spawn(player, 4)
	player.position, player.direction = {}, {}
	player.velocity = {0.03, 0.02, -0.01}
	floor.position, floor.scale = {0, 0, -10}, {100, 100, 2}
	shared.player_shoot(player, true)
	expected_z := f32(-0.01) + f32(0.09)*(1-f32(9)/35)
	if abs(player.velocity.z-expected_z) > 1e-6 || abs(player.velocity.y-0.02) > 1e-6 { return false }
	clear(&game.impacts)
	// The nearest surface blocks the probe even when boosting off it is disabled.
	wall := shared.Object{active = true, no_impulse = true, collision_type = .BOX, position = {0, 0, -5}, scale = {100, 100, 1}}
	append(&map_inst.objects, &wall)
	player.velocity, player.recoil_anim_y = {}, 0
	shared.player_shoot(player, true)
	if player.velocity != (shared.Vec3{}) { return false }
	clear(&game.impacts)
	clear(&map_inst.objects)

	// Players are excluded from the physical probe: five pellets, never six.
	target := shared.player_init(&game)
	shared.game_players_add(&game, target)
	shared.player_spawn(target, 0)
	target.team, player.team = 0, 0
	target.position, target.height, target.scale = {0, -50, -20}, 100, 50
	target.health = 10000
	player.velocity, player.recoil_anim_y = {}, 0
	player.ammo[0] = 2
	shared.player_shoot(player)
	with_probe_damage := 10000 - target.health
	target.health = 10000
	player.recoil_anim_y = 0
	player.ammo[0] = 2
	no_probe := player.weapon^
	no_probe.physical_power = 0
	player.weapon = &no_probe
	shared.player_shoot(player)
	if with_probe_damage <= 0 || abs(with_probe_damage-(10000-target.health)) > 1e-4 || player.velocity != (shared.Vec3{}) {
		fmt.eprintln("Impulse probes must not hit players or duplicate shotgun damage")
		return false
	}
	fmt.println("Shotgun/Sawed Off/RPG boost direction, distance falloff, surface flags, multiplier and damage isolation OK")
	return true
}

test_weapon_impulse_map_flags :: proc() -> bool {
	path := fmt.tprintf("%sbin/weapon_impulse_flags_test.json", project_root())
	fixture := `{"spawns":[],"objects":[
		{"p":[0,0,0],"s":[10,10,10],"ns":0,"ip":false,"pl":0},
		{"p":[0,0,0],"s":[10,10,10],"ns":null,"ip":null,"pl":null},
		{"p":[0,0,0],"s":[10,10,10]}
	]}`
	if os.write_entire_file(path, transmute([]u8)fixture) != nil { return false }
	defer os.remove(path)
	map_inst, loaded := shared.map_load_from_file(path)
	if !loaded { return false }
	defer shared.map_destroy(map_inst)
	if len(map_inst.objects) != 3 { return false }
	for object, index in map_inst.objects {
		expected := index == 0
		if object.no_shoot != expected || object.no_impulse != expected || object.no_player_collision != expected {
			fmt.eprintln("Surface impulse flags must use presence/non-null semantics, including zero/false values")
			return false
		}
	}
	return true
}
