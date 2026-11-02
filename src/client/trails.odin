package main

import "core:math"
import shared "../shared"

// Krunker's physObj bullet tracer (particle config 0): units converted from
// milliseconds to seconds. Sniper smoke is a separate, shrinking trail.
BULLET_TRACER_SPEED :: 3000.0
BULLET_TRACER_LENGTH :: 8.0
BULLET_TRACER_WIDTH :: 0.5
BULLET_TRACER_MIN_DISTANCE :: 20.0
BULLET_TRACER_MAX_DISTANCE :: 500.0
BULLET_TRAIL_WIDTH :: 0.45
BULLET_TRAIL_SHRINK :: 0.36

Bullet_Trail :: struct {
	mesh: ^Mesh,
	start_position, direction: shared.Vec3,
	distance, length, width: f32,
}

// Current browser weapon configs: muzzle sprites are children of the weapon
// anchor, at {0, muzOffY, -muzOff}, independently of the tiny OBJ model scale.
bullet_muzzle_offset :: proc(weapon: ^shared.Weapon) -> shared.Vec3 {
	forward, up: f32
	switch weapon.src {
	case "weapon_1": forward = 8
	case "weapon_2": forward, up = 5.1, -0.05
	case "weapon_3": forward = 1.5
	case "weapon_4": forward, up = 2.15, 0.1
	case "weapon_5": forward, up = 2.75, 0.2
	case "weapon_6": forward = 6
	case "weapon_7", "weapon-7": forward, up = 5.5, -0.14
	case "weapon_8": forward, up = 4, -0.05
	case "weapon_9": forward = 5
	case "weapon_10": forward = 3.6
	case "weapon_11", "weapon_17": forward = 2
	case "weapon_12", "weapon_14": forward, up = 2.2, 0.1
	case "weapon_15": forward, up = 4.9, -0.05
	case "weapon_16": forward = 6
	case "weapon_19": forward, up = 5.1, -0.08
	}
	return {0, up, -forward}
}

bullet_tracer_origin :: proc(client: ^Client, impact: ^shared.Bullet_Impact, weapon: ^shared.Weapon) -> shared.Vec3 {
	start := impact.origin
	for player in client.game.players {
		if player == nil { continue }
		if player.uid != impact.shooter_uid { continue }
		if player.mesh != nil && player.loadout_index < player.loadout_size && player.loadout[player.loadout_index] == impact.weapon_id {
			rig := cast(^Player_Mesh)player.mesh
			if int(player.loadout_index) < len(rig.arms) && rig.arms[player.loadout_index] != nil {
				point: Mesh
				point.transform.parent = &rig.arms[player.loadout_index].anchor
				point.transform.position = bullet_muzzle_offset(weapon)
				point.transform.scale = {1, 1, 1}
				mesh_update_transform_matrix(&point)
				world := point.transform_matrix * shared.Vec4{0, 0, 0, 1}
				start = {world.x, world.y, world.z}
			}
		}
		// The scope hides the view model; Krunker pulls these tracers back seven
		// units so the trail remains visible through the scope.
		if weapon.src == "weapon_1" && player.aim_val >= 1 {
			ray := impact.position - impact.origin
			length := math.sqrt(ray.x * ray.x + ray.y * ray.y + ray.z * ray.z)
			if length > 0 { start -= ray * (7 / length) }
		}
		break
	}
	// A view model can poke through a nearby wall even though the shot starts
	// at the eye. Keep the visual on the eye's side of that wall as well.
	if client.game.map_inst != nil {
		for object in client.game.map_inst.objects {
			if !object.active || object.collision_type == .NONE || object.score_zone || object.objective || object.team_zone || object.bomb_site || object.flag || object.trigger || object.premium || object.verified || object.teleporter || object.checkpoint || object.pickup { continue }
			if _, _, hit := shared.ray_box_hit(impact.origin, start - impact.origin, object.position, object.scale); hit {
				return impact.origin
			}
		}
	}
	return start
}

bullet_trail_set_segment :: proc(mesh: ^Mesh, start, direction: shared.Vec3, width, length: f32) {
	mesh.transform.position = start
	mesh.transform.scale = {width, max(0.001, length), width}
	mesh.transform.rotation_order = .EXTRINSIC
	mesh.transform.rotation.x = math.atan2(math.sqrt(direction.x * direction.x + direction.z * direction.z), direction.y)
	mesh.transform.rotation.y = math.atan2(direction.x, direction.z)
	mesh.transform.rotation.z = 0
}

