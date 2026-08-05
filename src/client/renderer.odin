package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import gl "vendor:OpenGL"
import shared "../shared"

VERT_SRC :: `#version 330 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec3 aNormal;
layout (location = 2) in vec3 aColor;
layout (location = 3) in vec2 aTexCoord;

out vec3 FragPos;
out vec3 Normal;
out vec3 Color;
out vec2 TexCoord;

uniform mat4 uModel;
uniform mat4 uView;
uniform mat4 uProj;
uniform vec3 uObjScale;

void main() {
    FragPos = vec3(uModel * vec4(aPos, 1.0));
    Normal = mat3(transpose(inverse(uModel))) * aNormal;
    Color = aColor;
    
    // Scale UV coordinates by object dimensions for world-space texture tiling
    vec2 tile_scale = vec2(max(uObjScale.x, uObjScale.z) / 10.0, uObjScale.y / 10.0);
    if (tile_scale.x < 0.1) tile_scale.x = 1.0;
    if (tile_scale.y < 0.1) tile_scale.y = 1.0;
    TexCoord = aTexCoord * tile_scale;
    
    gl_Position = uProj * uView * vec4(FragPos, 1.0);
}
`

FRAG_SRC :: `#version 330 core
out vec4 FragColor;

in vec3 FragPos;
in vec3 Normal;
in vec3 Color;
in vec2 TexCoord;

uniform vec3 uLightDir;
uniform sampler2D uTexture;
uniform bool uUseTexture;
uniform vec4 uCustomColor;
uniform bool uUseCustomColor;

void main() {
    vec3 norm = normalize(Normal);
    vec3 lightDir = normalize(-uLightDir);
    float diff = max(dot(norm, lightDir), 0.45);
    vec4 baseColor = vec4(Color, 1.0);
    
    if (uUseCustomColor) {
        baseColor = uCustomColor;
    } else if (uUseTexture) {
        vec4 texColor = texture(uTexture, TexCoord);
        if (texColor.a < 0.1) discard;
        baseColor = texColor;
    }
    
    FragColor = vec4(baseColor.rgb * diff, baseColor.a);
}
`

Renderer :: struct {
	shader_program:      u32,
	u_model:             i32,
	u_view:              i32,
	u_proj:              i32,
	u_light_dir:         i32,
	u_texture:           i32,
	u_use_texture:       i32,
	u_obj_scale:         i32,
	u_custom_color:      i32,
	u_use_custom_color:  i32,
	cube_vao:            u32,
	cube_vbo:            u32,
	default_tex:         u32,
}

