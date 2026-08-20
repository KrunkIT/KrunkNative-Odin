package main

import "core:math"
import "core:math/linalg"
import gl "vendor:OpenGL"
import shared "../shared"

scene_init :: proc() -> ^Scene {
	return new(Scene)
}

scene_add_mesh :: proc(scene: ^Scene, mesh: ^Mesh) {
	append(&scene.meshes, mesh)
	scene.mesh_count = i32(len(scene.meshes))
}

scene_remove_mesh :: proc(scene: ^Scene, mesh: ^Mesh) {
	for i := 0; i < len(scene.meshes); i += 1 {
		if scene.meshes[i] == mesh {
			ordered_remove(&scene.meshes, i)
			scene.mesh_count = i32(len(scene.meshes))
			return
		}
	}
}

scene_add_player_mesh :: proc(scene: ^Scene, player_mesh: ^Player_Mesh, loadout_size: int) {
	if player_mesh.body != nil {
		for mesh in player_mesh.body.meshes {
			scene_add_mesh(scene, mesh)
		}
	}

	if player_mesh.head != nil {
		for mesh in player_mesh.head.meshes {
			scene_add_mesh(scene, mesh)
		}
	}

	for i in 0 ..< loadout_size {
		if i >= len(player_mesh.arms) {
			break
		}

		arms := player_mesh.arms[i]
		if arms == nil {
			continue
		}

		if arms.weapon_right != nil {
			scene_add_mesh(scene, arms.weapon_right)
		}
		if arms.weapon_left != nil {
			scene_add_mesh(scene, arms.weapon_left)
		}

		for j in 0 ..< 2 {
			arm := arms.left if j == 1 else arms.right

			if arm == nil {
				continue
			}

			if arm.extender != nil {
				scene_add_mesh(scene, arm.extender)
			}

			if arm.upper != nil {
				scene_add_mesh(scene, arm.upper)
			}
			if arm.joint != nil {
				scene_add_mesh(scene, arm.joint)
			}

			for k in arm.lower.meshes {
				scene_add_mesh(scene, k)
			}
		}
	}

	for leg in player_mesh.legs {
		if leg == nil {
			continue
		}

		for mesh in leg.meshes {
			scene_add_mesh(scene, mesh)
		}
	}

	for leg in player_mesh.crouched_legs {
		if leg == nil {
			continue
		}

		scene_add_mesh(scene, leg.upper)
		scene_add_mesh(scene, leg.joint)

		for mesh in leg.lower.meshes {
			scene_add_mesh(scene, mesh)
		}
	}
}

scene_remove_player_mesh :: proc(scene: ^Scene, player_mesh: ^Player_Mesh, loadout_size: int) {
	if player_mesh == nil {
		return
	}

	if player_mesh.body != nil {
		for mesh in player_mesh.body.meshes {
			scene_remove_mesh(scene, mesh)
		}
	}

	if player_mesh.head != nil {
		for mesh in player_mesh.head.meshes {
			scene_remove_mesh(scene, mesh)
		}
	}

	for i in 0 ..< loadout_size {
		if i >= len(player_mesh.arms) {
			break
		}

		arms := player_mesh.arms[i]
		if arms == nil {
			continue
		}

		if arms.weapon_right != nil {
			scene_remove_mesh(scene, arms.weapon_right)
		}
		if arms.weapon_left != nil {
			scene_remove_mesh(scene, arms.weapon_left)
		}

		for j in 0 ..< 2 {
			arm := arms.left if j == 1 else arms.right

			if arm == nil {
				continue
			}

			if arm.extender != nil {
				scene_remove_mesh(scene, arm.extender)
			}

			if arm.upper != nil {
				scene_remove_mesh(scene, arm.upper)
			}
			if arm.joint != nil {
				scene_remove_mesh(scene, arm.joint)
			}

			for k in arm.lower.meshes {
				scene_remove_mesh(scene, k)
			}
		}
	}

	for leg in player_mesh.legs {
		if leg == nil {
			continue
		}

		for mesh in leg.meshes {
			scene_remove_mesh(scene, mesh)
		}
	}

	for leg in player_mesh.crouched_legs {
		if leg == nil {
			continue
		}

		scene_remove_mesh(scene, leg.upper)
		scene_remove_mesh(scene, leg.joint)

		for mesh in leg.lower.meshes {
			scene_remove_mesh(scene, mesh)
		}
	}
}

