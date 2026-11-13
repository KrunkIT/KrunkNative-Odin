package main

import "core:testing"
import "core:math"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import menuui "../menu"
import shared "../shared"

when ODIN_TEST {
	@(test)
	graphics_defaults_map_changes_and_drafts :: proc(t: ^testing.T) {
		visuals := menuui.DEFAULT_VISUAL_SETTINGS
		visuals.values[.FOG_DISTANCE] = 2
		visuals.color_override[.SKY], visuals.colors[.SKY] = true, {0.4,0.5,0.6}
		visuals.values[.GAMMA] = 2
		validated := menuui.visual_settings_validate(visuals)
		testing.expect(t, validated.values[.GAMMA] == 2 && validated.values[.FOG_DISTANCE] == 1 && validated.color_override == menuui.DEFAULT_VISUAL_SETTINGS.color_override && validated.colors == menuui.DEFAULT_VISUAL_SETTINGS.colors,
			"retired color overrides and fog distance must be neutralized without losing allowed preferences")
		testing.expect(t, abs(visual_adjust_color({0.25,0.25,0.25}, visuals).x-0.5) < 0.00001)
		visuals.values[.BRIGHTNESS] = math.nan_f32()
		visuals.values[.FOG_DISTANCE] = -1
		validated = menuui.visual_settings_validate(visuals)
		testing.expect(t, validated.values[.BRIGHTNESS] == 1 && validated.values[.FOG_DISTANCE] == 1, "invalid persisted graphics settings must be finite and bounded")
		testing.expect(t, client_supported_quality({anisotropy=16}, 4).anisotropy == 4 && client_supported_quality({anisotropy=16}, 1).anisotropy == 0, "quality choices must respect GPU capabilities")
		client := Client{visual_settings=menuui.DEFAULT_VISUAL_SETTINGS}
		view := menuui.View{visuals=client.visual_settings}
		client.menu.page = .SETTINGS
		menuui.prepare_settings(&client.menu, view)
		menuui.activate(&client.menu, {action={kind=.VISUAL_VALUE, index=i32(menuui.Visual_Control.FOG_DISTANCE), value=4}})
		testing.expect(t, client.menu.settings_draft.visuals.values[.FOG_DISTANCE] == 1, "settings actions must not change fog distance")
		menuui.activate(&client.menu, {action={kind=.VISUAL_VALUE, index=i32(menuui.Visual_Control.CONTRAST), value=1.2}})
		preview, _ := client_graphics_values(&client)
		testing.expect(t, preview.values[.CONTRAST] == 1.2 && client.visual_settings == menuui.DEFAULT_VISUAL_SETTINGS, "graphics previews must not overwrite committed preferences")
		menuui.activate(&client.menu, {action={kind=.SETTINGS_CANCEL}})
		reverted, _ := client_graphics_values(&client)
		testing.expect(t, reverted == menuui.DEFAULT_VISUAL_SETTINGS, "Cancel must restore committed rendering settings immediately")
		client.menu.page = .SETTINGS
		menuui.prepare_settings(&client.menu, view)
		menuui.activate(&client.menu, {action={kind=.VISUAL_VALUE, index=i32(menuui.Visual_Control.CONTRAST), value=1.3}})
		menuui.activate(&client.menu, {action={kind=.VISUAL_RESET}})
		testing.expect(t, client.menu.settings_draft.visuals.values == menuui.DEFAULT_VISUAL_SETTINGS.values && !client.menu.settings_draft.visuals.color_override[.SKY], "Reset must stage neutral settings and restore map colors")
	}

	@(test)
	graphics_shader_preview_and_sampler_isolation :: proc(t: ^testing.T) {
		if !testing.expect(t, bool(glfw.Init())) do return
		defer glfw.Terminate()
		glfw.DefaultWindowHints()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(64, 64, "Graphics regression", nil, nil)
		if !testing.expect(t, window != nil) do return
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		gl.Viewport(0,0,64,64)
		client := Client{visual_settings=menuui.DEFAULT_VISUAL_SETTINGS}
		client_graphics_init(&client)
		defer client_graphics_fini(&client)
		old_visuals, old_lighting := g_visual_settings, g_lighting_config
		defer { g_visual_settings, g_lighting_config = old_visuals, old_lighting }
		scene := scene_init()
		material := basic_material_init()
		if !testing.expect(t, material != nil) do return
		material.unlit, material.no_fog, material.color = true, true, {1,0,0,1}
		mesh := mesh_init(create_cube_geo(), &material.base)
		mesh.transform.position, mesh.transform.scale = {0,-1,-5}, {2,2,2}
		scene_add_mesh(scene, mesh)
		defer { mesh_fini(mesh); scene_fini(scene); resource_cache_fini() }
		camera := camera_init(math.PI/2)
		map_inst := shared.Map{lighting=shared.DEFAULT_LIGHTING_CONFIG}
		client.game.map_inst = &map_inst
		client.visual_settings.values[.FOG_DISTANCE] = 4
		for group in menuui.Visual_Color { client.visual_settings.color_override[group] = true; client.visual_settings.colors[group] = {1,0,0} }
		client_update_graphics(&client)
		testing.expect(t, g_lighting_config == map_inst.lighting, "retired saved overrides must never change the map environment")
		map_inst.lighting.fog_distance, map_inst.lighting.sky_color = 800, {0.1,0.2,0.3}
		client_update_graphics(&client)
		testing.expect(t, g_lighting_config == map_inst.lighting, "fog distance and environment colors must follow the current map")
		client.visual_settings = menuui.DEFAULT_VISUAL_SETTINGS
		client_update_graphics(&client)
		scene_test_pixel(t, scene, &camera, 32,32, {255,0,0})
		client.visual_settings.values[.SATURATION] = 0
		client_update_graphics(&client)
		scene_test_pixel(t, scene, &camera, 32,32, {54,54,54})
		client.visual_settings = menuui.DEFAULT_VISUAL_SETTINGS
		client.visual_settings.values[.GAMMA] = 2
		material.color = {0.25,0.25,0.25,1}
		client_update_graphics(&client)
		scene_test_pixel(t, scene, &camera, 32,32, {128,128,128})
		client.menu.page, client.menu.settings_active = .SETTINGS, true
		client.menu.settings_draft.visuals = menuui.DEFAULT_VISUAL_SETTINGS
		client.menu.settings_draft.visuals.values[.BRIGHTNESS] = 0.5
		client.menu.settings_draft.quality = {smooth_textures=true, anisotropy=16}
		client_update_graphics(&client)
		scene_test_pixel(t, scene, &camera, 32,32, {32,32,32})
		filter: i32
		gl.GetSamplerParameteriv(client.graphics_sampler, gl.TEXTURE_MIN_FILTER, &filter)
		testing.expect(t, filter == gl.LINEAR_MIPMAP_LINEAR && !client.quality_settings.smooth_textures, "quality changes must preview without modifying saved settings")
		scene_render(scene, &camera, 64,64, client.graphics_sampler)
		bound: i32
		gl.GetIntegerv(gl.SAMPLER_BINDING, &bound)
		testing.expect(t, bound == 0, "world texture filtering must not leak into HUD or menu fonts")
		menuui.activate(&client.menu, {action={kind=.SETTINGS_CANCEL}})
		client_update_graphics(&client)
		scene_test_pixel(t, scene, &camera, 32,32, {128,128,128})
		gl.GetSamplerParameteriv(client.graphics_sampler, gl.TEXTURE_MAG_FILTER, &filter)
		testing.expect(t, filter == gl.NEAREST, "Cancel must restore sharp filtering")
		client.visual_settings = menuui.DEFAULT_VISUAL_SETTINGS
		client.visual_settings.values[.AMBIENT] = 0.5
		client_update_graphics(&client)
		g_lighting_config.ambient_color, g_lighting_config.ambient_intensity, g_lighting_config.light_intensity = {1,1,1}, 1, 0
		material.unlit, material.color = false, {0.5,0.5,0.5,1}
		scene_test_pixel(t, scene, &camera, 32,32, {64,64,64})
		testing.expect(t, gl.GetError() == gl.NO_ERROR, "graphics preview and filtering must not generate OpenGL errors")
	}
}
