package shared

import "core:math"
import "core:math/rand"

player_init :: proc(game: ^Game) -> ^Player {
	player := new(Player)
	player.game = game
	player.slid_cont = 1
	player.scale = GAME_CONSTANTS.player_scale
	return player
}

player_update_height :: proc(player: ^Player) {
	player.height = GAME_CONSTANTS.player_height - player.crouch_val * GAME_CONSTANTS.crouch_distance
}

player_spawn :: proc(player: ^Player, class_index: i32 = 0) {
	player.active = true
	player.class_index = class_index
	player.respawn_timer = 0
	player.last_damage_time = -1000

	if player.team == 0 && player.game != nil && player.game.mode != nil && player.game.mode.config.teams {
		team_counts: [3]i32
		for other in player.game.players {
			if other != player && other.team > 0 && other.team < len(team_counts) {
				team_counts[other.team] += 1
			}
		}
		player.team = team_counts[1] <= team_counts[2] ? 1 : 2
	}

	// Resolve stats from the configured classes when available (the game's list
	// is built from game.toml by the client/server), falling back to defaults.
	class: Class_Config
	if player.game != nil && class_index >= 0 && class_index < i32(len(player.game.classes)) {
		class = player.game.classes[class_index]
	} else if class_index >= 0 && class_index < i32(len(CLASSES_LIST)) {
		class = CLASSES_LIST[class_index]
	} else {
		class = CLASSES_LIST[0]
	}

	player.speed = class.speed
	player.health = f32(class.health)
	player.max_health = class.health

	weapons := player.game.weapons if player.game != nil && len(player.game.weapons) > 0 else g_weapons()

	// Build the full loadout: the class's configured primary weapons, plus the
	// sidearm (when the class has one) and the melee knife. The C port shipped a
	// fixed [primary, pistol, knife] loadout; deriving it from the class keeps
	// weapon switching (Q/E) working for every class.
	composed: [dynamic]i32
	defer delete(composed)

	for weapon_id in class.loadout {
		if weapon_id >= 0 && weapon_id < i32(len(weapons)) {
			append(&composed, weapon_id)
		}
	}

	has_secondary := false
	has_melee := false
	for weapon_id in composed {
		if int(weapon_id) < len(weapons) {
			if weapons[weapon_id].secondary {
				has_secondary = true
			}
			if weapons[weapon_id].melee {
				has_melee = true
			}
		}
	}

	if class.secondary && !has_secondary {
		// Pistol is the default sidearm (index 2 in the weapon registry).
		if 2 < len(weapons) {
			append(&composed, 2)
		}
	}

	if !has_melee {
		// Combat Knife is the default melee (index 12 in the weapon registry).
		if 12 < len(weapons) {
			append(&composed, 12)
		}
	}

	delete(player.loadout)
	delete(player.ammo)
	delete(player.reloads)
	clear(&player.input_queue)

	player.loadout_size = i32(len(composed))
	player.loadout = make([]i32, player.loadout_size)
	player.ammo = make([]u32, player.loadout_size)
	player.reloads = make([]f32, player.loadout_size)
	copy(player.loadout, composed[:])

	if player.game != nil && player.game.map_inst != nil {
		for i in 0 ..< player.loadout_size {
			player.ammo[i] = weapons[player.loadout[i]].ammo
		}
	}

	player.velocity = Vec3{0, 0, 0}
	player.crouch_val = 0.0
	player.aim_val = 0.0
	player.recoil = {}
	player.recoil_force = 0.0
	player.recoil_anim = 0.0
	player.recoil_anim_y = 0.0

	player.on_ground = true
	player.on_wall = 0
	player.on_terrain = false
	player.on_ladder = false

	player.can_slide = true
	player.can_throw = true

	player.did_jump = false
	player.did_wall_jump = false
	player.did_act = false

	player.air_time = 0.0
	player.covered_distance = 0.0
	player.aim_time = 0.0

	player.swap_timer = 0.0
	player.slide_timer = 0.0
	player.jump_timer = 0.0
	player.reload_timer = 0.0

	player_update_height(player)
	player_swap_weapon(player, 0, true, false, false)

	if player.game != nil && player.game.map_inst != nil && len(player.game.map_inst.spawns) > 0 {
		eligible: [dynamic]^Spawn
		defer delete(eligible)
		for spawn in player.game.map_inst.spawns {
			if player.team != 0 && spawn.team != 0 && spawn.team != player.team {
				continue
			}
			occupied := false
			for other in player.game.players {
				if other != player && other.active {
					dx := other.position.x - spawn.position.x
					dz := other.position.z - spawn.position.z
					if dx * dx + dz * dz < 100.0 {
						occupied = true
						break
					}
				}
			}
			if !occupied {
				append(&eligible, spawn)
			}
		}
		spawn := player.game.map_inst.spawns[rand.int_max(len(player.game.map_inst.spawns))]
		if len(eligible) > 0 {
			spawn = eligible[rand.int_max(len(eligible))]
		}

		player.position = spawn.position
		player.direction.x = 0.0
		player.direction.y = -math.PI / 2.0 * (1.0 + f32(spawn.direction))
	}
}

