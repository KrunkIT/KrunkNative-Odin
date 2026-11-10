package shared

import "core:math"

// Straight energy bolts use swept collision so fast shots cannot pass through
// thin walls between simulation ticks. Damage is applied only by the authority.
projectile_spawn :: proc(player: ^Player, angles: Vec2) {
	if player == nil || player.game == nil || player.weapon == nil { return }
	weapon := player.weapon
	if !weapon.projectile || weapon.projectile_speed <= 0 || weapon.projectile_range <= 0 { return }
	if len(player.game.projectiles) >= 256 { ordered_remove(&player.game.projectiles, 0) }
	append(&player.game.projectiles, Projectile{
		predicted_id = player.projectile_shot_seq,
		owner_uid = player.uid,
		weapon_id = player.loadout[player.loadout_index],
		position = {player.position.x, player.position.y + player.height - GAME_CONSTANTS.camera_height, player.position.z},
		direction = {math.sin(angles.y + math.PI) * math.cos(angles.x), math.sin(angles.x), math.cos(angles.y + math.PI) * math.cos(angles.x)},
		remaining = weapon.projectile_range,
	})
}

game_tick_projectiles :: proc(game: ^Game, delta: f32) {
	if game == nil || game.map_inst == nil || delta <= 0 { return }
	for i := len(game.projectiles) - 1; i >= 0; i -= 1 {
		projectile := &game.projectiles[i]
		owner: ^Player
		for player in game.players {
			if player.uid == projectile.owner_uid { owner = player; break }
		}
		if owner == nil && !projectile.networked || projectile.weapon_id < 0 || int(projectile.weapon_id) >= len(game.weapons) {
			unordered_remove(&game.projectiles, i)
			continue
		}
		weapon := game.weapons[projectile.weapon_id]
		if weapon == nil { unordered_remove(&game.projectiles, i); continue }
		distance := min(projectile.remaining, weapon.projectile_speed * delta)
		segment := projectile.direction * distance
		if projectile.networked {
			// Server-owned visuals end on pre or range exhaustion. Local
			// collision estimates cannot determine live damage or impact timing.
			projectile.position += segment
			projectile.remaining -= distance
			projectile.travelled += distance
			if projectile.remaining <= 0 { unordered_remove(&game.projectiles, i) }
			continue
		}
		radius := max(0, weapon.projectile_scale) * 0.5
		padding := Vec3{radius * 2, radius * 2, radius * 2}
		nearest: f32 = 2
		target: ^Player
		for object in game.map_inst.objects {
			if !object.active || object.collision_type == .NONE || object.score_zone || object.objective || object.team_zone || object.bomb_site || object.flag || object.trigger || object.premium || object.verified || object.teleporter || object.checkpoint || object.pickup { continue }
			position := object.position - Vec3{0, radius, 0}
			if t, _, hit := ray_box_hit(projectile.position, segment, position, object.scale + padding); hit && t < nearest {
				nearest = t
			}
		}
		for player in game.players {
			if player == owner || !player.active || (player.team != 0 && player.team == owner.team && (game.mode == nil || !game.mode.config.dmg_team)) { continue }
			position := player.position - Vec3{0, radius, 0}
			size := Vec3{player.scale * 2, player.height, player.scale * 2} + padding
			if t, _, hit := ray_box_hit(projectile.position, segment, position, size); hit && t < nearest {
				nearest = t
				target = player
			}
		}
		if nearest <= 1 {
			if weapon.physical_power > 0 && game_is_authority(game) {
				game_emit_presentation(game, {kind = .EXPLOSION, position = projectile.position + segment * nearest})
			}
			if target != nil && game_is_authority(game) {
				player_apply_damage(target, owner, weapon.projectile_damage, projectile.weapon_id, false)
			}
			unordered_remove(&game.projectiles, i)
			continue
		}
		projectile.position += segment
		projectile.remaining -= distance
		projectile.travelled += distance
		if projectile.remaining <= 0 { unordered_remove(&game.projectiles, i) }
	}
}