client_add_tracer :: proc(client: ^Client, impact: ^shared.Bullet_Impact) {
	if impact.weapon_id < 0 || int(impact.weapon_id) >= len(client.game.weapons) { return }
	weapon := client.game.weapons[impact.weapon_id]
	bullet_drop := client.game.config.bullet_drop
	if weapon == nil || weapon.melee || weapon.equipment || weapon.bomb || (weapon.projectile && (!weapon.projectile_disable || bullet_drop)) { return }
	ray := impact.position - impact.origin
	ray_length := math.sqrt(ray.x * ray.x + ray.y * ray.y + ray.z * ray.z)
	if ray_length < BULLET_TRACER_MIN_DISTANCE { return }
	start := bullet_tracer_origin(client, impact, weapon)
	direction := impact.position - start
	length := math.sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
	if length <= 0.01 { return }
	direction /= length
	distance := min(length, BULLET_TRACER_MAX_DISTANCE)

	material := basic_material_init()
	if material == nil { return }
	material.unlit = true
	material.no_fog = true
	material.color = shared.hex_to_vec(0xffffdb)
	mesh := mesh_init(create_cube_geo(), &material.base)
	bullet_trail_set_segment(mesh, start, direction, BULLET_TRACER_WIDTH, min(distance, BULLET_TRACER_LENGTH))
	if len(client.tracer_markers) >= 256 {
		oldest := client.tracer_markers[0]
		scene_remove_mesh(client.scene, oldest.mesh)
		mesh_fini(oldest.mesh)
		ordered_remove(&client.tracer_markers, 0)
	}
	scene_add_mesh(client.scene, mesh)
	append(&client.tracer_markers, Tracer_Marker{
		mesh = mesh, direction = direction, start_position = start,
		travel_distance = distance, segment_length = BULLET_TRACER_LENGTH,
		speed = BULLET_TRACER_SPEED, lifetime = distance / BULLET_TRACER_SPEED,
		total_lifetime = distance / BULLET_TRACER_SPEED,
	})

	if weapon.src != "weapon_1" { return }
	smoke_material := basic_material_init()
	if smoke_material == nil { return }
	smoke_material.unlit = true
	smoke_material.transparent = true
	smoke_material.color = shared.hex_to_vec(0xededed)
	smoke_material.color.w = 0.18
	smoke := mesh_init(create_cube_geo(), &smoke_material.base)
	bullet_trail_set_segment(smoke, start, direction, BULLET_TRAIL_WIDTH, 0)
	if len(client.bullet_trails) >= 32 {
		oldest := client.bullet_trails[0]
		scene_remove_mesh(client.scene, oldest.mesh)
		mesh_fini(oldest.mesh)
		ordered_remove(&client.bullet_trails, 0)
	}
	scene_add_mesh(client.scene, smoke)
	append(&client.bullet_trails, Bullet_Trail{
		mesh = smoke, start_position = start, direction = direction,
		distance = distance * 0.5, width = BULLET_TRAIL_WIDTH,
	})
}

client_tick_tracers :: proc(client: ^Client, delta: f32) {
	delta := max(0, delta)
	for i := len(client.tracer_markers) - 1; i >= 0; i -= 1 {
		tracer := &client.tracer_markers[i]
		if tracer.lifetime <= 0 {
			scene_remove_mesh(client.scene, tracer.mesh)
			mesh_fini(tracer.mesh)
			unordered_remove(&client.tracer_markers, i)
			continue
		}
		tracer.distance = min(tracer.travel_distance, tracer.distance + tracer.speed * delta)
		tracer.lifetime -= delta
		// Clip the leading tip to the resolved hit point, including the final
		// visible frame at low FPS. Never draw a full ray through the wall.
		length := min(tracer.segment_length, tracer.distance)
		start := tracer.start_position + tracer.direction * (tracer.distance - length)
		bullet_trail_set_segment(tracer.mesh, start, tracer.direction, BULLET_TRACER_WIDTH, length)
	}
	for i := len(client.bullet_trails) - 1; i >= 0; i -= 1 {
		trail := &client.bullet_trails[i]
		trail.width -= BULLET_TRAIL_SHRINK * delta
		if trail.width <= 0 {
			scene_remove_mesh(client.scene, trail.mesh)
			mesh_fini(trail.mesh)
			unordered_remove(&client.bullet_trails, i)
			continue
		}
		trail.length = min(trail.distance, trail.length + BULLET_TRACER_SPEED * delta)
		bullet_trail_set_segment(trail.mesh, trail.start_position, trail.direction, trail.width, trail.length)
	}
}

client_clear_tracers :: proc(client: ^Client) {
	for tracer in client.tracer_markers {
		scene_remove_mesh(client.scene, tracer.mesh)
		mesh_fini(tracer.mesh)
	}
	delete(client.tracer_markers)
	client.tracer_markers = nil
	for trail in client.bullet_trails {
		scene_remove_mesh(client.scene, trail.mesh)
		mesh_fini(trail.mesh)
	}
	delete(client.bullet_trails)
	client.bullet_trails = nil
}