player_kill :: proc(player: ^Player, killer: ^Player, kill_info: ^Player_Kill_Info, skip_rewards: bool) {
	if !player.active {
		return
	}

	player.active = false
	player.health = 0
	player.velocity = {}
	player.deaths += 1
	player.death_streak += 1
	clear(&player.input_queue)
	if player.game != nil {
		player.respawn_timer = max(0.0, player.game.config.respawn_delay)
	}

	if killer != nil && killer != player {
		killer.kills += 1
		killer.death_streak = 0
		if !skip_rewards && killer.game != nil && killer.game.config.kill_rewards {
			killer.score += 100
		}
	}
}

player_apply_damage :: proc(victim, attacker: ^Player, amount: f32, weapon_id: i32, headshot: bool) -> bool {
	if victim == nil || !victim.active || victim.god_mode || amount <= 0 {
		return false
	}
	if attacker != nil && attacker != victim && victim.team != 0 && victim.team == attacker.team && !victim.game.mode.config.dmg_team {
		return false
	}

	final_damage := amount
	if attacker != nil && attacker.team == 1 {
		final_damage *= victim.game.config.team1_damage
	} else if attacker != nil && attacker.team == 2 {
		final_damage *= victim.game.config.team2_damage
	}

	victim.health = max(0.0, victim.health - final_damage)
	victim.last_damage_time = victim.game.now
	if victim.health == 0 {
		info := Player_Kill_Info{weapon_id = weapon_id}
		player_kill(victim, attacker, &info, false)
	}
	return true
}

player_queue_input :: proc(player: ^Player, input: ^Input) {
	append(&player.input_queue, input^)
}

player_reset_step :: proc(player: ^Player, recon: bool) {
	if !player.game.config.can_slide || player.game.mode.config.real_movement || player.crouch_val == 0 || !player.can_slide {
		return
	}

	player.can_slide = false

	player.slide_timer = GAME_CONSTANTS.slide_time *
		player.game.config.slide_time *
		player.game.map_inst.config.slide_time *
		player.crouch_val

	slide_mlt := (player.on_terrain ? GAME_CONSTANTS.player_terrain_slide_velocity_mlt : GAME_CONSTANTS.player_slide_velocity_mlt) * player.game.map_inst.config.slide_accel

	player.velocity.x *= slide_mlt
	player.velocity.z *= slide_mlt
}

player_collides :: proc(player: ^Player, object: ^Object, pad: f32) -> bool {
	switch object.collision_type {
	case .NONE:
		return false
	case .BOX:
		border := 0.0 if (player.game.config.disable_borders || !object.is_border) else GAME_CONSTANTS.border_height

		in_x := player.position.x + player.scale > object.position.x - (object.scale.x * 0.5 + pad) && player.position.x - player.scale < object.position.x + (object.scale.x * 0.5 + pad)
		in_z := player.position.z + player.scale > object.position.z - (object.scale.z * 0.5 + pad) && player.position.z - player.scale < object.position.z + (object.scale.z * 0.5 + pad)
		in_y := player.position.y + player.height >= object.position.y && player.position.y <= object.position.y + object.scale.y + border

		return in_x && in_y && in_z
	case .CYLINDER:
		border := 0.0 if (player.game.config.disable_borders || !object.is_border) else GAME_CONSTANTS.border_height

		in_y := player.position.y + player.height > object.position.y && player.position.y < object.position.y + object.scale.y + border
		dist := math.sqrt((player.position.x - object.position.x) * (player.position.x - object.position.x) + (player.position.z - object.position.z) * (player.position.z - object.position.z))

		return in_y && dist <= object.scale.x * 0.5 + player.scale + pad
	}

	return false
}

