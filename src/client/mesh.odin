package main

import "core:math/linalg"
import shared "../shared"

mesh_init :: proc(geometry: ^Geometry, material: ^Material) -> ^Mesh {
	mesh := new(Mesh)

	mesh.transform.scale = shared.Vec3{1.0, 1.0, 1.0}

	mesh.visible = true
	mesh.geometry = geometry
	mesh.material = material

	return mesh
}

mesh_update_transform_matrix :: proc(mesh: ^Mesh) {
	transform_matrix := linalg.MATRIX4F32_IDENTITY

	transform: ^Mesh_Transform = &mesh.transform

	for transform != nil {
		scale_matrix := linalg.matrix4_scale_f32(transform.scale)
		rotate_x_matrix := linalg.matrix4_rotate_f32(transform.rotation.x, shared.Vec3{1, 0, 0})
		rotate_y_matrix := linalg.matrix4_rotate_f32(transform.rotation.y, shared.Vec3{0, 1, 0})
		rotate_z_matrix := linalg.matrix4_rotate_f32(transform.rotation.z, shared.Vec3{0, 0, 1})
		translate_matrix := linalg.matrix4_translate_f32(transform.position)

		tmp := scale_matrix * transform_matrix

		tmp1: shared.Mat4

		// Intrinsic rotation by default (THREE.js style)
		if transform.rotation_order == .INTRINSIC {
			tmp1 = rotate_z_matrix * tmp
			tmp = rotate_y_matrix * tmp1
			tmp1 = rotate_x_matrix * tmp
		} else {
			tmp1 = rotate_x_matrix * tmp
			tmp = rotate_y_matrix * tmp1
			tmp1 = rotate_z_matrix * tmp
		}

		transform_matrix = translate_matrix * tmp1

		transform = transform.parent
	}

	mesh.transform_matrix = transform_matrix
}

mesh_fini :: proc(mesh: ^Mesh) {
	if mesh.material != nil {
		if mesh.material.vtable == &basic_material_vtable {
			material := cast(^Basic_Material)mesh.material
			texture_release(material.texture)
		}
		free(mesh.material)
	}

	geometry_release(mesh.geometry)

	free(mesh)
}

material_update_uniforms :: proc(material: ^Material) {
	if material.vtable != nil && material.vtable.update_uniforms != nil {
		material.vtable.update_uniforms(material)
	}
}

material_fini :: proc(material: ^Material) {
	free(material)
}
