package main

import "core:math"
import shared "../shared"
import kproto "../krunker"

krunker_client_apply_ammo :: proc(client: ^Client, player: ^shared.Player, source: ^kproto.Krunker_World_Player) {
	if source.ammo_revision == client.krunker.local_ammo_revision { return }
	client.krunker.local_ammo_revision = source.ammo_revision
	for slot in 0..<min(source.ammo_count, int(player.loadout_size)) {
		ammo := source.ammo[slot]
		if ammo < 0 { continue }
		capacity := client.game.weapons[player.loadout[slot]].ammo
		count := clamp(u32(ammo), 0, capacity)
		if slot == int(player.loadout_index) && count > player.ammo[slot] {
			player.reload_timer = 0
			player.did_shoot = false
		}
		player.ammo[slot] = count
	}
}

// Match the browser's one-interval delay and the q shot-history timing. Keeping both endpoints
// avoids the repeated start/stop motion of chasing the newest packet directly.
krunker_client_interpolate_remotes :: proc(client: ^Client, now: f64, delta: f32) {
	for &source in client.krunker_world.players {
		if source.sid == client.krunker_world.local_sid || source.pose_count == 0 { continue }
		player := client_find_player(client, source.sid)
		if player == nil || !player.active { continue }
		rate := source.send_rate > 0 ? source.send_rate : 10
		display_time := kproto.krunker_display_time(now, rate)
		for source.pose_count >= 2 && source.poses[1].time <= display_time {
			copy(source.poses[:], source.poses[1:source.pose_count])
			source.pose_count -= 1
		}
		a, b := source.poses[0], source.poses[0]
		if source.pose_count > 1 { b = source.poses[1] }
		alpha: f32
		if b.time > a.time { alpha = clamp(f32((display_time-a.time)/(b.time-a.time)), 0, 1) }
		previous := player.position
		player.last_position = previous
		player.position = a.position + (b.position-a.position)*alpha
		player.direction.x = a.direction.x + (b.direction.x-a.direction.x)*alpha
		player.direction.y = a.direction.y + shared.normalize_angle(b.direction.y-a.direction.y)*alpha
		player.crouch_val = a.crouch + (b.crouch-a.crouch)*alpha
		player.aim_val = a.aim + (b.aim-a.aim)*alpha
		player.on_ground = alpha < 0.5 ? a.on_ground : b.on_ground
		shared.player_update_height(player)
		displacement := player.position - previous
		distance := math.sqrt(displacement.x*displacement.x + displacement.z*displacement.z)
		if player.on_ground && distance < 64 { shared.player_step(player, distance) }
		player.step_chase += (player.step_val-player.step_chase)*min(1, delta*20)
		for &cooldown in player.reloads { cooldown = max(0, cooldown-delta) }
	}
}

krunker_client_present_shots :: proc(client: ^Client) {
	for shot in client.krunker_world.shots {
		// The server normally excludes the shooter. Never duplicate a locally
		// predicted bullet if a server implementation also echoes it back.
		if shot.sid == client.krunker_world.local_sid { continue }
		player := client_find_player(client, shot.sid)
		if player == nil || player.weapon == nil || player.weapon.melee { continue }
		impact := shared.Bullet_Impact{
			origin = shot.origin, position = shot.position,
			kind = .Miss, object_index = -1,
			weapon_id = player.loadout[player.loadout_index], shooter_uid = shot.sid,
		}
		impact.origin.y += shot.height - shared.GAME_CONSTANTS.camera_height - 3*player.crouch_val
		if shot.has_surface && client.game.map_inst != nil {
			// The wire endpoint sits just ahead of the surface. Resolve its map
			// face so the existing clipped bullet-hole renderer gets a real object.
			ray := impact.position-impact.origin
			distance := math.sqrt(ray.x*ray.x + ray.y*ray.y + ray.z*ray.z)
			if distance > 0 {
				for object, index in client.game.map_inst.objects {
					if object == nil || !object.active || object.collision_type == .NONE { continue }
					t, normal, hit := shared.ray_box_hit(impact.origin, ray*(1+0.5/distance), object.position, object.scale)
					if !hit { continue }
					point := impact.origin + ray*(1+0.5/distance)*t
					difference := point-impact.position
					if difference.x*difference.x + difference.y*difference.y + difference.z*difference.z > 0.5*0.5 { continue }
					impact.position, impact.normal = point, normal
					impact.kind, impact.hit, impact.object_index = .World, true, i32(index)
					break
				}
			}
		}
		if player.reloads[player.loadout_index] <= 0 {
			shared.player_apply_recoil(player)
			shared.player_start_view_kick(player)
			player.reloads[player.loadout_index] = player.weapon.rate * client.game.config.fire_rate
		}
		if len(client.game.impacts) >= 256 { ordered_remove(&client.game.impacts, 0) }
		append(&client.game.impacts, impact)
	}
	clear(&client.krunker_world.shots)
}