player_do_map_collisions :: proc(player: ^Player, input: ^Input, move_dir: f32, can_jump: bool, delta: f32, recon: bool) {
	max_ramp_height: ^f32

	for obj in player.game.map_inst.objects {
		collides_padded := player_collides(player, obj, GAME_CONSTANTS.collision_padding)

		if !obj.active || !collides_padded {
			continue
		}

		collides := player_collides(player, obj, 0.0)

		if obj.jump_pad {
			bounce_vel := obj.bounce * 0.1 * (player.crouch_val == 1.0 && obj.crouch ? 0.5 : 1.0)

			player.velocity.y = bounce_vel
			player.on_ground = false
		} else if obj.score_zone {
			// TODO: score
		} else if !obj.objective && !obj.bomb_site && !obj.premium && !obj.verified && (!obj.team_zone || player.game.mode.config.teams && obj.team != u32(player.team)) {
			if obj.teleporter {
				continue
			}

			if obj.checkpoint {
				continue
			}

			if obj.pickup {
				continue
			}

			if obj.flag {
				continue
			}

			if obj.trigger {
				continue
			}

			if obj.kill && !player.god_mode {
				player_kill(player, nil, nil, false)
				continue
			}

			if obj.ladder {
				if player.position.y >= obj.position.y + obj.scale.y || player.crouch_val != 0 {
					continue
				}

				player.velocity.y = 0.0
				player.on_ladder = true
				player.on_terrain = false

				if input.move_dir >= 0 {
					ladder_dir := math.PI * 0.5 * f32(obj.direction)
					dir := (math.abs(normalize_angle(ladder_dir - (move_dir - player.direction.y))) - math.PI * 0.5) / (math.PI * 0.5)

					if dir > 0.0 {
						player.position.y += GAME_CONSTANTS.ladder_speed * player.game.map_inst.config.ladder_accel * player.weapon.speed_mlt * dir * delta
						player.position.y = clamp(player.position.y, obj.position.y, obj.position.y + obj.scale.y)
					}
				}

				continue
			}

			if obj.ramp == nil && obj.collision_type != .CYLINDER && !can_jump && obj.position.y + obj.scale.y - player.position.y > GAME_CONSTANTS.climb_height && obj.wall_jumpable {
				if player.last_position.x - player.scale >= obj.position.x + obj.scale.x * 0.5 - GAME_CONSTANTS.collision_padding {
					player.on_wall = 1
				} else if player.last_position.x + player.scale <= obj.position.x - obj.scale.x * 0.5 + GAME_CONSTANTS.collision_padding {
					player.on_wall = 2
				} else if player.last_position.z - player.scale >= obj.position.z + obj.scale.z * 0.5 - GAME_CONSTANTS.collision_padding {
					player.on_wall = 3
				} else if player.last_position.z + player.scale <= obj.position.z - obj.scale.z * 0.5 + GAME_CONSTANTS.collision_padding {
					player.on_wall = 4
				}
			}

			if !collides {
				continue
			}

			if obj.ramp != nil {
				if player.position.y >= obj.position.y + obj.scale.y {
					continue
				}

				ramp_direction := math.PI * 0.5 * f32(obj.direction)
				player_dir := Vec2{player.position.x + player.scale * math.cos(ramp_direction), player.position.z + player.scale * math.sin(ramp_direction)}

				progress := clamp(progress_on_line(obj.ramp.start, obj.ramp.end, player_dir), 0.0, 1.0)
				collision_height := obj.position.y + (obj.scale.y + 0.01) * progress

				if max_ramp_height == nil {
					max_ramp_height = new(f32)
					max_ramp_height^ = collision_height
				}

				if (player.position.y <= collision_height || can_jump) && (max_ramp_height == nil || max_ramp_height^ <= collision_height) {
					if max_ramp_height != nil {
						max_ramp_height^ = collision_height
					}

					if obj.ramp.boost != 0 {
						player.position.y = collision_height

						boost_velocity := obj.ramp.boost * GAME_CONSTANTS.booster_speed * delta
						boost_direction := math.asin(obj.scale.y / math.sqrt(obj.scale.y * obj.scale.y + obj.scale.z * obj.scale.z))

						player.velocity.x += boost_velocity * math.sin(-ramp_direction + math.PI * 0.5) * math.cos(boost_direction)
						player.velocity.z += boost_velocity * math.cos(-ramp_direction + math.PI * 0.5) * math.cos(boost_direction)
						player.velocity.y += boost_velocity * math.sin(boost_direction)
					} else {
						if player.last_position.y > player.position.y {
							player_reset_step(player, recon)
						}

						player.position.y = collision_height
						player.velocity.y = 0.0
						player.on_wall = 0
						player.on_ground = true
						player.on_terrain = false

						if player.ramp_fix == nil {
							player.ramp_fix = new(f32)
						}

						if player.ramp_fix != nil {
							player.on_ramp = true
							player.ramp_fix^ = obj.position.y + obj.scale.y * math.round(progress)
						}
					}
				}

				continue
			}

			if obj.collision_type == .CYLINDER {
				y_collision := true

				if player.last_position.y >= obj.position.y + obj.scale.y {
					player.position.y = obj.position.y + obj.scale.y
					player.velocity.y = 0.0
					player.on_ground = true
					player.on_terrain = false
				} else if player.last_position.y + player.height <= obj.position.y {
					player.position.y = obj.position.y - player.height
					player.velocity.y = 0.0
				} else if player.position.y < obj.position.y + obj.scale.y && obj.position.y + obj.scale.y - player.position.y <= GAME_CONSTANTS.climb_height && player.last_position.y < obj.position.y + obj.scale.y && can_jump {
					player.position.y += (obj.position.y + obj.scale.y - player.position.y) * 0.3
					player.on_ground = true
					player.on_terrain = false
				} else {
					direction := math.atan2(player.position.z - obj.position.z, player.position.x - obj.position.x)

					player.position.x = obj.position.x + (obj.scale.x * 0.5 + player.scale) * math.cos(direction)
					player.position.z = obj.position.z + (obj.scale.x * 0.5 + player.scale) * math.sin(direction)

					y_collision = false
				}

				if y_collision {
					direction := math.atan2(player.position.z - obj.position.z, player.position.x - obj.position.x) - obj.spin * delta * GAME_CONSTANTS.disk_spin
					distance := math.sqrt((player.position.x - obj.position.x) * (player.position.x - obj.position.x) + (player.position.z - obj.position.z) * (player.position.z - obj.position.z))

					old_x := player.position.x
					old_z := player.position.z

					player.position.x = obj.position.x + distance * math.cos(direction)
					player.position.z = obj.position.z + distance * math.sin(direction)

					player.x_vel_cylinder = player.position.x - old_x
					player.z_vel_cylinder = player.position.z - old_z
				}

				continue
			}

			if (!obj.is_border || player.game.config.disable_borders) &&
			   player.position.y < obj.position.y + obj.scale.y &&
			   obj.position.y + obj.scale.y - player.position.y <= GAME_CONSTANTS.climb_height &&
			   player.last_position.y < obj.position.y + obj.scale.y && can_jump {
				player.position.y += delta * 30.0
				player.position.y = min(player.position.y, obj.position.y + obj.scale.y)

				player.on_ground = true
				player.on_terrain = false
			} else if player.last_position.y >= obj.position.y + obj.scale.y + (obj.is_border && !player.game.config.disable_borders ? GAME_CONSTANTS.border_height : 0.0) {
				if player.last_position.y > player.position.y {
					player_reset_step(player, recon)
				}

				player.position.y = obj.position.y + obj.scale.y + (obj.is_border && !player.game.config.disable_borders ? GAME_CONSTANTS.border_height : 0.0)
				player.velocity.y = 0.0
				player.on_ground = true
				player.on_terrain = false
			} else if player.last_position.x - player.scale >= obj.position.x + obj.scale.x * 0.5 - 0.00001 {
				player.position.x = obj.position.x + obj.scale.x * 0.5 + player.scale
				player.velocity.x = 0.0
			} else if player.last_position.x + player.scale <= obj.position.x - obj.scale.x * 0.5 + 0.00001 {
				player.position.x = obj.position.x - obj.scale.x * 0.5 - player.scale
				player.velocity.x = 0.0
			} else if player.last_position.z - player.scale >= obj.position.z + obj.scale.z * 0.5 - 0.00001 {
				player.position.z = obj.position.z + obj.scale.z * 0.5 + player.scale
				player.velocity.z = 0.0
			} else if player.last_position.z + player.scale <= obj.position.z - obj.scale.z * 0.5 + 0.00001 {
				player.position.z = obj.position.z - obj.scale.z * 0.5 - player.scale
				player.velocity.z = 0.0
			} else if player.last_position.y + player.height <= obj.position.y {
				player.position.y = obj.position.y - player.height
				player.velocity.y = 0.0
			}
		}
	}

	if max_ramp_height != nil {
		free(max_ramp_height)
	}
}

