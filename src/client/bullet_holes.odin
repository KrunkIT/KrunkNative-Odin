package main

import "core:math"
import "core:strings"
import stbi "vendor:stb/image"
import shared "../shared"

MAX_BULLET_HOLES :: 128
BULLET_HOLE_LIFETIME :: f32(4)
BULLET_HOLE_FADE_TIME :: f32(0.6)
BULLET_HOLE_SURFACE_OFFSET :: f32(0.012)
g_bullet_hole_source_checked: bool
g_bullet_hole_source_usable: bool

bullet_hole_surface_visible :: proc(object: ^shared.Object) -> bool {
	if object == nil || !object.active || object.is_border || object.mesh == nil { return false }
	return (cast(^Mesh)object.mesh).visible
}

bullet_hole_face_visible :: proc(object: ^shared.Object, normal: shared.Vec3) -> bool {
	mesh := cast(^Mesh)object.mesh
	// Shared collision currently traces AABBs for props and ramps. Their box
	// faces need not coincide with the visible model, so do not hang decals in
	// the empty space around custom geometry or rotated map objects.
	if object.prefab != .CUBE || mesh.geometry != g_cube_geometry || mesh.transform.parent != nil ||
		abs(mesh.transform.rotation.x) + abs(mesh.transform.rotation.y) + abs(mesh.transform.rotation.z) > 0.0001 ||
		mesh.material == nil || mesh.material.vtable != &basic_material_vtable { return false }
	material := cast(^Basic_Material)mesh.material
	// Cutout fences/foliage contain holes which AABB collision cannot sample.
	if material.color.w <= 0.001 || material.alpha_test > 0 { return false }
	face: u32
	if abs(normal.z) > 0.999 { face = normal.z > 0 ? 0 : 1 }
	else if abs(normal.x) > 0.999 { face = normal.x > 0 ? 3 : 2 }
	else if abs(normal.y) > 0.999 { face = normal.y > 0 ? 4 : 5 }
	else { return false }
	return material.face_mask & (u32(1) << face) != 0
}

// Some mod packs replace the original particle with a single flat square.
// Preserve the shaped fallback in that case instead of stamping square holes.
bullet_hole_texture :: proc() -> (texture: u32, use_source: bool) {
	path := shared.concat(shared.assets_path(), "textures/particles/1.png")
	defer delete(path)
	if g_bullet_hole_source_checked {
		if g_bullet_hole_source_usable {
			texture = load_texture(path)
			if texture != 0 { return texture, true }
		}
		return impact_texture_get(), false
	}
	g_bullet_hole_source_checked = true
	cpath := strings.clone_to_cstring(path)
	defer delete(cpath)
	w, h, channels: i32
	data := stbi.load(cpath, &w, &h, &channels, 4)
	if data != nil {
		defer stbi.image_free(data)
		pixels := data[:int(w) * int(h) * 4]
		varied := false
		for i := 4; i < len(pixels); i += 4 {
			if pixels[i] != pixels[0] || pixels[i + 1] != pixels[1] || pixels[i + 2] != pixels[2] || pixels[i + 3] != pixels[3] {
				varied = true
				break
			}
		}
		if varied {
			g_bullet_hole_source_usable = true
			texture = load_texture(path)
			if texture != 0 { return texture, true }
		}
	}
	return impact_texture_get(), false
}

bullet_hole_cross :: proc(a, b: shared.Vec3) -> shared.Vec3 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}

// Clip the decal's polygon and UVs together, so shots at wall corners never
// leave a floating square beyond the face. Hit surfaces use shared map AABBs.
bullet_hole_clip :: proc(polygon: []Vertex, axis: int, boundary: f32, keep_greater: bool, output: []Vertex) -> int {
	if len(polygon) == 0 { return 0 }
	count := 0
	previous := polygon[len(polygon) - 1]
	previous_distance := previous.position[axis] - boundary
	previous_inside := keep_greater ? previous_distance >= 0 : previous_distance <= 0
	for current in polygon {
		distance := current.position[axis] - boundary
		inside := keep_greater ? distance >= 0 : distance <= 0
		if inside != previous_inside {
			fraction := previous_distance / (previous_distance - distance)
			output[count] = Vertex{
				position = previous.position + (current.position - previous.position) * fraction,
				tex_coord = previous.tex_coord + (current.tex_coord - previous.tex_coord) * fraction,
			}
			count += 1
		}
		if inside { output[count] = current; count += 1 }
		previous, previous_distance, previous_inside = current, distance, inside
	}
	return count
}

