package main

import "core:math"
import gl "vendor:OpenGL"
import shared "../shared"

basic_shader_program: u32
quad_shader_program: u32
text_shader_program: u32

// Active map environment. It is updated when a map is loaded and consumed by
// the basic world material for every draw.
g_lighting_config: shared.Lighting_Config = shared.DEFAULT_LIGHTING_CONFIG

// Cached uniform locations. glGetUniformLocation is a driver-side string
// lookup; resolving each uniform once per program instead of once per mesh per
// frame removes tens of thousands of driver calls per frame on maps with
// 1000+ objects.
Shader_Uniforms :: struct {
	is_ramp:              i32,
	is_ladder:            i32,
	use_face_tex_scaling: i32,
	face_mask:            i32,
	texture_scale:        i32,
	unlit:                i32,
	world_uv_scale:       i32,
	face_scale:           i32,
	color:                i32,
	emissive:             i32,
	alpha_test:           i32,
	tex_transform:        i32,
	tex:                  i32,
	ambient_color:        i32,
	ambient_intensity:    i32,
	light_color:          i32,
	light_intensity:      i32,
	light_dir:            i32,
	fog_color:            i32,
	fog_near:             i32,
	fog_far:              i32,
	camera_position:      i32,
	aspect:               i32,
	r_clip:               i32,
	stroke_width:         i32,
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
	u.face_mask = gl.GetUniformLocation(program, "face_mask")
	u.texture_scale = gl.GetUniformLocation(program, "texture_scale")
	u.unlit = gl.GetUniformLocation(program, "unlit")
	u.world_uv_scale = gl.GetUniformLocation(program, "world_uv_scale")
	u.face_scale = gl.GetUniformLocation(program, "face_scale")
	u.color = gl.GetUniformLocation(program, "color")
	u.emissive = gl.GetUniformLocation(program, "emissive")
	u.alpha_test = gl.GetUniformLocation(program, "alpha_test")
	u.tex_transform = gl.GetUniformLocation(program, "tex_transform")
	u.tex = gl.GetUniformLocation(program, "tex")
	u.ambient_color = gl.GetUniformLocation(program, "uAmbientColor")
	u.ambient_intensity = gl.GetUniformLocation(program, "uAmbientIntensity")
	u.light_color = gl.GetUniformLocation(program, "uLightColor")
	u.light_intensity = gl.GetUniformLocation(program, "uLightIntensity")
	u.light_dir = gl.GetUniformLocation(program, "uLightDir")
	u.fog_color = gl.GetUniformLocation(program, "uFogColor")
	u.fog_near = gl.GetUniformLocation(program, "uFogNear")
	u.fog_far = gl.GetUniformLocation(program, "uFogFar")
	u.camera_position = gl.GetUniformLocation(program, "uCameraPosition")
	u.aspect = gl.GetUniformLocation(program, "aspect")
	u.r_clip = gl.GetUniformLocation(program, "r_clip")
	u.stroke_width = gl.GetUniformLocation(program, "stroke_width")
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
	gl.Uniform1i(u_basic.face_mask, i32(material.face_mask))
	gl.Uniform1f(u_basic.texture_scale, material.texture_scale)
	gl.Uniform1i(u_basic.unlit, i32(material.unlit))
	gl.Uniform1f(world_uv_scale, shared.GAME_CONSTANTS.world_uv_scale)
	gl.Uniform3f(face_scale, material.face_scale.x, material.face_scale.y, material.face_scale.z)

	color := u_basic.color
	emissive := u_basic.emissive
	tex_transform := u_basic.tex_transform
	texture := u_basic.tex

	c := math.cos(material.texture_rotation)
	s := math.sin(material.texture_rotation)
	// Match THREE.Texture.setUvTransform with its default center (0, 0).
	// Krunker stores `tro` in degrees and applies it clockwise in UV space.
	m00 := material.texture_repeat.x * c
	m01 := material.texture_repeat.x * s
	m10 := -material.texture_repeat.y * s
	m11 := material.texture_repeat.y * c
	tx := material.texture_offset.x
	ty := material.texture_offset.y
	transform := [3][3]f32{
		{m00, m01, tx},
		{m10, m11, ty},
		{0, 0, 1},
	}

	gl.Uniform4f(color, material.color.x, material.color.y, material.color.z, material.color.w)
	gl.Uniform4f(emissive, material.emissive.x, material.emissive.y, material.emissive.z, material.emissive.w)
	gl.Uniform1f(u_basic.alpha_test, material.alpha_test)

	// Current Krunker uses an ambient light plus a directional sky/sun light.
	// Keep the same angle convention as the browser's sceneInit (degrees,
	// negated before conversion to radians).
	light_x := g_lighting_config.light_distance * math.cos(-g_lighting_config.sun_angle_x * math.PI / 180.0)
	light_y := g_lighting_config.light_distance * math.sin(-g_lighting_config.sun_angle_x * math.PI / 180.0) * math.sin(-g_lighting_config.sun_angle_y * math.PI / 180.0)
	light_z := g_lighting_config.light_distance * math.sin(-g_lighting_config.sun_angle_x * math.PI / 180.0) * math.cos(-g_lighting_config.sun_angle_y * math.PI / 180.0)
	gl.Uniform3f(u_basic.ambient_color, g_lighting_config.ambient_color.x, g_lighting_config.ambient_color.y, g_lighting_config.ambient_color.z)
	gl.Uniform1f(u_basic.ambient_intensity, g_lighting_config.ambient_intensity)
	gl.Uniform3f(u_basic.light_color, g_lighting_config.light_color.x, g_lighting_config.light_color.y, g_lighting_config.light_color.z)
	gl.Uniform1f(u_basic.light_intensity, g_lighting_config.light_intensity)
	gl.Uniform3f(u_basic.light_dir, light_x, light_y, light_z)
	gl.Uniform3f(u_basic.fog_color, g_lighting_config.fog_color.x, g_lighting_config.fog_color.y, g_lighting_config.fog_color.z)
	gl.Uniform1f(u_basic.fog_near, 1.0)
	gl.Uniform1f(u_basic.fog_far, max(1.0, g_lighting_config.fog_distance))
	gl.Uniform3f(u_basic.camera_position, g_render_camera_position.x, g_render_camera_position.y, g_render_camera_position.z)

	transform_flat := flatten_mat3(transform)
	transform_ptr := transform_flat
	gl.UniformMatrix3fv(tex_transform, 1, gl.TRUE, &transform_ptr[0])
	gl.Uniform1i(texture, 0)
	gl.ActiveTexture(gl.TEXTURE0)
	if material.texture != 0 && g_active_texture == material.texture || material.texture == 0 && g_blank_texture != 0 && g_active_texture == g_blank_texture {
		return
	}

	if material.texture != 0 {
		gl.BindTexture(gl.TEXTURE_2D, material.texture)
		g_active_texture = material.texture
	} else {
		if g_blank_texture == 0 {
			gl.CreateTextures(gl.TEXTURE_2D, 1, &g_blank_texture)
			gl.BindTexture(gl.TEXTURE_2D, g_blank_texture)

			blank := [3]u8{255, 255, 255}
			gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, 1, 1, 0, gl.RGB, gl.UNSIGNED_BYTE, &blank[0])
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
			gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
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
	material.face_mask = 0x3f
	material.texture_scale = 1.0

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
	gl.Uniform1f(u_quad.stroke_width, material.stroke_width)

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
