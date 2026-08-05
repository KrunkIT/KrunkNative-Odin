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

scene_depth_sort :: proc(a, b: rawptr) -> int {
	p_a := cast(^int)a
	p_b := cast(^int)b

	mesh_a := g_sort_scene.meshes[p_a^]
	mesh_b := g_sort_scene.meshes[p_b^]

	if !mesh_a.visible {
		return 1
	}
	if !mesh_b.visible {
		return -1
	}

	if mesh_a.material.transparent || mesh_b.material.transparent {
		if !mesh_b.material.transparent {
			return 1
		}
		if !mesh_a.material.transparent {
			return -1
		}

		a_depth := mesh_a.camera_space_matrix[2, 3]
		b_depth := mesh_b.camera_space_matrix[2, 3]

		if b_depth > a_depth {
			return -1
		}

		return 1
	}

	return 0
}

g_sort_scene: ^Scene

scene_render :: proc(scene: ^Scene, camera: ^Camera) {
	viewport: [4]i32
	gl.GetIntegerv(gl.VIEWPORT, &viewport[0])

	gl.Enable(gl.DEPTH_TEST)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)

	camera_update_projection_matrix(camera, f32(viewport[2]) / f32(viewport[3]))
	camera_update_world_inverse_matrix(camera)

	indices := make([]int, len(scene.meshes))
	defer delete(indices)

	for i in 0 ..< len(scene.meshes) {
		mesh := scene.meshes[i]
		mesh_update_transform_matrix(mesh)

		if mesh.material.transparent {
			mesh.camera_space_matrix = camera.world_inverse_matrix * mesh.transform_matrix
		}

		indices[i] = i
	}

	g_sort_scene = scene
	sort_ints(indices)

	for i in 0 ..< len(indices) {
		mesh := scene.meshes[indices[i]]

		if !mesh.visible {
			continue
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

		transform := gl.GetUniformLocation(mesh.material.program, "transform")
		camera_world_inverse := gl.GetUniformLocation(mesh.material.program, "camera_world_inverse")
		camera_projection := gl.GetUniformLocation(mesh.material.program, "camera_projection")

		if transform > -1 {
			gl.UniformMatrix4fv(transform, 1, gl.FALSE, &mesh.transform_matrix[0, 0])
		}
		if camera_world_inverse > -1 {
			gl.UniformMatrix4fv(camera_world_inverse, 1, gl.FALSE, &camera.world_inverse_matrix[0, 0])
		}
		if camera_projection > -1 {
			gl.UniformMatrix4fv(camera_projection, 1, gl.FALSE, &camera.projection_matrix[0, 0])
		}

		if mesh.material.wireframe {
			gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
		} else {
			gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)
		}

		gl.DrawElements(gl.TRIANGLES, mesh.geometry.index_count, gl.UNSIGNED_INT, nil)
	}

	// Rendering state must not leak into the HUD pass.
	gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)
}

sort_ints :: proc(indices: []int) {
	// insertion sort keeps the depth sort stable & simple
	for i in 1 ..< len(indices) {
		key := indices[i]
		j := i - 1

		for j >= 0 && scene_depth_sort(&key, &indices[j]) < 0 {
			indices[j + 1] = indices[j]
			j -= 1
		}

		indices[j + 1] = key
	}
}

scene_fini :: proc(scene: ^Scene) {
	delete(scene.meshes)
	free(scene)
}
