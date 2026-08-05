package main

import "core:math"
import "core:math/linalg"
import shared "../shared"

camera_update_projection_matrix :: proc(camera: ^Camera, aspect: f32) {
	camera.projection_matrix = linalg.matrix4_perspective_f32(
		camera.fov / camera.zoom,
		aspect,
		camera.near,
		camera.far,
	)
}

camera_update_world_inverse_matrix :: proc(camera: ^Camera) {
	rotate_x_matrix := linalg.matrix4_rotate_f32(-camera.rotation.x, shared.Vec3{1, 0, 0})
	rotate_y_matrix := linalg.matrix4_rotate_f32(-camera.rotation.y, shared.Vec3{0, 1, 0})
	rotate_z_matrix := linalg.matrix4_rotate_f32(-camera.rotation.z, shared.Vec3{0, 0, 1})
	translate_matrix := linalg.matrix4_translate_f32(-camera.position)

	tmp := rotate_z_matrix * translate_matrix
	tmp1 := rotate_y_matrix * tmp
	camera.world_inverse_matrix = rotate_x_matrix * tmp1
}

camera_init :: proc(fov: f32) -> Camera {
	cam: Camera

	cam.fov = fov
	cam.near = 0.1
	cam.far = 10000.0
	cam.zoom = 1.0

	return cam
}
