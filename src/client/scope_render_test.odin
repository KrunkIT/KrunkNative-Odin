package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:testing"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import shared "../shared"

when ODIN_TEST {
	@(test)
	scope_image_and_current_undergrowth_render :: proc(t: ^testing.T) {
		context = runtime.default_context()
		if !testing.expect(t, bool(glfw.Init())) do return
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(1280, 720, "Scope and Undergrowth", nil, nil)
		if !testing.expect(t, window != nil) do return
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
		ui := ui_init()
		client := Client{scene = scene_init(), ui = ui}
		g_client = &client
		old_lighting := g_lighting_config
		defer {
			client_unload_map(&client)
			shared.map_destroy(client.game.map_inst)
			scene_fini(client.scene)
			overlay_fini()
			ui_fini(ui)
			resource_cache_fini()
			g_client = nil
			g_lighting_config = old_lighting
		}
		map_inst, ok := shared.map_load_from_file("assets/maps/undergrowth.json")
		if !testing.expect(t, ok && map_inst != nil) do return
		client.game.map_inst = map_inst
		testing.expect(t, len(map_inst.objects) == 1371, "Undergrowth must use the current captured map")
		testing.expect(t, map_inst.objects[0].position == (shared.Vec3{-179, 67, 54}) && map_inst.objects[0].scale == (shared.Vec3{232, 2, 190}), "current map position and interned dimensions must load")
		client_load_current_map(&client)
		custom_meshes := 0
		for object in map_inst.objects {
			if object.mesh == nil { continue }
			mesh := cast(^Mesh)object.mesh
			if mesh.geometry != nil && len(mesh.geometry.cache_key) > 0 {
				if (cast(^Basic_Material)mesh.material).texture != 0 && object.prefab == .CUSTOM_ASSET { custom_meshes += 1 }
			}
		}
		testing.expect(t, custom_meshes == 16, "all current Undergrowth custom models must have textures")
		camera := camera_init(DEFAULT_WEAPON_FOV)
		camera.position = {60, 115, 210}
		camera.rotation = {-0.12, 0.3, 0}
		for dimensions in ([][2]i32{{1280, 720}, {1920, 1080}, {2560, 1600}}) {
			w, h := dimensions[0], dimensions[1]
			glfw.SetWindowSize(window, w, h)
			gl.Viewport(0, 0, w, h)
			gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
			scene_render(client.scene, &camera, f32(w), f32(h))
			ui_update(ui, f32(w), f32(h))
			overlay_scope_render(ui)
			testing.expect(t, scope_icon != 0, "the packaged default scope image must load")
			pixel: [3]u8
			gl.ReadPixels(0, h/2, 1, 1, gl.RGB, gl.UNSIGNED_BYTE, &pixel[0])
			testing.expect(t, pixel == ([3]u8{}), "scope borders must mask the sides on wide screens")
			gl.ReadPixels(w/2, h/2, 1, 1, gl.RGB, gl.UNSIGNED_BYTE, &pixel[0])
			testing.expect(t, pixel[0] < 20 && pixel[1] < 20 && pixel[2] < 20, "scope reticle must stay centered")
			testing.expect(t, gl.GetError() == gl.NO_ERROR, "map and scope must render without OpenGL errors")
			when #config(WEAPON_PREVIEW, false) {
				pixels := make([]u8, int(w*h*3))
				gl.ReadPixels(0, 0, w, h, gl.RGB, gl.UNSIGNED_BYTE, raw_data(pixels))
				file := make([dynamic]u8)
				append(&file, ..transmute([]u8)fmt.tprintf("P6\n%d %d\n255\n", w, h))
				for row := h-1; row >= 0; row -= 1 { append(&file, ..pixels[row*w*3:(row+1)*w*3]) }
				testing.expect(t, os.write_entire_file(fmt.tprintf("bin/undergrowth_scope_%d.ppm", w), file[:]) == nil)
				delete(file)
				delete(pixels)
			}
		}
	}
}
