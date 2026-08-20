package main

import "core:fmt"
import "core:math"
import "core:strings"
import core_c "core:c"
import gl "vendor:OpenGL"
import stbtt "vendor:stb/truetype"
import shared "../shared"

g_font_info: stbtt.fontinfo
g_font_loaded: bool
g_font_data: []byte

load_glyph :: proc(c: u8) -> ^Glyph_Cache_Entry {
	if cached, ok := g_glyph_cache[c]; ok {
		return cached
	}

	glyph := new(Glyph_Cache_Entry)

	// Font is loaded lazily from assets (matches C's freetype usage).
	if !g_font_loaded {
		load_font()
	}

	if !g_font_loaded {
		free(glyph)
		return nil
	}

	scale := stbtt.ScaleForPixelHeight(&g_font_info, 100)
	advance_width, left_side_bearing: core_c.int
	stbtt.GetCodepointHMetrics(&g_font_info, rune(c), &advance_width, &left_side_bearing)

	width, height, xoff, yoff: core_c.int
	bitmap := stbtt.GetCodepointBitmap(&g_font_info, scale, scale, rune(c), &width, &height, &xoff, &yoff)

	if bitmap != nil && width > 0 && height > 0 {
		gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
		gl.GenTextures(1, &glyph.texture)
		gl.BindTexture(gl.TEXTURE_2D, glyph.texture)

		gl.TexImage2D(
			gl.TEXTURE_2D, 0, gl.RED,
			width, height,
			0, gl.RED, gl.UNSIGNED_BYTE,
			bitmap,
		)

		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

		gl.PixelStorei(gl.UNPACK_ALIGNMENT, 4)
		stbtt.FreeBitmap(bitmap, nil)
	}

	glyph.size.x = f32(width)
	glyph.size.y = f32(height)
	// Convert stb's baseline-relative offsets into the bearing convention used
	// by the original FreeType UI implementation.
	glyph.h_bearing = shared.Vec2{f32(xoff), -f32(yoff)}
	glyph.advance = f32(advance_width) * scale

	g_glyph_cache[c] = glyph
	return glyph
}

load_font :: proc() {
	if g_font_loaded {
		return
	}

	font_path := shared.concat(shared.assets_path(), "css/fonts/font2.ttf")
	font_data, ok := shared.read_file(font_path)
	delete(font_path)

	if ok {
		g_font_data = font_data
		g_font_loaded = bool(stbtt.InitFont(&g_font_info, &g_font_data[0], 0))
	}
}

ui_init :: proc() -> ^UI {
	ui := new(UI)

	ui.material = quad_material_init()
	ui.text_material = text_material_init()

	gl.GenBuffers(1, &ui.vbo)

	gl.GenVertexArrays(1, &ui.vao)
	gl.BindVertexArray(ui.vao)

	vertices := [?]Vertex{
		{{-1.0, -1.0, 0.0}, {0.0, 0.0}},
		{{1.0, -1.0, 0.0}, {1.0, 0.0}},
		{{1.0, 1.0, 0.0}, {1.0, 1.0}},
		{{-1.0, 1.0, 0.0}, {0.0, 1.0}},
	}

	gl.BindBuffer(gl.ARRAY_BUFFER, ui.vbo)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), &vertices[0], gl.STATIC_DRAW)

	stride := i32(size_of(Vertex))

	gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, stride, 0)
	gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, stride, uintptr(3 * size_of(f32)))

	gl.EnableVertexAttribArray(0)
	gl.EnableVertexAttribArray(1)

	return ui
}

ui_update :: proc(ui: ^UI, width, height: f32) {
	ui.width = width
	ui.height = height

	scale_factor: f32 = 1.5
	target_width: f32 = scale_factor * 1700.0
	target_height: f32 = scale_factor * 900.0

	scale_x := ui.width / target_width
	scale_y := ui.height / target_height

	ui.scale = min(scale_x, scale_y)

	gl.Disable(gl.DEPTH_TEST)
	gl.Enable(gl.BLEND)
	gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)
}

ui_fill_rect_ :: proc(ui: ^UI, shader: u32, x, y, width, height: f32) {
	offset_x := (x + width * 0.5) / ui.width * 2.0 - 1.0
	offset_y := 1.0 - (y + height * 0.5) / ui.height * 2.0

	scale_x := width / ui.width
	scale_y := height / ui.height

	u := scene_uniforms(shader)

	gl.BindVertexArray(ui.vao)

	if u.offset > -1 {
		gl.Uniform2f(u.offset, offset_x, offset_y)
	}
	if u.scale > -1 {
		gl.Uniform2f(u.scale, scale_x, scale_y)
	}

	gl.DrawArrays(gl.TRIANGLE_FAN, 0, 4)
}

ui_fill_rect :: proc(ui: ^UI, color: shared.Vec4, x, y, width, height: f32) {
	ui.material.color = color
	ui.material.texture = 0

	ui.material.texture_viewport = [4]f32{0.0, 0.0, 1.0, 1.0}

	ui.material.border_bottom_left_radius = 0.0
	ui.material.border_bottom_right_radius = 0.0
	ui.material.border_top_left_radius = 0.0
	ui.material.border_top_right_radius = 0.0

	ui.material.r_clip = 0.0

	if g_active_shader != ui.material.base.program {
		gl.UseProgram(ui.material.base.program)
		g_active_shader = ui.material.base.program
	}

	material_update_uniforms(&ui.material.base)

	ui_fill_rect_(ui, ui.material.base.program, x, y, width, height)
}