player_jump :: proc(player: ^Player) {
	player.did_act = true
	player.jump_timer = (player.terrain_slipping ? GAME_CONSTANTS.player_slipping_jump_cooldown : 0.0) * player.game.map_inst.config.jump_cooldown
	player.did_jump = true
	player.did_wall_jump = true
	player.on_terrain = false

	jump_push := GAME_CONSTANTS.jump_push * player.game.config.jump_mlt
	jump_vel := GAME_CONSTANTS.jump_velocity * player.game.config.jump_mlt * (player.game.mode.config.real_movement ? 0.92 : 1.0)
	vel := math.sqrt(player.velocity.x * player.velocity.x + player.velocity.z * player.velocity.z)

	weapon_jump_mlt := player.weapon.jump_mlt != 0 ? player.weapon.jump_mlt : player.weapon.speed_mlt
	player.velocity.y += jump_vel * (1.0 - GAME_CONSTANTS.crouch_jump * player.crouch_val) * weapon_jump_mlt * (player.aim_val != 1.0 ? 1.0 : GAME_CONSTANTS.jump_aim_slow)

	player.velocity.x -= vel * jump_push * math.sin(player.direction.y)
	player.velocity.z -= vel * jump_push * math.cos(player.direction.y)
}

player_swap_weapon :: proc(player: ^Player, index: i32, force_swap, instant_swap, recon: bool) {
	if player == nil || player.loadout_size <= 0 || index < 0 || index >= player.loadout_size {
		return
	}

	loadout_changed := force_swap || player.loadout_index != index
	player.loadout_index = index

	if !instant_swap && loadout_changed {
		player.reload_timer = 0.0
		player.did_shoot = false
		player.burst_count = 0
	}

	weapons := player.game.weapons if player.game != nil && len(player.game.weapons) > 0 else g_weapons()
	player.weapon = weapons[player.loadout[player.loadout_index]]

	if player.weapon == nil {
		player.weapon = weapons[player.loadout[0]]

		if player.weapon != nil {
			player.loadout_index = 0
			loadout_changed = true
		}
	}

	if !instant_swap && player.weapon != nil {
		if !recon && loadout_changed {
			player.swap_timer = player.weapon.swap_time
		}
	}
}

player_reload :: proc(player: ^Player) {
	if player.reload_timer != 0 || player.ammo[player.loadout_index] >= player.weapon.ammo {
		return
	}

	player.reload_timer = player.weapon.reload_time * player.game.config.reload_speed
	player.burst_count = 0
}

player_apply_recoil :: proc(player: ^Player) {
	if player == nil || player.weapon == nil {
		return
	}

	player.recoil_force += player.weapon.recoil

	rand_recoil := (rand.float32() - 0.5) * 2.0 * math.PI
	player.recoil.x += player.weapon.recoil_r * math.sin(rand_recoil)
	player.recoil.z += player.weapon.recoil_r * 0.3 * math.cos(rand_recoil)
}

