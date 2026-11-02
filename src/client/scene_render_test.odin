package main

import "base:runtime"
import "core:math"
import "core:testing"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import shared "../shared"

when ODIN_TEST {
	check_mesh_point :: proc(t: ^testing.T, mesh: ^Mesh, point, expected: shared.Vec4) {
		mesh_update_transform_matrix(mesh)
		actual := mesh.transform_matrix * point
		for value, i in actual {
			testing.expect(t, abs(value - expected[i]) < 0.0001, "direct transform edits and ancestor changes must update the world matrix")
		}
	}

	@(test)
	mesh_transforms_follow_edits_and_ancestors :: proc(t: ^testing.T) {
		mesh := Mesh{transform = {scale = {1, 1, 1}}}
		point := shared.Vec4{1, 2, 3, 1}
		check_mesh_point(t, &mesh, point, point)
		check_mesh_point(t, &mesh, point, point)
		mesh.transform.position = {2, 3, 4}
		mesh.transform.scale = {2, 3, 4}
		check_mesh_point(t, &mesh, point, {4, 9, 16, 1})
		mesh.transform.rotation.z = math.PI / 2
		check_mesh_point(t, &mesh, point, {-4, 5, 16, 1})
		mesh.transform = {rotation = {math.PI / 2, math.PI / 2, 0}, scale = {1, 1, 1}}
		check_mesh_point(t, &mesh, {0, 1, 0, 1}, {0, 0, 1, 1})
		mesh.transform.rotation_order = .EXTRINSIC
		check_mesh_point(t, &mesh, {0, 1, 0, 1}, {1, 0, 0, 1})

		parent := Mesh_Transform{position = {10, 0, 0}, scale = {1, 1, 1}}
		mesh.transform = {parent = &parent, position = {1, 0, 0}, scale = {1, 1, 1}}
		check_mesh_point(t, &mesh, {0, 0, 0, 1}, {11, 0, 0, 1})
		parent.position.x = 20
		check_mesh_point(t, &mesh, {0, 0, 0, 1}, {21, 0, 0, 1})
		ancestor := Mesh_Transform{position = {100, 0, 0}, scale = {1, 1, 1}}
		parent.parent = &ancestor
		check_mesh_point(t, &mesh, {0, 0, 0, 1}, {121, 0, 0, 1})
		mesh.transform.parent = nil
		check_mesh_point(t, &mesh, {0, 0, 0, 1}, {1, 0, 0, 1})
		check_mesh_point(t, &mesh, {0, 0, 0, 1}, {1, 0, 0, 1})
	}

	scene_test_pixel :: proc(t: ^testing.T, scene: ^Scene, camera: ^Camera, x, y: i32, expected: [3]u8) {
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
		scene_render(scene, camera, 64, 64)
		pixel: [4]u8
		gl.ReadPixels(x, y, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, &pixel[0])
		for value, i in expected {
			testing.expect(t, abs(i32(pixel[i]) - i32(value)) <= 3, "each render pass must use its current camera, environment, material and GL state")
		}
	}

	@(test)
	scene_pass_refreshes_camera_environment_and_state :: proc(t: ^testing.T) {
		context = runtime.default_context()
		if !testing.expect(t, bool(glfw.Init()), "GLFW initialization failed") do return
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(64, 64, "Render pass regression", nil, nil)
		if !testing.expect(t, window != nil, "hidden OpenGL window failed") do return
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
		gl.Viewport(0, 0, 64, 64)
		gl.ClearColor(0, 0, 0, 1)
		scene := scene_init()
		material := basic_material_init()
		if !testing.expect(t, material != nil, "basic material failed") do return
		material.no_fog = true
		mesh := mesh_init(create_cube_geo(), &material.base)
		mesh.transform.position = {0, -1, -5}
		mesh.transform.scale = {2, 2, 2}
		scene_add_mesh(scene, mesh)
		ui := ui_init()
		saved_lighting := g_lighting_config
		defer {
			g_lighting_config = saved_lighting
			ui_fini(ui)
			mesh_fini(mesh)
			scene_fini(scene)
			resource_cache_fini()
		}
		g_lighting_config.ambient_intensity = 1
		g_lighting_config.light_intensity = 0
		g_lighting_config.ambient_color = {1, 0, 0}
		camera := camera_init(math.PI / 2)
		scene_test_pixel(t, scene, &camera, 32, 32, {255, 0, 0})
		g_lighting_config.ambient_color = {0, 0, 1}
		scene_test_pixel(t, scene, &camera, 32, 32, {0, 0, 255})
		camera.position.x = 100
		scene_test_pixel(t, scene, &camera, 32, 32, {0, 0, 0})
		camera.position.x = 0
		scene_test_pixel(t, scene, &camera, 44, 32, {0, 0, 0})
		weapon_camera := camera_for_viewmodel(&camera)
		weapon_camera.zoom = 2
		scene_test_pixel(t, scene, &weapon_camera, 44, 32, {0, 0, 255})
		scene_test_pixel(t, scene, &camera, 44, 32, {0, 0, 0})

		material.no_fog = false
		g_lighting_config.fog_distance = 2
		g_lighting_config.fog_color = {0, 1, 0}
		scene_test_pixel(t, scene, &camera, 32, 32, {0, 255, 0})
		camera.position.z = -3.5
		scene_test_pixel(t, scene, &camera, 32, 32, {0, 0, 255})

		material.no_fog = true
		material.unlit = true
		material.transparent = true
		material.color.w = 0.5
		scene_test_pixel(t, scene, &camera, 32, 32, {128, 128, 128})
		material.transparent = false
		material.color.w = 1
		material.wireframe = true
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
		scene_render(scene, &camera, 64, 64)
		polygon_modes: [2]i32
		gl.GetIntegerv(gl.POLYGON_MODE, &polygon_modes[0])
		testing.expect(t, polygon_modes == [2]i32{gl.FILL, gl.FILL}, "wireframe must not leak into HUD drawing")
		material.wireframe = false
		ui_update(ui, 64, 64)
		ui_fill_rect(ui, {0, 1, 0, 1}, 0, 0, 64, 64)
		gl.ActiveTexture(gl.TEXTURE1)
		scene_test_pixel(t, scene, &camera, 32, 32, {255, 255, 255})
		testing.expect(t, !bool(gl.IsEnabled(gl.BLEND)), "a new opaque pass must reset HUD blending")
		testing.expect(t, load_glyph('0') != nil, "UI font must load")
		ui_fini(ui)
		ui = ui_init()
		testing.expect(t, load_glyph('0') != nil, "recreating the UI must rebuild its font cache safely")
		testing.expect(t, gl.GetError() == gl.NO_ERROR, "render pass produced an OpenGL error")
	}
}
