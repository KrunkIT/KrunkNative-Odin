package main

import gl "vendor:OpenGL"
import shared "../shared"

basic_shader_program: u32
quad_shader_program: u32
text_shader_program: u32

basic_material_update_uniforms :: proc(mat: rawptr) {
	material := cast(^Basic_Material)mat

	is_ramp := gl.GetUniformLocation(material.base.program, "is_ramp")
	is_ladder := gl.GetUniformLocation(material.base.program, "is_ladder")
	use_face_tex_scaling := gl.GetUniformLocation(material.base.program, "use_face_tex_scaling")
	world_uv_scale := gl.GetUniformLocation(material.base.program, "world_uv_scale")
	face_scale := gl.GetUniformLocation(material.base.program, "face_scale")

	gl.Uniform1i(is_ramp, i32(material.is_ramp ? 1 : 0))
	gl.Uniform1i(is_ladder, i32(material.is_ladder ? 1 : 0))
	gl.Uniform1i(use_face_tex_scaling, i32(material.use_face_tex_scaling ? 1 : 0))
	gl.Uniform1f(world_uv_scale, shared.GAME_CONSTANTS.world_uv_scale)
	gl.Uniform3f(face_scale, material.face_scale.x, material.face_scale.y, material.face_scale.z)

	color := gl.GetUniformLocation(material.base.program, "color")
	emissive := gl.GetUniformLocation(material.base.program, "emissive")
	tex_transform := gl.GetUniformLocation(material.base.program, "tex_transform")
	texture := gl.GetUniformLocation(material.base.program, "tex")

	repeat := [3][3]f32{
		{material.texture_repeat.x, 0, 0},
		{0, material.texture_repeat.y, 0},
		{0, 0, 1},
	}

	translate := [3][3]f32{
		{1, 0, material.texture_offset.x},
		{0, 1, material.texture_offset.y},
		{0, 0, 1},
	}

	transform := shared.mat3x3(flatten_mat3(repeat), flatten_mat3(translate))

	gl.Uniform4f(color, material.color.x, material.color.y, material.color.z, material.color.w)
	gl.Uniform4f(emissive, material.emissive.x, material.emissive.y, material.emissive.z, material.emissive.w)

	if material.texture != 0 && g_active_texture == material.texture || material.texture == 0 && g_blank_texture != 0 && g_active_texture == g_blank_texture {
		return
	}

	transform_ptr := [9]f32{transform[0], transform[1], transform[2], transform[3], transform[4], transform[5], transform[6], transform[7], transform[8]}
	gl.UniformMatrix3fv(tex_transform, 1, gl.TRUE, &transform_ptr[0])
	gl.Uniform1i(texture, 0)
	gl.ActiveTexture(gl.TEXTURE0)

	if material.texture != 0 {
		gl.BindTexture(gl.TEXTURE_2D, material.texture)
		g_active_texture = material.texture
	} else {
		if g_blank_texture == 0 {
			gl.CreateTextures(gl.TEXTURE_2D, 1, &g_blank_texture)
			gl.BindTexture(gl.TEXTURE_2D, g_blank_texture)

			blank := [3]u8{255, 255, 255}
			gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, 1, 1, 0, gl.RGB, gl.UNSIGNED_BYTE, &blank[0])
		}

		gl.BindTexture(gl.TEXTURE_2D, g_blank_texture)
		g_active_texture = g_blank_texture
	}
}

flatten_mat3 :: proc(m: [3][3]f32) -> [9]f32 {
	return [9]f32{m[0][0], m[0][1], m[0][2], m[1][0], m[1][1], m[1][2], m[2][0], m[2][1], m[2][2]}
}

basic_material_vtable := Material_VTable{update_uniforms = basic_material_update_uniforms}

basic_material_init :: proc() -> ^Basic_Material {
	material := new(Basic_Material)
	material.base.vtable = &basic_material_vtable

	material.color = shared.Vec4{1.0, 1.0, 1.0, 1.0}

	material.texture_repeat = shared.Vec2{1.0, 1.0}

	if basic_shader_program == 0 {
		vert_shader := shared.concat(shared.assets_path(), "shaders/basic.vert")
		frag_shader := shared.concat(shared.assets_path(), "shaders/basic.frag")

		basic_shader_program = shader_compile(vert_shader, frag_shader)

		delete(vert_shader)
		delete(frag_shader)
	}

	if basic_shader_program == 0 {
		free(material)
		return nil
	}

	material.base.program = basic_shader_program
	return material
}