player_update_recoil :: proc(player: ^Player, delta: f32) {
	if player == nil || player.weapon == nil {
		return
	}

	delta := min(delta, GAME_CONSTANTS.max_delta)
	if player.recoil_force != 0 {
		player.recoil_anim += player.recoil_force * delta
		player.recoil_anim_y += player.recoil_force * (player.weapon.recoil_y != 0 ? player.weapon.recoil_y : 1.0) * (1.0 - player.crouch_val * 0.3) * delta
		player.recoil_force *= math.pow(player.weapon.recover_f, delta * 1000.0)
	}

	if player.recoil_anim != 0 {
		player.recoil_anim *= math.pow(player.weapon.recover, delta * 1000.0)
	}

	if player.recoil_anim_y != 0 {
		player.recoil_anim_y *= math.pow(player.weapon.recover_y != 0 ? player.weapon.recover_y : player.weapon.recover, delta * 1000.0)
	}
}

player_proc_input :: proc(player: ^Player, input: ^Input, recon, move_lock: bool) {
	delta := min(input.delta, GAME_CONSTANTS.max_delta)
	move_dir := -math.PI / 2.0 + math.PI / 4.0 * f32(input.move_dir)

	if player.noclip {
		player.on_ground = true
	}

	pitch_delta := normalize_angle(input.x_dir - player.direction.x)
	yaw_delta := normalize_angle(input.y_dir - player.direction.y)

	player.direction.x = clamp(input.x_dir, -math.PI / 2.0, math.PI / 2.0)
	player.direction.y = input.y_dir

	if input.swap != 0 && player.loadout_size > 1 {
		swap_secondary := input.swap == 1
		swap_melee := input.swap == 2
		swap_equipment := input.swap == 3

		swap_to: i32 = -1
		weapons := g_weapons()

		for i in 0 ..< player.loadout_size {
			weapon := player.loadout[i]

			if swap_secondary && weapons[weapon].secondary {
				swap_to = i32(i)
				break
			}

			if swap_melee && weapons[weapon].melee {
				swap_to = i32(i)
				break
			}

			if swap_equipment && weapons[weapon].equipment {
				swap_to = i32(i)
				break
			}
		}

		if swap_to >= 0 {
			if player.loadout_index == swap_to {
				swap_to = 0
			}

			player_swap_weapon(player, swap_to, false, false, recon)
		}
	}

	if !recon {
		player_update_recoil(player, delta)
	}

	player.last_position = player.position

	if player.weapon.no_aim && player.aim_val > 0.0 {
		player.aim_val = 0.0
	} else if player.weapon.zoom != 0 && (!player.weapon.no_aim || player.swap_timer > 0.0) {
		can_scope := player.reload_timer <= 0.0 && player.swap_timer <= 0.0 && (!player.weapon.melee || (player.can_throw && player.game.config.throwable_melees))

		if input.scope && player.aim_val < 1.0 && can_scope {
			player.aim_val += 1.0 / player.weapon.aim_speed * delta
			player.aim_val = min(1.0, player.aim_val)
		} else if !can_scope || !input.scope && player.aim_val > 0.0 {
			player.aim_val -= 1.0 / player.weapon.aim_speed * delta
			player.aim_val = max(0.0, player.aim_val)
		}

		if player.aim_val == 1.0 {
			player.aim_time += delta
		} else {
			player.aim_time = 0.0
		}
	}

	if input.crouch && player.crouch_val < 1.0 && !player.on_ladder {
		player.crouch_val = min(1.0, player.crouch_val + GAME_CONSTANTS.crouch_speed * delta)

		if player.on_ground {
			// TODO: bob anim
		} else {
			player.position.y += GAME_CONSTANTS.crouch_speed * delta
		}
	} else if !input.crouch && player.crouch_val > 0.0 {
		player.crouch_val = max(0.0, player.crouch_val - GAME_CONSTANTS.crouch_speed * delta)

		if player.on_ground {
			// TODO: bob anim
		} else {
			player.position.y -= GAME_CONSTANTS.crouch_speed * delta
		}
	}

	player_update_height(player)

	contact := player.on_ground || player.on_ladder

	if !move_lock {
		accel: f32

		if contact {
			accel = (player.terrain_slipping ? GAME_CONSTANTS.slipping_speed : GAME_CONSTANTS.player_speed) * player.speed
		} else {
			accel = GAME_CONSTANTS.air_speed * player.game.map_inst.config.air_accel * (player.game.mode.config.real_movement ? 0.72 : 1.0)
		}

		accel *= player.aim_val == 1.0 ? GAME_CONSTANTS.aim_slow : 1.0
		accel *= player.crouch_val != 0 ? GAME_CONSTANTS.crouch_slow : 1.0
		accel *= player.game.mode.config.speed_mlt[player.team]
		accel *= player.weapon.speed_mlt
		accel *= (player.noclip ? 2.0 : 1.0) * delta

		decel: f32

		if player.on_ladder {
			decel = GAME_CONSTANTS.ladder_decel
		} else if player.terrain_slipping {
			decel = GAME_CONSTANTS.terrain_slip_decel
		} else if player.on_terrain {
			decel = GAME_CONSTANTS.terrain_decel
		} else if player.on_ground {
			decel = GAME_CONSTANTS.ground_decel
		} else {
			decel = GAME_CONSTANTS.air_decel
		}

		if player.crouch_val <= 0.5 {
			player.can_slide = true
		}

		if !player.on_ground || player.crouch_val == 0 {
			player.slide_timer = 0.0
		}

		if player.slide_timer != 0 {
			player.slide_timer = max(0.0, player.slide_timer - delta)

			if player.slide_timer > 0.0 {
				accel *= 0.25
				decel = player.on_terrain ? GAME_CONSTANTS.terrain_slide_decel : GAME_CONSTANTS.slide_decel

				vel := math.sqrt(player.velocity.x * player.velocity.x + player.velocity.z * player.velocity.z)
				dir := math.PI / 2.0 - player.direction.y

				if player.slid_cont != 0 {
					player.velocity.x = vel * math.cos(dir + math.PI)
					player.velocity.z = vel * math.sin(dir + math.PI)
				} else {
					vel_dir := math.atan2(-player.velocity.z, -player.velocity.x)
					angle_delta := normalize_angle(vel_dir - dir) * 0.18

					player.velocity.x = vel * math.cos(vel_dir + math.PI - angle_delta)
					player.velocity.z = vel * math.sin(vel_dir + math.PI - angle_delta)
				}
			}
		}

		player.jump_timer = max(0.0, player.jump_timer - delta)

		if player.jump_timer <= 0.0 && (player.on_ground || player.game.map_inst.config.infinite_jump) {
			if player.did_jump && !input.jump {
				player.did_jump = false
			}

			if input.jump && (!player.did_jump || player.game.config.auto_jump) {
				player_jump(player)
			}
		}

		if !contact {
			wall_mlt: f32 = player.velocity.y < 0.0 && player.wall_jump && player.on_wall != 0 && player.game.config.wall_jump > 0.0 && player.crouch_val != 0 ? 0.3 : 1.0
			player.velocity.y -= delta * GAME_CONSTANTS.gravity * player.game.config.gravity_mlt * wall_mlt
		}

		if input.move_dir >= 0 {
			yaw_origin := player.direction.y

			player.velocity.x += accel * math.cos(move_dir - yaw_origin)
			player.velocity.z += accel * math.sin(move_dir - yaw_origin)

			if player.noclip {
				player.velocity.y += accel * player.direction.x * (input.move_dir > 2 && input.move_dir < 6 ? -1.0 : 1.0)
			}
		}

		if !contact {
			if player.x_vel_cylinder != 0 {
				player.velocity.x += player.x_vel_cylinder * 0.07
				player.x_vel_cylinder = 0.0
			}

			if player.z_vel_cylinder != 0 {
				player.velocity.z += player.z_vel_cylinder * 0.07
				player.z_vel_cylinder = 0.0
			}
		}

		if player.velocity.x != 0 {
			player.position.x += player.velocity.x * player.game.map_inst.config.speed.x * delta * 1000.0
			player.velocity.x *= math.pow(decel, delta * 1000.0)
			player.velocity.x = crop(player.velocity.x, GAME_CONSTANTS.min_decel)
		}

		if player.velocity.y != 0 {
			player.position.y += player.velocity.y * player.game.map_inst.config.speed.y * delta * 1000.0

			if player.noclip {
				player.velocity.y *= math.pow(decel, delta * 1000.0)
			} else if player.velocity.y > 0.0 {
				player.velocity.y -= delta * 0.032
			} else if player.velocity.y < -0.3 {
				player.velocity.y = -0.3
			}
		}

		if player.velocity.z != 0 {
			player.position.z += player.velocity.z * player.game.map_inst.config.speed.z * delta * 1000.0
			player.velocity.z *= math.pow(decel, delta * 1000.0)
			player.velocity.z = crop(player.velocity.z, GAME_CONSTANTS.min_decel)
		}

		can_jump := player.on_ground && !player.did_jump

		player.on_ground = player.noclip
		player.on_ladder = false
		player.on_wall = 0
		player.on_ramp = false

		if !player.noclip {
			player_do_map_collisions(player, input, move_dir, can_jump, delta, recon)
		}

		if !player.did_jump && player.ramp_fix != nil && math.abs(player.position.y - player.ramp_fix^) <= GAME_CONSTANTS.climb_height {
			if !player.on_ramp {
				player.position.y = player.ramp_fix^
				player.on_ground = true
				player.velocity.y = 0.0

				free(player.ramp_fix)
				player.ramp_fix = nil
			}
		} else {
			if player.ramp_fix != nil {
				free(player.ramp_fix)
			}

			player.ramp_fix = nil
		}

		player.air_time = player.on_ground ? 0 : player.air_time + delta
	}

	delta_pos2D := math.sqrt((player.position.x - player.last_position.x) * (player.position.x - player.last_position.x) + (player.position.z - player.last_position.z) * (player.position.z - player.last_position.z))
	player.covered_distance += delta_pos2D

	if !recon && player.game.map_inst.config.model != .SPRITE {
		if input.reload && !player.game.mode.config.no_reloads {
			player_reload(player)
		}

		if player.reload_timer > 0.0 {
			player.reload_timer = max(0.0, player.reload_timer - delta)

			if player.reload_timer == 0 {
				player.did_shoot = false
				player.ammo[player.loadout_index] = player.weapon.ammo
			}
		}

		player.swap_timer = max(0.0, player.swap_timer - delta)

		for i in 0 ..< player.loadout_size {
			player.reloads[i] = max(0.0, player.reloads[i] - delta)
		}

		if player.weapon != nil && !move_lock {
			will_shoot := player.weapon.burst_count != 0 || !player.weapon.no_auto && input.shoot

			if player.did_shoot && !input.shoot {
				player.did_shoot = false
			}

			if !player.did_shoot && input.shoot {
				will_shoot = true
			}

			if will_shoot && player.reloads[player.loadout_index] <= 0.0 && player.swap_timer <= 0.0 && player.reload_timer <= 0.0 {
				if player.weapon.melee {
					player_melee(player)
				} else {
					if player.ammo[player.loadout_index] > 0 {
						player_shoot(player)
					} else if !player.game.mode.config.no_reloads {
						player_reload(player)
					}
				}
			}
		}
	}

	if !move_lock && player.wall_jump && !player.on_ground && !player.on_ladder && player.on_wall != 0 && player.game.config.wall_jump > 0.0 {
		if player.did_wall_jump && !input.jump {
			player.did_wall_jump = false
		}

		if !player.did_wall_jump && input.jump {
			player.did_wall_jump = true

			velocity: f32 = (player.game.mode.config.real_movement ? 0.7 : 1.0) * 0.03
			player.velocity.y = (player.game.mode.config.real_movement ? 0.9 : 1.0) * 0.058

			switch player.on_wall {
			case 1:
				player.velocity.x = velocity * player.game.config.wall_jump
			case 2:
				player.velocity.x = -velocity * player.game.config.wall_jump
			case 3:
				player.velocity.z = velocity * player.game.config.wall_jump
			case 4:
				player.velocity.z = -velocity * player.game.config.wall_jump
			}

			player.on_wall = 0
		}
	}
}