renderer_init :: proc() -> (r: Renderer, ok: bool) {
	vert_shader := gl.CreateShader(gl.VERTEX_SHADER)
	defer gl.DeleteShader(vert_shader)
	v_src := cstring(VERT_SRC)
	gl.ShaderSource(vert_shader, 1, &v_src, nil)
	gl.CompileShader(vert_shader)

	frag_shader := gl.CreateShader(gl.FRAGMENT_SHADER)
	defer gl.DeleteShader(frag_shader)
	f_src := cstring(FRAG_SRC)
	gl.ShaderSource(frag_shader, 1, &f_src, nil)
	gl.CompileShader(frag_shader)

	r.shader_program = gl.CreateProgram()
	gl.AttachShader(r.shader_program, vert_shader)
	gl.AttachShader(r.shader_program, frag_shader)
	gl.LinkProgram(r.shader_program)

	r.u_model = gl.GetUniformLocation(r.shader_program, "uModel")
	r.u_view = gl.GetUniformLocation(r.shader_program, "uView")
	r.u_proj = gl.GetUniformLocation(r.shader_program, "uProj")
	r.u_light_dir = gl.GetUniformLocation(r.shader_program, "uLightDir")
	r.u_texture = gl.GetUniformLocation(r.shader_program, "uTexture")
	r.u_use_texture = gl.GetUniformLocation(r.shader_program, "uUseTexture")
	r.u_obj_scale = gl.GetUniformLocation(r.shader_program, "uObjScale")
	r.u_custom_color = gl.GetUniformLocation(r.shader_program, "uCustomColor")
	r.u_use_custom_color = gl.GetUniformLocation(r.shader_program, "uUseCustomColor")

	// Cube vertices with normals, vertex colors, and UVs
	cube_vertices := [?]f32{
		// pos              // normal           // color         // uv
		// Back face
		-0.5, -0.5, -0.5,  0.0,  0.0, -1.0,  0.8, 0.8, 0.8,   0.0, 0.0,
		 0.5, -0.5, -0.5,  0.0,  0.0, -1.0,  0.8, 0.8, 0.8,   1.0, 0.0,
		 0.5,  0.5, -0.5,  0.0,  0.0, -1.0,  0.8, 0.8, 0.8,   1.0, 1.0,
		 0.5,  0.5, -0.5,  0.0,  0.0, -1.0,  0.8, 0.8, 0.8,   1.0, 1.0,
		-0.5,  0.5, -0.5,  0.0,  0.0, -1.0,  0.8, 0.8, 0.8,   0.0, 1.0,
		-0.5, -0.5, -0.5,  0.0,  0.0, -1.0,  0.8, 0.8, 0.8,   0.0, 0.0,

		// Front face
		-0.5, -0.5,  0.5,  0.0,  0.0,  1.0,  0.9, 0.9, 0.9,   0.0, 0.0,
		 0.5, -0.5,  0.5,  0.0,  0.0,  1.0,  0.9, 0.9, 0.9,   1.0, 0.0,
		 0.5,  0.5,  0.5,  0.0,  0.0,  1.0,  0.9, 0.9, 0.9,   1.0, 1.0,
		 0.5,  0.5,  0.5,  0.0,  0.0,  1.0,  0.9, 0.9, 0.9,   1.0, 1.0,
		-0.5,  0.5,  0.5,  0.0,  0.0,  1.0,  0.9, 0.9, 0.9,   0.0, 1.0,
		-0.5, -0.5,  0.5,  0.0,  0.0,  1.0,  0.9, 0.9, 0.9,   0.0, 0.0,

		// Left face
		-0.5,  0.5,  0.5, -1.0,  0.0,  0.0,  0.85, 0.85, 0.85, 1.0, 0.0,
		-0.5,  0.5, -0.5, -1.0,  0.0,  0.0,  0.85, 0.85, 0.85, 1.0, 1.0,
		-0.5, -0.5, -0.5, -1.0,  0.0,  0.0,  0.85, 0.85, 0.85, 0.0, 1.0,
		-0.5, -0.5, -0.5, -1.0,  0.0,  0.0,  0.85, 0.85, 0.85, 0.0, 1.0,
		-0.5, -0.5,  0.5, -1.0,  0.0,  0.0,  0.85, 0.85, 0.85, 0.0, 0.0,
		-0.5,  0.5,  0.5, -1.0,  0.0,  0.0,  0.85, 0.85, 0.85, 1.0, 0.0,

		// Right face
		 0.5,  0.5,  0.5,  1.0,  0.0,  0.0,  0.85, 0.85, 0.85, 1.0, 0.0,
		 0.5,  0.5, -0.5,  1.0,  0.0,  0.0,  0.85, 0.85, 0.85, 1.0, 1.0,
		 0.5, -0.5, -0.5,  1.0,  0.0,  0.0,  0.85, 0.85, 0.85, 0.0, 1.0,
		 0.5, -0.5, -0.5,  1.0,  0.0,  0.0,  0.85, 0.85, 0.85, 0.0, 1.0,
		 0.5, -0.5,  0.5,  1.0,  0.0,  0.0,  0.85, 0.85, 0.85, 0.0, 0.0,
		 0.5,  0.5,  0.5,  1.0,  0.0,  0.0,  0.85, 0.85, 0.85, 1.0, 0.0,

		// Bottom face
		-0.5, -0.5, -0.5,  0.0, -1.0,  0.0,  0.7, 0.7, 0.7,   0.0, 1.0,
		 0.5, -0.5, -0.5,  0.0, -1.0,  0.0,  0.7, 0.7, 0.7,   1.0, 1.0,
		 0.5, -0.5,  0.5,  0.0, -1.0,  0.0,  0.7, 0.7, 0.7,   1.0, 0.0,
		 0.5, -0.5,  0.5,  0.0, -1.0,  0.0,  0.7, 0.7, 0.7,   1.0, 0.0,
		-0.5, -0.5,  0.5,  0.0, -1.0,  0.0,  0.7, 0.7, 0.7,   0.0, 0.0,
		-0.5, -0.5, -0.5,  0.0, -1.0,  0.0,  0.7, 0.7, 0.7,   0.0, 1.0,

		// Top face
		-0.5,  0.5, -0.5,  0.0,  1.0,  0.0,  1.0, 1.0, 1.0,   0.0, 1.0,
		 0.5,  0.5, -0.5,  0.0,  1.0,  0.0,  1.0, 1.0, 1.0,   1.0, 1.0,
		 0.5,  0.5,  0.5,  0.0,  1.0,  0.0,  1.0, 1.0, 1.0,   1.0, 0.0,
		 0.5,  0.5,  0.5,  0.0,  1.0,  0.0,  1.0, 1.0, 1.0,   1.0, 0.0,
		-0.5,  0.5,  0.5,  0.0,  1.0,  0.0,  1.0, 1.0, 1.0,   0.0, 0.0,
		-0.5,  0.5, -0.5,  0.0,  1.0,  0.0,  1.0, 1.0, 1.0,   0.0, 1.0,
	}

	gl.GenVertexArrays(1, &r.cube_vao)
	gl.GenBuffers(1, &r.cube_vbo)

	gl.BindVertexArray(r.cube_vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, r.cube_vbo)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(cube_vertices), &cube_vertices[0], gl.STATIC_DRAW)

	stride := i32(11 * size_of(f32))
	gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, stride, 0)
	gl.EnableVertexAttribArray(0)

	gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, stride, uintptr(3 * size_of(f32)))
	gl.EnableVertexAttribArray(1)

	gl.VertexAttribPointer(2, 3, gl.FLOAT, gl.FALSE, stride, uintptr(6 * size_of(f32)))
	gl.EnableVertexAttribArray(2)

	gl.VertexAttribPointer(3, 2, gl.FLOAT, gl.FALSE, stride, uintptr(9 * size_of(f32)))
	gl.EnableVertexAttribArray(3)

	gl.BindVertexArray(0)

	return r, true
}

