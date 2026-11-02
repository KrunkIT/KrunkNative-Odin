package main

import "base:runtime"
import "core:encoding/json"
import "core:math"
import "core:os"
import "core:testing"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import shared "../shared"

when ODIN_TEST {
	objective_test_render :: proc(scene: ^Scene, camera: ^Camera, y: i32) -> [4]u8 {
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
		scene_render(scene, camera, 320, 180)
		pixel: [4]u8
		gl.ReadPixels(160, y, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, &pixel[0])
		return pixel
	}

	@(test)
	objective_perimeter_renders_fade_without_covering_floor_or_writing_depth :: proc(t: ^testing.T) {
		context = runtime.default_context()
		if !testing.expect(t, bool(glfw.Init())) do return
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(320, 180, "Objective perimeter regression", nil, nil)
		if !testing.expect(t, window != nil) do return
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
		gl.Viewport(0, 0, 320, 180)
		gl.ClearColor(0, 0, 0, 1)
		scene := scene_init()
		defer { scene_fini(scene); resource_cache_fini() }
		raw := make(json.Object)
		defer delete(raw)
		object := shared.Object{prefab = .OBJECTIVE, objective = true, position = {0, 0, -30}, scale = {20, 30, 10}}
		mesh := prefab_init(&object, nil, raw)
		if !testing.expect(t, mesh != nil) do return
		defer mesh_fini(mesh)
		material := cast(^Basic_Material)mesh.material
		testing.expect(t, material.texture != 0, "the real objective texture must load")
		material.no_fog = true
		scene_add_mesh(scene, mesh)
		object.mesh = mesh
		map_inst := shared.Map{}
		append(&map_inst.objects, &object)
		defer delete(map_inst.objects)
		client := Client{}
		client.game.map_inst = &map_inst
		client.game.match.objective.active_object_index = -1
		client_update_objective_visuals(&client)
		camera := camera_init(math.PI/2)
		camera.position.y = 2.5
		hidden := objective_test_render(scene, &camera, 84)
		testing.expect(t, hidden[0] == 0, "inactive objectives must stay hidden")
		client.game.match.objective.active_object_index = 0
		client_update_objective_visuals(&client)
		lower := objective_test_render(scene, &camera, 84)
		upper := objective_test_render(scene, &camera, 96)
		testing.expect(t, lower[0] > 40 && lower[1] > lower[2] && lower[0] > upper[0]*3 && upper[0] > 0,
			"the yellow perimeter must fade upward across the wall instead of tiling or filling the floor")
		depth: f32
		gl.ReadPixels(160, 84, 1, 1, gl.DEPTH_COMPONENT, gl.FLOAT, &depth)
		testing.expect(t, depth == 1, "translucent objective walls must leave world depth untouched")
		depth_write: bool
		gl.GetBooleanv(gl.DEPTH_WRITEMASK, &depth_write)
		testing.expect(t, depth_write == gl.TRUE, "depth writes must be restored for subsequent render passes")
		camera.position.z = -30
		inside := objective_test_render(scene, &camera, 55)
		testing.expect(t, inside[0] > 30, "the perimeter must also be visible from inside the zone")
		camera.position.y = 20
		camera.rotation.x = -math.PI/2
		open_top := objective_test_render(scene, &camera, 90)
		testing.expect(t, open_top[0] == 0, "the zone must have no top or floor face")

		wall_material := basic_material_init()
		wall_material.unlit, wall_material.no_fog = true, true
		wall_material.color = {0, 0, 1, 1}
		wall := mesh_init(create_cube_geo(), &wall_material.base)
		defer mesh_fini(wall)
		wall.transform.position, wall.transform.scale = {0, -50, -10}, {100, 100, 1}
		scene_add_mesh(scene, wall)
		camera.position, camera.rotation = {0, 2.5, 0}, {}
		occluded := objective_test_render(scene, &camera, 84)
		testing.expect(t, occluded[0] == 0 && occluded[2] == 255, "solid map geometry must occlude the objective")
		wall.visible = false
		client.game.match.objective.active_object_index = -1
		client_update_objective_visuals(&client)
		rotated := objective_test_render(scene, &camera, 84)
		testing.expect(t, rotated[0] == 0, "rotating the objective must hide the old perimeter")

		when #config(OBJECTIVE_PREVIEW, false) {
			client.game.match.objective.active_object_index = 0
			client_update_objective_visuals(&client)
			wall.visible = true
			wall.transform.position, wall.transform.scale = {0, -1, -30}, {120, 1, 120}
			wall_material.color = {0.12, 0.14, 0.17, 1}
			camera.position, camera.rotation = {18, 12, -5}, {-0.32, 0.55, 0}
			objective_test_render(scene, &camera, 90)
			pixels := make([]u8, 320*180*3)
			defer delete(pixels)
			gl.ReadPixels(0, 0, 320, 180, gl.RGB, gl.UNSIGNED_BYTE, raw_data(pixels))
			file := make([dynamic]u8)
			defer delete(file)
			append(&file, "P6\n320 180\n255\n")
			for row := 179; row >= 0; row -= 1 { append(&file, ..pixels[row*320*3:(row+1)*320*3]) }
			testing.expect(t, os.write_entire_file("bin/objective-preview.ppm", file[:]) == nil)
		}
		testing.expect(t, gl.GetError() == gl.NO_ERROR, "objective rendering must preserve valid OpenGL state")
	}
}
