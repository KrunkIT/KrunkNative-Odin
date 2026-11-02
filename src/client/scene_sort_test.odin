package main

import "core:testing"

when ODIN_TEST {
	@(test)
	transparent_sort_keeps_depth_order_and_ties :: proc(t: ^testing.T) {
		scene := scene_init()
		defer scene_fini(scene)
		meshes := make([]Mesh, 4097)
		defer delete(meshes)
		for &mesh, i in meshes {
			mesh.camera_space_matrix[2, 3] = f32((i * 199) % 67 - 40)
			append(&scene.transparent_meshes, &mesh)
		}
		scene_sort_transparent(scene)
		for i in 1..<len(scene.transparent_meshes) {
			a, b := scene.transparent_meshes[i - 1], scene.transparent_meshes[i]
			testing.expect(t, a.camera_space_matrix[2, 3] <= b.camera_space_matrix[2, 3], "transparent geometry must draw from far to near")
			if a.camera_space_matrix[2, 3] == b.camera_space_matrix[2, 3] {
				testing.expect(t, uintptr(a) < uintptr(b), "equal-depth effects must keep their original scene order")
			}
		}
		scratch := raw_data(scene.transparent_sort_scratch)
		// Turning 180 degrees reverses every depth; the buffer remains reusable.
		for &mesh in meshes { mesh.camera_space_matrix[2, 3] *= -1 }
		scene_sort_transparent(scene)
		for i in 1..<len(scene.transparent_meshes) {
			testing.expect(t, scene.transparent_meshes[i - 1].camera_space_matrix[2, 3] <= scene.transparent_meshes[i].camera_space_matrix[2, 3], "reversing the camera must reverse depth order correctly")
		}
		testing.expect(t, raw_data(scene.transparent_sort_scratch) == scratch, "camera turns must reuse sorting storage")
		clear(&scene.transparent_meshes)
		scene_sort_transparent(scene)
		append(&scene.transparent_meshes, &meshes[0])
		scene_sort_transparent(scene)
		testing.expect(t, len(scene.transparent_meshes) == 1 && scene.transparent_meshes[0] == &meshes[0], "empty and singleton scenes must remain valid")
	}
}
