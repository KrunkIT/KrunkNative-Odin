package main

import "core:math"
import shared "../shared"

client_clear_projectiles :: proc(client: ^Client) {
	for mesh in client.projectile_meshes {
		scene_remove_mesh(client.scene, mesh)
		mesh_fini(mesh)
	}
	delete(client.projectile_meshes)
	client.projectile_meshes = nil
	clear(&client.game.projectiles)
}

client_tick_projectiles :: proc(client: ^Client) {
	for len(client.projectile_meshes) > len(client.game.projectiles) {
		last := len(client.projectile_meshes) - 1
		mesh := client.projectile_meshes[last]
		scene_remove_mesh(client.scene, mesh)
		mesh_fini(mesh)
		unordered_remove(&client.projectile_meshes, last)
	}
	for projectile, i in client.game.projectiles {
		if i == len(client.projectile_meshes) {
			material := basic_material_init()
			if material == nil { return }
			material.unlit = true
			mesh := mesh_init(create_cube_geo(), &material.base)
			append(&client.projectile_meshes, mesh)
			scene_add_mesh(client.scene, mesh)
		}
		mesh := client.projectile_meshes[i]
		weapon := client.game.weapons[projectile.weapon_id]
		material := cast(^Basic_Material)mesh.material
		material.color = shared.hex_to_vec(weapon.projectile_color)
		material.emissive = material.color
		length := max(0.1, min(weapon.projectile_length, projectile.travelled))
		mesh.transform.position = projectile.position - projectile.direction * length
		mesh.transform.scale = {weapon.projectile_scale, length, weapon.projectile_scale}
		mesh.transform.rotation_order = .EXTRINSIC
		mesh.transform.rotation.x = math.atan2(math.sqrt(projectile.direction.x * projectile.direction.x + projectile.direction.z * projectile.direction.z), projectile.direction.y)
		mesh.transform.rotation.y = math.atan2(projectile.direction.x, projectile.direction.z)
		mesh.transform.rotation.z = 0
	}
}