renderer_draw_box :: proc(r: ^Renderer, pos, scale: shared.Vec3, view, proj: shared.Mat4, texture_id: u32 = 0) {
	gl.UseProgram(r.shader_program)

	// Map JSON positions use the bottom centre of a box (y = floor level),
	// while this cube mesh is centred vertically around its origin.
	box_pos := pos + shared.Vec3{0, scale.y * 0.5, 0}
	model := linalg.matrix4_translate_f32(box_pos) * linalg.matrix4_scale_f32(scale)

	m_mat := model
	v_mat := view
	p_mat := proj
	s_vec := scale
	light_dir := shared.Vec3{-0.5, -1.0, -0.3}

	gl.UniformMatrix4fv(r.u_model, 1, gl.FALSE, &m_mat[0, 0])
	gl.UniformMatrix4fv(r.u_view, 1, gl.FALSE, &v_mat[0, 0])
	gl.UniformMatrix4fv(r.u_proj, 1, gl.FALSE, &p_mat[0, 0])
	gl.Uniform3fv(r.u_light_dir, 1, &light_dir[0])
	gl.Uniform3fv(r.u_obj_scale, 1, &s_vec[0])
	gl.Uniform1i(r.u_use_custom_color, 0)

	use_tex := texture_id != 0
	gl.Uniform1i(r.u_use_texture, i32(use_tex ? 1 : 0))

	if use_tex {
		gl.ActiveTexture(gl.TEXTURE0)
		gl.BindTexture(gl.TEXTURE_2D, texture_id)
		gl.Uniform1i(r.u_texture, 0)
	}

	gl.BindVertexArray(r.cube_vao)
	gl.DrawArrays(gl.TRIANGLES, 0, 36)
	gl.BindVertexArray(0)
}

renderer_draw_part :: proc(r: ^Renderer, pos, scale: shared.Vec3, color: shared.Vec4, view, proj: shared.Mat4) {
	gl.UseProgram(r.shader_program)

	model := linalg.matrix4_translate_f32(pos) * linalg.matrix4_scale_f32(scale)

	m_mat := model
	v_mat := view
	p_mat := proj
	s_vec := scale
	c_vec := color
	light_dir := shared.Vec3{-0.5, -1.0, -0.3}

	gl.UniformMatrix4fv(r.u_model, 1, gl.FALSE, &m_mat[0, 0])
	gl.UniformMatrix4fv(r.u_view, 1, gl.FALSE, &v_mat[0, 0])
	gl.UniformMatrix4fv(r.u_proj, 1, gl.FALSE, &p_mat[0, 0])
	gl.Uniform3fv(r.u_light_dir, 1, &light_dir[0])
	gl.Uniform3fv(r.u_obj_scale, 1, &s_vec[0])
	gl.Uniform1i(r.u_use_texture, 0)
	gl.Uniform1i(r.u_use_custom_color, 1)
	gl.Uniform4fv(r.u_custom_color, 1, &c_vec[0])

	gl.BindVertexArray(r.cube_vao)
	gl.DrawArrays(gl.TRIANGLES, 0, 36)
	gl.BindVertexArray(0)
}