scene_uniforms :: proc(program: u32) -> ^Shader_Uniforms {
	if program == basic_shader_program {
		return &u_basic
	} else if program == quad_shader_program {
		return &u_quad
	}
	return &u_text
}

scene_draw_mesh :: proc(mesh: ^Mesh, camera: ^Camera) {
	if !mesh.visible {
		return
	}

	if mesh.material.transparent {
		gl.Enable(gl.BLEND)
	} else {
		gl.Disable(gl.BLEND)
	}

	gl.BindVertexArray(mesh.geometry.vao)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.geometry.ebo)

	if g_active_shader != mesh.material.program {
		gl.UseProgram(mesh.material.program)
		g_active_shader = mesh.material.program
	}

	material_update_uniforms(mesh.material)

	u := scene_uniforms(mesh.material.program)
	if u.transform > -1 {
		gl.UniformMatrix4fv(u.transform, 1, gl.FALSE, &mesh.transform_matrix[0, 0])
	}
	if u.camera_world_inverse > -1 {
		gl.UniformMatrix4fv(u.camera_world_inverse, 1, gl.FALSE, &camera.world_inverse_matrix[0, 0])
	}
	if u.camera_projection > -1 {
		gl.UniformMatrix4fv(u.camera_projection, 1, gl.FALSE, &camera.projection_matrix[0, 0])
	}

	if mesh.material.wireframe {
		gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
	} else {
		gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)
	}

	gl.DrawElements(gl.TRIANGLES, mesh.geometry.index_count, gl.UNSIGNED_INT, nil)
}

scene_render :: proc(scene: ^Scene, camera: ^Camera, viewport_w, viewport_h: f32) {
	aspect := viewport_h > 0 ? viewport_w / viewport_h : (16.0 / 9.0)

	gl.Enable(gl.DEPTH_TEST)
	gl.DepthMask(gl.TRUE)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)

	camera_update_projection_matrix(camera, aspect)
	camera_update_world_inverse_matrix(camera)

	mesh_count := len(scene.meshes)
	if mesh_count == 0 {
		return
	}

	// 1. Draw opaque meshes directly with hardware depth testing.
	// 2. Collect visible transparent meshes for back-to-front sorting.
	clear(&scene.transparent_meshes)
	for i in 0 ..< mesh_count {
		mesh := scene.meshes[i]
		if !mesh.visible {
			continue
		}
		mesh_update_transform_matrix(mesh)

		if mesh.material.transparent {
			mesh.camera_space_matrix = camera.world_inverse_matrix * mesh.transform_matrix
			append(&scene.transparent_meshes, mesh)
		} else {
			scene_draw_mesh(mesh, camera)
		}
	}

	// Draw sorted transparent meshes
	trans_count := len(scene.transparent_meshes)
	if trans_count > 0 {
		// Sort transparent meshes back-to-front (largest camera-space depth first)
		for i in 1 ..< trans_count {
			key := scene.transparent_meshes[i]
			key_depth := key.camera_space_matrix[2, 3]
			j := i - 1
			for j >= 0 && scene.transparent_meshes[j].camera_space_matrix[2, 3] > key_depth {
				scene.transparent_meshes[j + 1] = scene.transparent_meshes[j]
				j -= 1
			}
			scene.transparent_meshes[j + 1] = key
		}

		for i in 0 ..< trans_count {
			scene_draw_mesh(scene.transparent_meshes[i], camera)
		}
	}

	// Rendering state must not leak into the HUD pass.
	gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)
}

scene_fini :: proc(scene: ^Scene) {
	delete(scene.meshes)
	delete(scene.transparent_meshes)
	delete(scene.sort_indices)
	free(scene)
}
