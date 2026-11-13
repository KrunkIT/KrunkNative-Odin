package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:testing"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import shared "../shared"

when ODIN_TEST {
	match_hud_snapshot :: proc(client: ^Client, pixels: []u8) {
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
		ui_update(client.ui, f32(client.viewport_width), f32(client.viewport_height))
		overlay_render(client, 0)
		gl.ReadPixels(0, 0, client.viewport_width, client.viewport_height, gl.RGB, gl.UNSIGNED_BYTE, raw_data(pixels))
	}
	match_hud_region_delta :: proc(client: ^Client, before, after: []u8, x1, y1, x2, y2: f32) -> int {
		changes := 0
		for y in int(y1*client.ui.scale)..<int(y2*client.ui.scale) {
			for x in int(x1*client.ui.scale)..<int(x2*client.ui.scale) {
				offset := ((int(client.viewport_height)-1-y)*int(client.viewport_width)+x)*3
				if before[offset] != after[offset] || before[offset+1] != after[offset+1] || before[offset+2] != after[offset+2] { changes += 1 }
			}
		}
		return changes
	}

	@(test)
	match_hud_separates_round_wins_from_objective_points :: proc(t: ^testing.T) {
		logger := context.logger
		context = runtime.default_context()
		context.logger = logger
		if !testing.expect(t, bool(glfw.Init())) { return }
		defer glfw.Terminate()
		glfw.WindowHint(glfw.VISIBLE, glfw.FALSE)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		window := glfw.CreateWindow(1280, 720, "Match HUD", nil, nil)
		if !testing.expect(t, window != nil) { return }
		defer glfw.DestroyWindow(window)
		glfw.MakeContextCurrent(window)
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
		gl.ClearColor(0.16, 0.18, 0.20, 1)
		// Render independently of the hidden window's desktop-backed buffer size.
		framebuffer, color_texture: u32
		gl.GenFramebuffers(1, &framebuffer)
		gl.GenTextures(1, &color_texture)
		defer gl.DeleteFramebuffers(1, &framebuffer)
		defer gl.DeleteTextures(1, &color_texture)
		gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer)
		mode := shared.Game_Mode{objective=true}
		client := Client{ui=ui_init(), krunker={connected=true}, game={mode=&mode}}
		defer { overlay_fini(); ui_fini(client.ui); resource_cache_fini() }
		client.krunker_world.rounds_total = 3
		for size in ([?][2]i32{{1280,720},{1920,1080},{2560,1600}}) {
			gl.BindTexture(gl.TEXTURE_2D, color_texture)
			gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB8, size[0], size[1], 0, gl.RGB, gl.UNSIGNED_BYTE, nil)
			gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, color_texture, 0)
			if !testing.expect(t, gl.CheckFramebufferStatus(gl.FRAMEBUFFER) == gl.FRAMEBUFFER_COMPLETE) { return }
			gl.BindTexture(gl.TEXTURE_2D, 0)
			g_active_texture = 0
			client.viewport_width, client.viewport_height = size[0], size[1]
			gl.Viewport(0, 0, size[0], size[1])
			client.game.match = {phase=.LIVE, round_current=1, time_remaining=180, objective={active_zone=-1, rotation_remaining=42}, team_scores={0,80,620}}
			before := make([]u8, int(size[0]*size[1]*3))
			after := make([]u8, len(before))
			defer delete(before)
			defer delete(after)
			match_hud_snapshot(&client, before)
			client.game.match.team_scores = {0,190,450}
			match_hud_snapshot(&client, after)
			left_delta, center_delta := 0, 0
			for row in 0..<int(200*client.ui.scale) {
				for x in 0..<int(size[0]) {
					offset := ((int(size[1])-1-row)*int(size[0])+x)*3
					if before[offset] == after[offset] && before[offset+1] == after[offset+1] && before[offset+2] == after[offset+2] { continue }
					if x < int(240*client.ui.scale) { left_delta += 1 }
					else { center_delta += 1 }
				}
			}
			testing.expect(t, left_delta > 0 && center_delta == 0, "objective point changes must only update the totals under the timer, even without a mapped objective")
			copy(before, after)
			client.game.match.round_wins = {0,1,2}
			match_hud_snapshot(&client, after)
			left_delta, center_delta = 0, 0
			for row in 0..<int(200*client.ui.scale) {
				for x in 0..<int(size[0]) {
					offset := ((int(size[1])-1-row)*int(size[0])+x)*3
					if before[offset] == after[offset] && before[offset+1] == after[offset+1] && before[offset+2] == after[offset+2] { continue }
					if x < int(240*client.ui.scale) { left_delta += 1 }
					else { center_delta += 1 }
				}
			}
			testing.expect(t, left_delta == 0 && center_delta > 0, "round wins must update the center scoreboard independently of objective points")
			copy(before, after)
			for option in 0..<3 {
				client.hud_settings = {hide_timer = option == 0, hide_round_score = option == 1, hide_game_score = option == 2}
				match_hud_snapshot(&client, after)
				timer_delta := match_hud_region_delta(&client, before, after, 0, 0, 240, 100)
				points_delta := match_hud_region_delta(&client, before, after, 0, 104, 240, 224)
				center := client.ui.width/client.ui.scale*0.5
				wins_delta := match_hud_region_delta(&client, before, after, center-240, 0, center+240, 104)
				testing.expectf(t, (timer_delta > 0) == (option == 0) && (points_delta > 0) == (option == 1) && (wins_delta > 0) == (option == 2),
					"HUD toggle %d must hide its own element independently (timer=%d points=%d wins=%d)", option, timer_delta, points_delta, wins_delta)
			}
			client.hud_settings = {}
			match_hud_snapshot(&client, after)
			when #config(HUD_PREVIEW, false) {
				file := make([dynamic]u8)
				defer delete(file)
				append(&file, ..transmute([]u8)fmt.tprintf("P6\n%d %d\n255\n", size[0], size[1]))
				for row := int(size[1])-1; row >= 0; row -= 1 { append(&file, ..after[row*int(size[0])*3:(row+1)*int(size[0])*3]) }
				testing.expect(t, os.write_entire_file(fmt.tprintf("bin/match-hud-%dx%d.ppm", size[0],size[1]), file[:]) == nil)
			}
		}
		testing.expect(t, gl.GetError() == gl.NO_ERROR)
	}
}