renderer_draw_gun :: proc(r: ^Renderer, player: ^shared.Player, view, proj: shared.Mat4) {
	gl.UseProgram(r.shader_program)
	gl.Clear(gl.DEPTH_BUFFER_BIT)

	// Fixed view matrix in camera space for first person view model
	view_fp := linalg.MATRIX4F32_IDENTITY

	// ADS (Aim Down Sights) Animation interpolation using player.aim_val (0.0 = Hipfire, 1.0 = ADS)
	aim_t := player != nil ? player.aim_val : 0.0
	recoil_t := player != nil ? player.recoil_anim_y : 0.0

	// Hipfire position: Offset to bottom right of screen
	hip_pos := shared.Vec3{0.32, -0.26, -0.60}
	// ADS position: Centered on screen for precision aiming
	ads_pos := shared.Vec3{0.0, -0.16, -0.42}

	gun_origin := linalg.lerp(hip_pos, ads_pos, aim_t)
	gun_origin.z += recoil_t * 0.08 // Recoil kick backwards
	gun_origin.y += recoil_t * 0.04 // Recoil kick upwards

	// Colors for iconic Krunker AK-47 model
	c_metal := shared.Vec4{0.18, 0.18, 0.20, 1.0}   // Dark gun metal
	c_steel := shared.Vec4{0.30, 0.30, 0.33, 1.0}   // Steel receiver/barrel
	c_wood  := shared.Vec4{0.55, 0.27, 0.07, 1.0}   // Wooden stock & handguard
	c_mag   := shared.Vec4{0.65, 0.35, 0.10, 1.0}   // Bakelite AK magazine (orange-brown)

	// 1. AK Receiver Body
	rec_pos := gun_origin + shared.Vec3{0.0, 0.0, 0.0}
	rec_scale := shared.Vec3{0.09, 0.11, 0.40}
	renderer_draw_part(r, rec_pos, rec_scale, c_metal, view_fp, proj)

	// 2. Wooden Handguard / Fore-end
	guard_pos := gun_origin + shared.Vec3{0.0, -0.01, -0.28}
	guard_scale := shared.Vec3{0.08, 0.09, 0.22}
	renderer_draw_part(r, guard_pos, guard_scale, c_wood, view_fp, proj)

	// 3. AK Barrel & Gas Tube
	bar_pos := gun_origin + shared.Vec3{0.0, 0.01, -0.48}
	bar_scale := shared.Vec3{0.035, 0.035, 0.25}
	renderer_draw_part(r, bar_pos, bar_scale, c_steel, view_fp, proj)

	// Front sight post
	sight_pos := gun_origin + shared.Vec3{0.0, 0.045, -0.58}
	sight_scale := shared.Vec3{0.015, 0.04, 0.03}
	renderer_draw_part(r, sight_pos, sight_scale, c_metal, view_fp, proj)

	// Rear iron sight
	rear_sight_pos := gun_origin + shared.Vec3{0.0, 0.07, -0.16}
	rear_sight_scale := shared.Vec3{0.02, 0.025, 0.04}
	renderer_draw_part(r, rear_sight_pos, rear_sight_scale, c_metal, view_fp, proj)

	// 4. Curved Bakelite AK Magazine
	mag_pos := gun_origin + shared.Vec3{0.0, -0.14, -0.12}
	mag_scale := shared.Vec3{0.05, 0.18, 0.08}
	renderer_draw_part(r, mag_pos, mag_scale, c_mag, view_fp, proj)

	// 5. Wooden Rifle Stock
	stock_pos := gun_origin + shared.Vec3{0.0, -0.02, 0.25}
	stock_scale := shared.Vec3{0.08, 0.12, 0.22}
	renderer_draw_part(r, stock_pos, stock_scale, c_wood, view_fp, proj)
}