player_step :: proc(player: ^Player, distance: f32) {
	// TODO
}

player_melee :: proc(player: ^Player) {
	is_throw := player.can_throw && player.weapon.can_throw && player.aim_val == 1.0

	player.reloads[player.loadout_index] = player.weapon.rate * player.game.config.fire_rate
	player.did_shoot = true
	player.did_act = true

	if is_throw {
		player.can_throw = player.unlimited_ammo
		// TODO: init projectile
	} else {
		// TODO: hitscan
	}
}

player_shoot :: proc(player: ^Player) {
	if !player.unlimited_ammo {
		player.ammo[player.loadout_index] -= 1
	}

	player.did_shoot = true
	player.did_act = true
	player.shot_seq += 1

	if player.burst_count != 0 {
		player.burst_count -= 1
	} else {
		player.burst_count = player.weapon.burst ? i32(player.weapon.burst_count) - 1 : 0
	}

	player.reloads[player.loadout_index] = (player.burst_count != 0 && player.weapon.burst ? player.weapon.burst_rate : player.weapon.rate) * player.game.config.fire_rate

	player_apply_recoil(player)

	is_projectile := player.weapon.projectile && (!player.weapon.projectile_disable || player.game.config.bullet_drop)
	shot_height := player.position.y + player.height - GAME_CONSTANTS.camera_height

	shot_angles := Vec2{0, 0}

	if is_projectile {
		projectile_spread: f32 = 0.0
		spread := (player.spread + player.weapon.inaccuracy) * GAME_CONSTANTS.spread_adjustment * projectile_spread

		shot_angles.x = player.direction.x + player.recoil_anim_y * GAME_CONSTANTS.recoil_mlt + spread
		shot_angles.y = player.direction.y + spread
	}

	if !is_projectile || player.weapon.physical_power != 0 {
		shots: u32 = player.weapon.shots != 0 ? player.weapon.shots : 1

		start: i32 = player.weapon.physical_power != 0 ? -1 : 0
		for i := start; i < i32(shots); i += 1 {
			if player.weapon.custom_spread != nil && i >= 0 {
				offset := player.ammo[player.loadout_index] * player.weapon.shots

				spread := player.weapon.custom_spread[offset + u32(i)]
				spread_mlt := rand.float32() * 0.02 + 0.3

				shot_angles.x = player.direction.x + spread.y * spread_mlt
				shot_angles.y = player.direction.y + spread.x * spread_mlt
			} else {
				spread_range := i >= 0 ? (player.spread + player.weapon.inaccuracy) * GAME_CONSTANTS.spread_adjustment : 0.0
				spread := Vec2{
					(rand.float32() - 0.5) * 2.0 * spread_range,
					(rand.float32() - 0.5) * 2.0 * spread_range,
				}

				shot_angles.x = player.direction.x + spread.x
				shot_angles.y = player.direction.y + spread.y
			}

			shot_angles.x += player.recoil_anim_y * GAME_CONSTANTS.recoil_mlt

			range := i < 0 ? player.weapon.physical_range : player.weapon.range

			shot_origin := Vec3{player.position.x, shot_height, player.position.z}
			shot_dir := Vec3{
				range * math.sin(shot_angles.y + math.PI) * math.cos(shot_angles.x),
				range * math.sin(shot_angles.x),
				range * math.cos(shot_angles.y + math.PI) * math.cos(shot_angles.x),
			}

			nearest_t: f32 = 2.0
			nearest_normal := Vec3{}
			nearest_player: ^Player
			headshot := false

			for object in player.game.map_inst.objects {
				if !object.active || object.collision_type == .NONE || object.score_zone || object.objective || object.team_zone || object.bomb_site || object.flag || object.trigger || object.premium || object.verified || object.teleporter || object.checkpoint || object.pickup {
					continue
				}
				if player.game.is_local && object.mesh == nil {
					continue
				}

				t, normal, hit := ray_box_hit(shot_origin, shot_dir, object.position, object.scale)
				if hit && t < nearest_t {
					nearest_t = t
					nearest_normal = normal
				}
			}

			for target in player.game.players {
				if target == player || !target.active || target.team != 0 && target.team == player.team && !player.game.mode.config.dmg_team {
					continue
				}

				body_height := max(0.1, target.height * 0.72)
				body_origin := Vec3{target.position.x, target.position.y, target.position.z}
				body_scale := Vec3{target.scale * 2.0, body_height, target.scale * 2.0}
				body_t, _, body_hit := ray_box_hit(shot_origin, shot_dir, body_origin, body_scale)

				head_height := max(0.1, target.height - body_height)
				head_origin := Vec3{target.position.x, target.position.y + body_height, target.position.z}
				head_scale := Vec3{target.scale * 1.6, head_height, target.scale * 1.6}
				head_t, _, head_hit := ray_box_hit(shot_origin, shot_dir, head_origin, head_scale)

				hit_t := body_t
				is_head := false
				if head_hit && (!body_hit || head_t <= body_t) {
					hit_t = head_t
					is_head = true
				} else if !body_hit {
					continue
				}

				if hit_t < nearest_t {
					nearest_t = hit_t
					nearest_player = target
					headshot = is_head
				}
			}

			if nearest_player != nil {
				distance := range * nearest_t
				damage := player.weapon.damage
				if player.weapon.range > player.weapon.drop_start && distance > player.weapon.drop_start {
					drop_progress := clamp((distance - player.weapon.drop_start) / (player.weapon.range - player.weapon.drop_start), 0.0, 1.0)
					damage = max(0.0, damage - player.weapon.damage_drop * drop_progress)
				}
				if headshot {
					damage *= player.weapon.headshot_mlt
				}
				player_apply_damage(nearest_player, player, damage, player.loadout[player.loadout_index], headshot)
			}

			if nearest_t <= 1.0 {
				impact := Bullet_Impact{
					position = shot_origin + shot_dir * nearest_t,
					normal   = nearest_normal,
				}

				// Bound pending events if a headless consumer is not draining them.
				if len(player.game.impacts) >= 256 {
					ordered_remove(&player.game.impacts, 0)
				}
				append(&player.game.impacts, impact)
			}
		}
	}
}