ui_round_rect :: proc(ui: ^UI, color: shared.Vec4, x, y, width, height, radius: f32) {
	ui.material.color = color
	ui.material.texture = 0

	ui.material.texture_viewport = [4]f32{0.0, 0.0, 1.0, 1.0}

	radius_mlt := radius / min(width, height)

	ui.material.aspect = width / height
	ui.material.border_bottom_left_radius = radius_mlt
	ui.material.border_bottom_right_radius = radius_mlt
	ui.material.border_top_left_radius = radius_mlt
	ui.material.border_top_right_radius = radius_mlt

	ui.material.r_clip = 0.0

	if g_active_shader != ui.material.base.program {
		gl.UseProgram(ui.material.base.program)
		g_active_shader = ui.material.base.program
	}

	material_update_uniforms(&ui.material.base)

	ui_fill_rect_(ui, ui.material.base.program, x, y, width, height)
}

ui_fill_rect_rclip :: proc(ui: ^UI, color: shared.Vec4, x, y, width, height, radius, r_clip: f32) {
	ui.material.color = color
	ui.material.texture = 0

	ui.material.texture_viewport = [4]f32{0.0, 0.0, 1.0, 1.0}

	radius_mlt := radius / min(width, height)

	ui.material.aspect = width / height
	ui.material.border_bottom_left_radius = radius_mlt
	ui.material.border_bottom_right_radius = radius_mlt
	ui.material.border_top_left_radius = radius_mlt
	ui.material.border_top_right_radius = radius_mlt

	ui.material.r_clip = r_clip

	if g_active_shader != ui.material.base.program {
		gl.UseProgram(ui.material.base.program)
		g_active_shader = ui.material.base.program
	}

	material_update_uniforms(&ui.material.base)

	ui_fill_rect_(ui, ui.material.base.program, x, y, width, height)
}

ui_draw_image :: proc(ui: ^UI, texture_id: u32, x, y, width, height: f32) {
	ui.material.color = shared.Vec4{1.0, 1.0, 1.0, 1.0}
	ui.material.texture = texture_id

	ui.material.texture_viewport = [4]f32{0.0, 0.0, 1.0, 1.0}

	ui.material.border_bottom_left_radius = 0.0
	ui.material.border_bottom_right_radius = 0.0
	ui.material.border_top_left_radius = 0.0
	ui.material.border_top_right_radius = 0.0

	ui.material.r_clip = 0.0

	if g_active_shader != ui.material.base.program {
		gl.UseProgram(ui.material.base.program)
		g_active_shader = ui.material.base.program
	}

	material_update_uniforms(&ui.material.base)

	ui_fill_rect_(ui, ui.material.base.program, x, y, width, height)
}

ui_draw_image_rounded :: proc(ui: ^UI, texture_id: u32, x, y, width, height, radius: f32) {
	ui.material.color = shared.Vec4{1.0, 1.0, 1.0, 1.0}
	ui.material.texture = texture_id

	ui.material.texture_viewport = [4]f32{0.0, 0.0, 1.0, 1.0}

	radius_mlt := radius / min(width, height)

	ui.material.aspect = width / height
	ui.material.border_bottom_left_radius = radius_mlt
	ui.material.border_bottom_right_radius = radius_mlt
	ui.material.border_top_left_radius = radius_mlt
	ui.material.border_top_right_radius = radius_mlt

	ui.material.r_clip = 0.0

	if g_active_shader != ui.material.base.program {
		gl.UseProgram(ui.material.base.program)
		g_active_shader = ui.material.base.program
	}

	material_update_uniforms(&ui.material.base)

	ui_fill_rect_(ui, ui.material.base.program, x, y, width, height)
}

ui_measure_text :: proc(ui: ^UI, text: string, size: f32) -> f32 {
	width: f32 = 0

	for c in text {
		glyph := load_glyph(u8(c))
		if glyph == nil {
			continue
		}

		width += glyph.advance * size / 100.0
	}

	return width
}

ui_fill_text :: proc(ui: ^UI, color: shared.Vec4, text: string, x, y, size: f32) -> f32 {
	start_x := x
	cursor_x := x

	ui.text_material.color = color
	gl.BindVertexArray(ui.vao)

	if g_active_shader != ui.text_material.base.program {
		gl.UseProgram(ui.text_material.base.program)
		g_active_shader = ui.text_material.base.program
	}

	for c in text {
		glyph := load_glyph(u8(c))

		if glyph == nil {
			continue
		}

		if c != ' ' {
			ui.text_material.texture = glyph.texture
			material_update_uniforms(&ui.text_material.base)

			glyph_y := y - glyph.h_bearing.y * size / 100.0
			ui_fill_rect_(ui, ui.text_material.base.program, cursor_x - glyph.h_bearing.x * size / 100.0, glyph_y, glyph.size.x * size / 100.0, glyph.size.y * size / 100.0)
		}

		cursor_x += glyph.advance * size / 100.0
	}

	return cursor_x - start_x
}

ui_fini :: proc(ui: ^UI) {
	if ui == nil {
		return
	}

	for _, glyph in g_glyph_cache {
		if glyph.texture != 0 {
			gl.DeleteTextures(1, &glyph.texture)
		}
		free(glyph)
	}
	delete(g_glyph_cache)

	if ui.vao != 0 {
		gl.DeleteVertexArrays(1, &ui.vao)
	}
	if ui.vbo != 0 {
		gl.DeleteBuffers(1, &ui.vbo)
	}
	material_fini(&ui.material.base)
	material_fini(&ui.text_material.base)
	delete(g_font_data)
	g_font_data = nil
	g_font_loaded = false
	free(ui)
}
