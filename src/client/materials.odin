package main

import gl "vendor:OpenGL"
import shared "../shared"

basic_shader_program: u32
quad_shader_program: u32
text_shader_program: u32

// Cached uniform locations. glGetUniformLocation is a driver-side string
// lookup; resolving each uniform once per program instead of once per mesh per
// frame removes tens of thousands of driver calls per frame on maps with
// 1000+ objects.
Shader_Uniforms :: struct {
	is_ramp:              i32,
	is_ladder:            i32,
	use_face_tex_scaling: i32,
	world_uv_scale:       i32,
	face_scale:           i32,
	color:                i32,
	emissive:             i32,
	tex_transform:        i32,
	tex:                  i32,
	aspect:               i32,
	r_clip:               i32,
	border_bottom_left_radius:  i32,
	border_bottom_right_radius: i32,
	border_top_left_radius:     i32,
	border_top_right_radius:    i32,
	tex_viewport:          i32,
	transform:             i32,
	camera_world_inverse:  i32,
	camera_projection:     i32,
	offset:                i32,
	scale:                 i32,
}

u_basic: Shader_Uniforms
u_quad:  Shader_Uniforms
u_text:  Shader_Uniforms

cache_uniforms :: proc(program: u32) -> Shader_Uniforms {
	u := Shader_Uniforms{}
	u.is_ramp = gl.GetUniformLocation(program, "is_ramp")
	u.is_ladder = gl.GetUniformLocation(program, "is_ladder")
	u.use_face_tex_scaling = gl.GetUniformLocation(program, "use_face_tex_scaling")
	u.world_uv_scale = gl.GetUniformLocation(program, "world_uv_scale")
	u.face_scale = gl.GetUniformLocation(program, "face_scale")
	u.color = gl.GetUniformLocation(program, "color")
	u.emissive = gl.GetUniformLocation(program, "emissive")
	u.tex_transform = gl.GetUniformLocation(program, "tex_transform")
	u.tex = gl.GetUniformLocation(program, "tex")
	u.aspect = gl.GetUniformLocation(program, "aspect")
	u.r_clip = gl.GetUniformLocation(program, "r_clip")
	u.border_bottom_left_radius = gl.GetUniformLocation(program, "border_bottom_left_radius")
	u.border_bottom_right_radius = gl.GetUniformLocation(program, "border_bottom_right_radius")
	u.border_top_left_radius = gl.GetUniformLocation(program, "border_top_left_radius")
	u.border_top_right_radius = gl.GetUniformLocation(program, "border_top_right_radius")
	u.tex_viewport = gl.GetUniformLocation(program, "tex_viewport")
	u.transform = gl.GetUniformLocation(program, "transform")
	u.camera_world_inverse = gl.GetUniformLocation(program, "camera_world_inverse")
	u.camera_projection = gl.GetUniformLocation(program, "camera_projection")
	u.offset = gl.GetUniformLocation(program, "offset")
	u.scale = gl.GetUniformLocation(program, "scale")
	return u
}

basic_material_update_uniforms :: proc(mat: rawptr) {
	material := cast(^Basic_Material)mat

	is_ramp := u_basic.is_ramp
	is_ladder := u_basic.is_ladder
	use_face_tex_scaling := u_basic.use_face_tex_scaling
	world_uv_scale := u_basic.world_uv_scale
	face_scale := u_basic.face_scale

	gl.Uniform1i(is_ramp, i32(material.is_ramp ? 1 : 0))
	gl.Uniform1i(is_ladder, i32(material.is_ladder ? 1 : 0))
	gl.Uniform1i(use_face_tex_scaling, i32(material.use_face_tex_scaling ? 1 : 0))
	gl.Uniform1f(world_uv_scale, shared.GAME_CONSTANTS.world_uv_scale)
	gl.Uniform3f(face_scale, material.face_scale.x, material.face_scale.y, material.face_scale.z)

	color := u_basic.color
	emissive := u_basic.emissive
	tex_transform := u_basic.tex_transform
	texture := u_basic.tex

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
		u_basic = cache_uniforms(basic_shader_program)

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

	color := u_quad.color
	aspect := u_quad.aspect
	r_clip := u_quad.r_clip

	border_bottom_left_radius := u_quad.border_bottom_left_radius
	border_bottom_right_radius := u_quad.border_bottom_right_radius
	border_top_left_radius := u_quad.border_top_left_radius
	border_top_right_radius := u_quad.border_top_right_radius

	texture := u_quad.tex
	texture_viewport := u_quad.tex_viewport

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
		u_quad = cache_uniforms(quad_shader_program)

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

	color := u_text.color
	texture := u_text.tex

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
		u_text = cache_uniforms(text_shader_program)

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