quad_material_update_uniforms :: proc(mat: rawptr) {
	material := cast(^Quad_Material)mat

	color := gl.GetUniformLocation(material.base.program, "color")
	aspect := gl.GetUniformLocation(material.base.program, "aspect")
	r_clip := gl.GetUniformLocation(material.base.program, "r_clip")

	border_bottom_left_radius := gl.GetUniformLocation(material.base.program, "border_bottom_left_radius")
	border_bottom_right_radius := gl.GetUniformLocation(material.base.program, "border_bottom_right_radius")
	border_top_left_radius := gl.GetUniformLocation(material.base.program, "border_top_left_radius")
	border_top_right_radius := gl.GetUniformLocation(material.base.program, "border_top_right_radius")

	texture := gl.GetUniformLocation(material.base.program, "tex")
	texture_viewport := gl.GetUniformLocation(material.base.program, "tex_viewport")

	gl.Uniform4f(color, material.color.x, material.color.y, material.color.z, material.color.w)
	gl.Uniform1f(aspect, material.aspect)
	gl.Uniform1f(r_clip, material.r_clip)

	gl.Uniform1f(border_bottom_left_radius, material.border_bottom_left_radius)
	gl.Uniform1f(border_bottom_right_radius, material.border_bottom_right_radius)
	gl.Uniform1f(border_top_left_radius, material.border_top_left_radius)
	gl.Uniform1f(border_top_right_radius, material.border_top_right_radius)

	if material.texture != 0 && g_active_texture == material.texture || material.texture == 0 && g_blank_texture != 0 && g_active_texture == g_blank_texture {
		return
	}

	gl.Uniform1fv(texture_viewport, 4, &material.texture_viewport[0])
	gl.Uniform1i(texture, 0)
	gl.ActiveTexture(gl.TEXTURE0)

	if material.texture != 0 {
		gl.BindTexture(gl.TEXTURE_2D, material.texture)
		g_active_texture = material.texture
	} else {
		if g_blank_texture == 0 {
			gl.CreateTextures(gl.TEXTURE_2D, 1, &g_blank_texture)
			gl.BindTexture(gl.TEXTURE_2D, g_blank_texture)

			blank := [3]u8{255, 255, 255}
			gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, 1, 1, 0, gl.RGB, gl.UNSIGNED_BYTE, &blank[0])
		}

		gl.BindTexture(gl.TEXTURE_2D, g_blank_texture)
		g_active_texture = g_blank_texture
	}
}

quad_material_vtable := Material_VTable{update_uniforms = quad_material_update_uniforms}

quad_material_init :: proc() -> ^Quad_Material {
	material := new(Quad_Material)
	material.base.vtable = &quad_material_vtable

	if quad_shader_program == 0 {
		vert_shader := shared.concat(shared.assets_path(), "shaders/quad.vert")
		frag_shader := shared.concat(shared.assets_path(), "shaders/quad.frag")

		quad_shader_program = shader_compile(vert_shader, frag_shader)

		delete(vert_shader)
		delete(frag_shader)
	}

	if quad_shader_program == 0 {
		free(material)
		return nil
	}

	material.base.program = quad_shader_program
	return material
}

text_material_update_uniforms :: proc(mat: rawptr) {
	material := cast(^Text_Material)mat

	color := gl.GetUniformLocation(material.base.program, "color")
	texture := gl.GetUniformLocation(material.base.program, "tex")

	gl.Uniform4f(color, material.color.x, material.color.y, material.color.z, material.color.w)

	if material.texture != 0 && g_active_texture == material.texture || material.texture == 0 && g_blank_texture != 0 && g_active_texture == g_blank_texture {
		return
	}

	gl.Uniform1i(texture, 0)
	gl.ActiveTexture(gl.TEXTURE0)

	if material.texture != 0 {
		gl.BindTexture(gl.TEXTURE_2D, material.texture)
		g_active_texture = material.texture
	} else {
		if g_blank_texture == 0 {
			gl.CreateTextures(gl.TEXTURE_2D, 1, &g_blank_texture)
			gl.BindTexture(gl.TEXTURE_2D, g_blank_texture)

			blank := [3]u8{255, 255, 255}
			gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, 1, 1, 0, gl.RGB, gl.UNSIGNED_BYTE, &blank[0])
		}

		gl.BindTexture(gl.TEXTURE_2D, g_blank_texture)
		g_active_texture = g_blank_texture
	}
}

text_material_vtable := Material_VTable{update_uniforms = text_material_update_uniforms}

text_material_init :: proc() -> ^Text_Material {
	material := new(Text_Material)
	material.base.vtable = &text_material_vtable

	if text_shader_program == 0 {
		vert_shader := shared.concat(shared.assets_path(), "shaders/quad.vert")
		frag_shader := shared.concat(shared.assets_path(), "shaders/text.frag")

		text_shader_program = shader_compile(vert_shader, frag_shader)

		delete(vert_shader)
		delete(frag_shader)
	}

	if text_shader_program == 0 {
		free(material)
		return nil
	}

	material.base.program = text_shader_program
	return material
}