bullet_hole_vertices :: proc(position, normal: shared.Vec3, size, roll: f32, object: ^shared.Object, output: []Vertex) -> int {
	up := shared.Vec3{0, 1, 0}
	if abs(normal.y) > 0.95 { up = {1, 0, 0} }
	right := bullet_hole_cross(up, normal)
	right /= math.sqrt(right.x * right.x + right.y * right.y + right.z * right.z)
	top := bullet_hole_cross(normal, right)
	c, s := math.cos(roll), math.sin(roll)
	u := (right * c + top * s) * (size * 0.5)
	v := (top * c - right * s) * (size * 0.5)
	a, b: [16]Vertex
	a[0] = {position - u - v, {0, 0}}
	a[1] = {position + u - v, {1, 0}}
	a[2] = {position + u + v, {1, 1}}
	a[3] = {position - u + v, {0, 1}}
	count := 4
	minimum := object.position - shared.Vec3{object.scale.x * 0.5, 0, object.scale.z * 0.5}
	maximum := minimum + object.scale
	for axis in 0..<3 {
		// The impact already lies on the correct face.
		// A small tolerance retains vertices exactly on a collision plane.
		count = bullet_hole_clip(a[:count], axis, minimum[axis] - 0.001, true, b[:])
		count = bullet_hole_clip(b[:count], axis, maximum[axis] + 0.001, false, a[:])
	}
	for i in 0..<count {
		output[i] = a[i]
		output[i].position -= position
	}
	return count
}

client_remove_bullet_hole :: proc(client: ^Client, index: int) {
	scene_remove_mesh(client.scene, client.impact_markers[index].mesh)
	mesh_fini(client.impact_markers[index].mesh)
	ordered_remove(&client.impact_markers, index)
}

client_add_bullet_hole :: proc(client: ^Client, impact: ^shared.Bullet_Impact) {
	if impact.kind != .World || client.scene == nil || client.game.map_inst == nil { return }
	if impact.weapon_id < 0 || int(impact.weapon_id) >= len(client.game.weapons) { return }
	weapon := client.game.weapons[impact.weapon_id]
	if weapon == nil || weapon.melee || weapon.equipment || weapon.bomb ||
		(weapon.projectile && (!weapon.projectile_disable || client.game.config.bullet_drop)) { return }
	if impact.object_index < 0 || int(impact.object_index) >= len(client.game.map_inst.objects) { return }
	object := client.game.map_inst.objects[impact.object_index]
	if !bullet_hole_surface_visible(object) { return }
	normal := impact.normal
	normal_length := math.sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z)
	if normal_length < 0.001 { return }
	normal /= normal_length
	if !bullet_hole_face_visible(object, normal) { return }
	// Stable variation avoids using simulation randomness for cosmetic effects.
	variation := math.sin(impact.position.x * 12.9898 + impact.position.y * 78.233 + impact.position.z * 37.719) * 43758.5453
	variation -= math.floor(variation)
	size := f32(0.4) + variation * 0.6
	vertices: [16]Vertex
	count := bullet_hole_vertices(impact.position, normal, size, variation * math.PI * 2, object, vertices[:])
	if count < 3 { return }
	indices: [42]u32
	for i in 1..<count - 1 {
		indices[(i - 1) * 3 + 0] = 0
		indices[(i - 1) * 3 + 1] = u32(i)
		indices[(i - 1) * 3 + 2] = u32(i + 1)
	}
	material := basic_material_init()
	if material == nil { return }
	texture, source := bullet_hole_texture()
	if texture == 0 { material_fini(&material.base); return }
	material.texture = texture
	material.base.transparent = true
	material.unlit = true
	material.alpha_test = 0.005
	material.color = source ? shared.Vec4{0, 0, 0, 1} : shared.Vec4{1, 1, 1, 1}
	geometry := create_geometry(vertices[:count], indices[:(count - 2) * 3])
	mesh := mesh_init(geometry, &material.base)
	mesh.transform.position = impact.position + normal * BULLET_HOLE_SURFACE_OFFSET
	if len(client.impact_markers) >= MAX_BULLET_HOLES { client_remove_bullet_hole(client, 0) }
	scene_add_mesh(client.scene, mesh)
	append(&client.impact_markers, Impact_Marker{mesh = mesh, position = impact.position, lifetime = BULLET_HOLE_LIFETIME, object_index = impact.object_index})
}

client_tick_bullet_holes :: proc(client: ^Client, delta: f32) {
	for i := len(client.impact_markers) - 1; i >= 0; i -= 1 {
		marker := &client.impact_markers[i]
		marker.lifetime -= max(delta, 0)
		map_inst := client.game.map_inst
		if marker.lifetime <= 0 || map_inst == nil || marker.object_index < 0 || int(marker.object_index) >= len(map_inst.objects) {
			client_remove_bullet_hole(client, i)
			continue
		}
		if !bullet_hole_surface_visible(map_inst.objects[marker.object_index]) {
			client_remove_bullet_hole(client, i)
			continue
		}
		material := cast(^Basic_Material)marker.mesh.material
		material.color.w = clamp(marker.lifetime / BULLET_HOLE_FADE_TIME, 0, 1)
	}
}

client_clear_bullet_holes :: proc(client: ^Client) {
	for len(client.impact_markers) > 0 { client_remove_bullet_hole(client, len(client.impact_markers) - 1) }
	delete(client.impact_markers)
	client.impact_markers = nil
}