player_update :: proc(player: ^Player, delta: f32) {
	if !player.active {
		return
	}

	if game_is_authority(player.game) && player.game.config.health_regen && !player.game.mode.config.no_regen && player.health < f32(player.max_health) && player.game.now - player.last_damage_time >= player.game.config.regen_delay {
		class := &player.game.classes[player.class_index]
		player.health = min(f32(player.max_health), player.health + f32(player.max_health) * class.regen * delta)
	}

	if len(player.input_queue) > 0 {
		for i in 0 ..< len(player.input_queue) {
			player_proc_input(player, &player.input_queue[i], false, player.game.move_lock)
		}

		clear(&player.input_queue)
	}

	player.idle_anim += GAME_CONSTANTS.idle_anim_speed * delta

	if player.hp_chase > player.health / f32(player.max_health) {
		player.hp_chase = max(0.0, player.hp_chase - delta * 0.2)
	} else {
		player.hp_chase = player.health / f32(player.max_health)
	}

	if player.interpolate {
		player_interpolate(player, delta)
	}
}

player_interpolate :: proc(player: ^Player, delta: f32) {
	if !player.interpolate {
		return
	}

	player.dt += delta

	progress := clamp(
		player.dt * player.send_rate / GAME_CONSTANTS.interpolation / player.game.config.delta_mlt,
		0.0,
		1.0,
	)

	player.last_position = player.position

	player.position.x = player.interp_pos_start.x + (player.interp_pos_end.x - player.interp_pos_start.x) * progress
	player.position.y = player.interp_pos_start.y + (player.interp_pos_end.y - player.interp_pos_start.y) * progress
	player.position.z = player.interp_pos_start.z + (player.interp_pos_end.z - player.interp_pos_start.z) * progress
	player.direction.x = player.interp_dir_start.x + (player.interp_dir_end.x - player.interp_dir_start.x) * progress
	player.direction.y = player.interp_dir_start.y + normalize_angle(player.interp_dir_end.y - player.interp_dir_start.y) * progress

	if player.on_ground {
		player_step(player, math.sqrt((player.last_position.x - player.position.x) * (player.last_position.x - player.position.x) + (player.last_position.z - player.position.z) * (player.last_position.z - player.position.z)))
	}
}

player_destroy :: proc(player: ^Player) {
	if player.ramp_fix != nil {
		free(player.ramp_fix)
	}

	delete(player.loadout)
	delete(player.ammo)
	delete(player.reloads)
	delete(player.input_queue)

	free(player)
}
