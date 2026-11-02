package main

import gl "vendor:OpenGL"
import shared "../shared"

// Screen position and OpenGL clip depth from the world camera. The weapon
// camera has a separate FOV and must never move an overhead bar.
player_healthbar_project :: proc(view_projection: shared.Mat4, point: shared.Vec3, width, height: f32) -> (shared.Vec3, bool) {
	clip := view_projection * shared.Vec4{point.x, point.y, point.z, 1}
	if clip.w <= 0 || abs(clip.x) > clip.w || abs(clip.y) > clip.w || abs(clip.z) > clip.w { return {}, false }
	ndc := shared.Vec3{clip.x, clip.y, clip.z} / clip.w
	return {(ndc.x+1)*width*0.5, (1-ndc.y)*height*0.5, ndc.z}, true
}

player_healthbars_render :: proc(client: ^Client) {
	if !client.in_game || !client.mouse_state.locked || client.me == nil || !client.me.active ||
		client.ui == nil || len(client.game.players) < 2 || client.game.config.hide_nametags ||
		client.viewport_width <= 0 || client.viewport_height <= 0 { return }

	ui := client.ui
	ui_update(ui, f32(client.viewport_width), f32(client.viewport_height))
	// This pass runs against the world's depth buffer before it is cleared
	// for the view model. The GPU hides bars behind actual map geometry, with
	// no per-player collision scans or depth-buffer readbacks on the CPU.
	gl.Enable(gl.DEPTH_TEST)
	gl.DepthMask(gl.FALSE)
	if g_active_shader != ui.material.base.program {
		gl.UseProgram(ui.material.base.program)
		g_active_shader = ui.material.base.program
	}
	defer {
		gl.Uniform1f(u_quad.depth, 0)
		gl.DepthMask(gl.TRUE)
		gl.Disable(gl.DEPTH_TEST)
	}
	view_projection := client.camera.projection_matrix * client.camera.world_inverse_matrix
	for player in client.game.players {
		if player == nil || player == client.me || player.is_you || !player.active || player.health <= 0 || player.max_health <= 0 { continue }
		point := player.position + shared.Vec3{0, player.height + 1.8, 0}
		screen, visible := player_healthbar_project(view_projection, point, ui.width, ui.height)
		if !visible { continue }
		view_point := client.camera.world_inverse_matrix * shared.Vec4{point.x, point.y, point.z, 1}
		s := ui.scale * clamp(160 / -view_point.z, 0.55, 1)
		width, height := 110*s, 10*s
		border := max(1, 2*s)
		left, top := screen.x-width*0.5, screen.y-height-4*s
		progress := clamp(player.health/f32(player.max_health), 0, 1)
		friendly := client.me.team != 0 && player.team == client.me.team
		color := shared.hex_to_vec(friendly ? 0x9eeb56 : 0xff4444)
		gl.Uniform1f(u_quad.depth, screen.z)
		ui_fill_rect(ui, {0, 0, 0, 0.85}, left-border, top-border, width+2*border, height+2*border)
		ui_fill_rect(ui, {0.15, 0.15, 0.15, 1}, left, top, width, height)
		ui_fill_rect(ui, color, left, top, width*progress, height)
	}
}
