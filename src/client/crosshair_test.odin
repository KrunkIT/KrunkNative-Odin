package main

import "base:runtime"
import "core:math"
import "core:testing"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import menuui "../menu"
import shared "../shared"

when ODIN_TEST {
	@(test)
	crosshair_geometry_and_validation :: proc(t: ^testing.T) {
		settings := menuui.DEFAULT_CROSSHAIR_SETTINGS
		boxes, count := menuui.crosshair_geometry(settings)
		testing.expect(t, count == 5 && abs(boxes[0].width-3.8)<0.0001 && abs(boxes[1].height-30.4)<0.0001, "Precision must use official thickness/length scaling and a center dot")
		testing.expect(t, abs(boxes[1].y+boxes[1].height+boxes[2].y)<0.0001 && abs(boxes[3].x+boxes[3].width+boxes[4].x)<0.0001, "opposing arms must stay symmetric")
		settings.values[.GAP] = -3
		boxes, count = menuui.crosshair_geometry(settings)
		testing.expect(t, abs(boxes[2].y-boxes[0].height*0.5)<0.0001, "gap -3 must make arms touch the dot using the official +3 gap offset")
		settings.values[.GAP] = -10
		boxes, count = menuui.crosshair_geometry(settings)
		testing.expect(t, boxes[2].y < 0 && boxes[4].x < 0, "negative gaps may overlap the center")
		settings.toggles[.DOT] = false
		_, count = menuui.crosshair_geometry(settings)
		testing.expect(t, count == 4)
		settings.values[.SIZE] = 0
		_, count = menuui.crosshair_geometry(settings)
		testing.expect(t, count == 0, "zero size and no dot must hide all geometry")
		settings.toggles[.DOT] = true
		_, count = menuui.crosshair_geometry(settings)
		testing.expect(t, count == 1, "zero size can leave only the center dot")
		settings.values[.THICKNESS] = 0
		_, count = menuui.crosshair_geometry(settings)
		testing.expect(t, count == 0)
		settings.values = {.OPACITY=math.nan_f32(), .SHADOW=math.inf_f32(1), .THICKNESS=-10, .SIZE=120, .GAP=-200}
		settings.kind, settings.color, settings.shadow_color = .IMAGE, 0xffaabbcc, 0xff112233
		valid := menuui.crosshair_settings_validate(settings)
		testing.expect(t, valid.values == [menuui.Crosshair_Control]f32{.OPACITY=1, .SHADOW=1, .THICKNESS=0, .SIZE=100, .GAP=-100} && valid.kind == .PRECISION && valid.color == 0xaabbcc && valid.shadow_color == 0x112233, "bad preferences must be bounded and Image must fall back to Precision")
		for text in ([]string{"#Aa00fF", "aa00ff", "  #AA00FF  "}) { value, ok := menuui.crosshair_parse_color(text); testing.expect(t, ok && value==0xaa00ff) }
		for text in ([]string{"", "#123", "#1234567", "#12ZZ56", "#-12345"}) { _, ok := menuui.crosshair_parse_color(text); testing.expect(t, !ok) }
	}

	@(test)
	crosshair_visibility_preview_and_cancel :: proc(t: ^testing.T) {
		weapon := shared.Weapon{scope=true}
		player := shared.Player{active=true, weapon=&weapon}
		client := Client{me=&player, crosshair_settings=menuui.DEFAULT_CROSSHAIR_SETTINGS}
		settings := client.crosshair_settings
		testing.expect(t, client_crosshair_opacity(&client, settings)==1)
		player.aim_val = 0.5
		testing.expect(t, client_crosshair_opacity(&client, settings)==0.5, "normal opacity follows the rendered ADS transition")
		player.aim_val = 1
		testing.expect(t, client_crosshair_opacity(&client, settings)==0, "the scope keeps its own reticle by default")
		settings.toggles[.ALWAYS_SHOW] = true
		testing.expect(t, client_crosshair_opacity(&client, settings)==1, "Always show must keep Precision visible during ADS")
		settings.toggles[.CUSTOM_OPACITY], settings.values[.OPACITY] = true, 0.3
		testing.expect(t, client_crosshair_opacity(&client, settings)==0.3, "custom opacity overrides Always show")
		settings.values[.OPACITY] = 0
		testing.expect(t, client_crosshair_opacity(&client, settings)==0, "zero custom opacity must hide the crosshair")
		settings = client.crosshair_settings
		player.aim_val, player.reload_timer = 0, 1
		testing.expect(t, client_crosshair_opacity(&client, settings)==0)
		player.reload_timer, player.inspecting = 0, true
		testing.expect(t, client_crosshair_opacity(&client, settings)==0)
		player.active, settings.toggles[.ALWAYS_SHOW] = false, true
		testing.expect(t, client_crosshair_opacity(&client, settings)==0, "Always show must not draw a crosshair without an active player")
		client.menu.page = .SETTINGS
		menuui.prepare_settings(&client.menu, {crosshair=client.crosshair_settings})
		menuui.activate(&client.menu, {action={kind=.CROSSHAIR_VALUE, index=i32(menuui.Crosshair_Control.GAP), value=-3}})
		testing.expect(t, client_crosshair_values(&client).values[.GAP]==-3 && client.crosshair_settings==menuui.DEFAULT_CROSSHAIR_SETTINGS, "preview changes must leave committed preferences intact")
		menuui.activate(&client.menu, {action={kind=.SETTINGS_CANCEL}})
		testing.expect(t, client_crosshair_values(&client)==menuui.DEFAULT_CROSSHAIR_SETTINGS, "Cancel must restore the committed crosshair")
	}

	@(test)
	crosshair_pixels :: proc(t: ^testing.T) {
		logger := context.logger
		context = runtime.default_context()
		context.logger = logger
		if !testing.expect(t, bool(glfw.Init())) do return
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(400, 400, "Precision crosshair", nil, nil)
		if !testing.expect(t, window != nil) do return
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		gl.Viewport(0,0,400,400)
		gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
		ui := ui_init()
		defer { ui_fini(ui); resource_cache_fini() }
		ui_update(ui, 400, 400)
		settings := menuui.DEFAULT_CROSSHAIR_SETTINGS
		settings.color, settings.shadow_color = 0x00ff00, 0xff0000
		settings.values[.THICKNESS], settings.values[.SIZE], settings.values[.GAP], settings.values[.SHADOW] = 4, 10, 5, 2
		gl.ClearColor(0,0,0,1)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		crosshair_render(ui, settings, 200, 200, 1, 0.5)
		pixel: [3]u8
		gl.ReadPixels(200,200,1,1,gl.RGB,gl.UNSIGNED_BYTE,&pixel[0])
		testing.expect(t, pixel[0]==0 && pixel[1]>=126 && pixel[1]<=129 && pixel[2]==0, "the dot must use the configured color and alpha")
		gl.ReadPixels(200,220,1,1,gl.RGB,gl.UNSIGNED_BYTE,&pixel[0])
		testing.expect(t, pixel[1]>=126 && pixel[0]==0, "the top arm must render at the expected gap/length")
		gl.ReadPixels(200,208,1,1,gl.RGB,gl.UNSIGNED_BYTE,&pixel[0])
		testing.expect(t, pixel==[3]u8{}, "positive gap must leave the expected empty space")
		gl.ReadPixels(195,220,1,1,gl.RGB,gl.UNSIGNED_BYTE,&pixel[0])
		testing.expect(t, pixel[0]>=126 && pixel[1]==0, "shadow must straddle the arm's edge with its own color")
		settings.toggles[.DOT] = false
		gl.Clear(gl.COLOR_BUFFER_BIT)
		crosshair_render(ui, settings, 200,200,1,1)
		gl.ReadPixels(200,200,1,1,gl.RGB,gl.UNSIGNED_BYTE,&pixel[0])
		testing.expect(t, pixel==[3]u8{}, "disabling the dot must leave the center empty")
		testing.expect(t, gl.GetError()==gl.NO_ERROR)
	}
}
