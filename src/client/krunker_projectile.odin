package main

import "core:math"
import shared "../shared"

Krunker_Explosion_Flash :: struct {
	mesh: ^Mesh,
	age, radius: f32,
}

krunker_client_present_projectiles :: proc(client: ^Client) {
	world := &client.krunker_world
	for event in world.projectile_events {
		switch event.kind {
		case .END:
			for i := len(client.game.projectiles)-1; i >= 0; i -= 1 {
				projectile := &client.game.projectiles[i]
				matches := projectile.networked && projectile.network_id == event.id
				if event.by_shot_count { matches = !projectile.networked && projectile.owner_uid == world.local_sid && projectile.predicted_id == u32(event.id) }
				if matches { unordered_remove(&client.game.projectiles, i) }
			}
		case .SPAWN:
			if event.weapon_id < 0 || int(event.weapon_id) >= len(client.game.weapons) { continue }
			weapon := client.game.weapons[event.weapon_id]
			if weapon == nil || !weapon.projectile || weapon.projectile_range <= 0 || weapon.projectile_speed <= 0 { continue }
			duplicate := false
			for projectile in client.game.projectiles { if projectile.networked && projectile.network_id == event.id { duplicate = true; break } }
			if duplicate { continue }
			if event.owner_sid != world.local_sid {
				shared.game_emit_presentation(&client.game, {kind = .FIRE, uid = event.owner_sid, weapon_id = event.weapon_id, position = event.position})
			}
			// The normal server excludes the predicting shooter from pr. Its
			// pre packet addresses that player's local projectile shot counter.
			if len(client.game.projectiles) >= 256 { ordered_remove(&client.game.projectiles, 0) }
			append(&client.game.projectiles, shared.Projectile{
				networked = true, network_id = event.id, owner_uid = event.owner_sid,
				weapon_id = event.weapon_id, position = event.position,
				direction = {math.sin(event.angles.y+math.PI)*math.cos(event.angles.x), math.sin(event.angles.x), math.cos(event.angles.y+math.PI)*math.cos(event.angles.x)},
				remaining = weapon.projectile_range,
			})
		case .EXPLOSION:
			shared.game_emit_presentation(&client.game, {kind = .EXPLOSION, position = event.position})
			krunker_client_add_explosion(client, event.position, event.radius)
		}
	}
	clear(&world.projectile_events)
}

krunker_client_clear_explosions :: proc(client: ^Client) {
	for flash in client.explosions {
		scene_remove_mesh(client.scene, flash.mesh)
		mesh_fini(flash.mesh)
	}
	delete(client.explosions)
	client.explosions = nil
}

krunker_client_add_explosion :: proc(client: ^Client, position: shared.Vec3, radius: f32) {
	if client.scene == nil || radius <= 0 { return }
	if len(client.explosions) >= 64 {
		scene_remove_mesh(client.scene, client.explosions[0].mesh)
		mesh_fini(client.explosions[0].mesh)
		ordered_remove(&client.explosions, 0)
	}
	material := basic_material_init()
	if material == nil { return }
	material.unlit, material.transparent, material.no_depth_write = true, true, true
	material.no_fog = true
	path := shared.concat(shared.assets_path(), "textures/particles/glow_0.png")
	material.texture = load_texture(path)
	delete(path)
	material.color = {1, 0.65, 0.2, 0.9}
	vertices := [?]Vertex{
		{{-0.5,-0.5,0},{0,1}}, {{0.5,-0.5,0},{1,1}},
		{{0.5,0.5,0},{1,0}}, {{-0.5,0.5,0},{0,0}},
	}
	indices := [?]u32{0,1,2,0,2,3}
	mesh := mesh_init(create_geometry(vertices[:], indices[:]), &material.base)
	mesh.transform.position = position
	mesh.transform.rotation = client.camera.rotation
	mesh.transform.scale = {1,1,1}
	scene_add_mesh(client.scene, mesh)
	append(&client.explosions, Krunker_Explosion_Flash{mesh=mesh,radius=max(1,radius*0.32)})
}

krunker_client_tick_explosions :: proc(client: ^Client, delta: f32) {
	for i := len(client.explosions)-1; i >= 0; i -= 1 {
		flash := &client.explosions[i]
		flash.age += max(0, delta)
		if flash.age >= 0.4 {
			scene_remove_mesh(client.scene, flash.mesh)
			mesh_fini(flash.mesh)
			unordered_remove(&client.explosions, i)
			continue
		}
		size := flash.radius * (0.25 + flash.age/0.4)
		flash.mesh.transform.scale = {size,size,size}
		flash.mesh.transform.rotation = client.camera.rotation
		material := cast(^Basic_Material)flash.mesh.material
		material.color.w = 0.9*(1-flash.age/0.4)
	}
}
