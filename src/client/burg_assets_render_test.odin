package main

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:testing"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import shared "../shared"

when ODIN_TEST {
	@(test)
	burg_hosted_assets_render :: proc(t: ^testing.T) {
		context = runtime.default_context()
		if !testing.expect(t, bool(glfw.Init())) do return
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(1280, 720, "Burg hosted art", nil, nil)
		if !testing.expect(t, window != nil) do return
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
		client := Client{scene = scene_init()}
		g_client = &client
		old_lighting := g_lighting_config
		defer {
			client_unload_map(&client)
			shared.map_destroy(client.game.map_inst)
			scene_fini(client.scene)
			resource_cache_fini()
			g_client = nil
			g_lighting_config = old_lighting
		}
		map_inst, ok := shared.map_load_from_file("assets/maps/burg.json")
		if !testing.expect(t, ok && map_inst != nil) do return
		client.game.map_inst = map_inst
		client_load_current_map(&client)
		custom, trees, windows, foliage := 0, 0, 0, 0
		for object in map_inst.objects {
			raw, is_object := object.raw_data.(json.Object)
			if !is_object do continue
			aid, is_string := raw["aid"].(json.String)
			if !is_string || len(aid) == 0 do continue
			custom += 1
			if !testing.expect(t, object.mesh != nil, fmt.tprintf("Burg aid=%s must create a mesh", aid)) do continue
			mesh := cast(^Mesh)object.mesh
			testing.expect(t, mesh.geometry != nil && mesh.geometry.index_count > 0, "hosted models need triangles")
			material := cast(^Basic_Material)mesh.material
			gl.BindTexture(gl.TEXTURE_2D, material.texture)
			width: i32
			gl.GetTexLevelParameteriv(gl.TEXTURE_2D, 0, gl.TEXTURE_WIDTH, &width)
			testing.expect(t, material.texture != 0 && (width > 1 || aid == "27432g"), "hosted models must use original images rather than the white fallback")
			scale := shared.get_json_f32(raw["ms"])
			testing.expect(t, mesh.transform.scale == (shared.Vec3{scale, scale, scale}), "map ms must set hosted asset scale")
			switch aid {
			case "632nest": trees += 1
			case "2846": windows += 1
			case "27432g":
				foliage += 1
				testing.expect(t, mesh.geometry.index_count == 270, "static foliage must preserve all glTF triangles")
				vertices := make([]Vertex, int(mesh.geometry.index_count))
				gl.BindBuffer(gl.ARRAY_BUFFER, mesh.geometry.vbo)
				gl.GetBufferSubData(gl.ARRAY_BUFFER, 0, len(vertices)*size_of(Vertex), raw_data(vertices))
				min_y: f32 = 1000
				for vertex in vertices do min_y = min(min_y, vertex.position.y)
				testing.expect(t, abs(min_y - (-0.1519973)) < 0.00001, "glTF foliage must retain its authored vertical origin")
				delete(vertices)
			}
		}
		testing.expect(t, custom == 93 && trees == 17 && windows == 46 && foliage == 8, "every Burg hosted asset must be present")
		camera := camera_init(DEFAULT_WEAPON_FOV)
		camera.position = {-90, 220, 180}
		camera.rotation = {-0.48, -0.1, 0}
		w, h := i32(1280), i32(720)
		gl.Viewport(0, 0, w, h)
		before, after := make([]u8, int(w*h*3)), make([]u8, int(w*h*3))
		defer delete(before)
		defer delete(after)
		for pass in 0..<2 {
			for object in map_inst.objects {
				raw, is_object := object.raw_data.(json.Object)
				if is_object && raw["aid"] != nil && object.mesh != nil {
					(cast(^Mesh)object.mesh).visible = pass == 1
				}
			}
			gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
			scene_render(client.scene, &camera, f32(w), f32(h))
			pixels := before if pass == 0 else after
			gl.ReadPixels(0, 0, w, h, gl.RGB, gl.UNSIGNED_BYTE, raw_data(pixels))
		}
		changed := 0
		for value, index in after {
			if value != before[index] do changed += 1
		}
		testing.expect(t, changed > 3000, "restored art must visibly contribute to the Burg courtyard")
		testing.expect(t, gl.GetError() == gl.NO_ERROR, "Burg must render without OpenGL errors")
		when #config(WEAPON_PREVIEW, false) {
			file := make([dynamic]u8)
			append(&file, ..transmute([]u8)fmt.tprintf("P6\n%d %d\n255\n", w, h))
			for row := h-1; row >= 0; row -= 1 { append(&file, ..after[row*w*3:(row+1)*w*3]) }
			testing.expect(t, os.write_entire_file("bin/burg_restored.ppm", file[:]) == nil)
			delete(file)
		}
	}
}
