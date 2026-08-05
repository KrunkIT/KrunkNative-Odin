package main

import "core:fmt"
import gl "vendor:OpenGL"
import shared "../shared"

shader_compile :: proc(vertex_shader_path, fragment_shader_path: string) -> u32 {
	vertex_shader, v_ok := shared.read_file(vertex_shader_path)
	fragment_shader, f_ok := shared.read_file(fragment_shader_path)

	if !v_ok || !f_ok {
		return 0
	}

	defer delete(vertex_shader)
	defer delete(fragment_shader)

	v_src := string(vertex_shader)
	f_src := string(fragment_shader)

	vert := gl.CreateShader(gl.VERTEX_SHADER)
	frag := gl.CreateShader(gl.FRAGMENT_SHADER)

	v_cstr := cstring(raw_data(v_src))
	f_cstr := cstring(raw_data(f_src))

	gl.ShaderSource(vert, 1, &v_cstr, nil)
	gl.CompileShader(vert)

	status: i32
	gl.GetShaderiv(vert, gl.COMPILE_STATUS, &status)

	if status == 0 {
		error: [512]u8
		gl.GetShaderInfoLog(vert, 512, nil, &error[0])
		fmt.printf("vertex shader compile error (%s):\n %s \n", vertex_shader_path, cstring(&error[0]))

		gl.DeleteShader(vert)
		gl.DeleteShader(frag)
		return 0
	}

	gl.ShaderSource(frag, 1, &f_cstr, nil)
	gl.CompileShader(frag)

	gl.GetShaderiv(frag, gl.COMPILE_STATUS, &status)

	if status == 0 {
		error: [512]u8
		gl.GetShaderInfoLog(frag, 512, nil, &error[0])
		fmt.printf("fragment shader compile error (%s):\n %s \n", fragment_shader_path, cstring(&error[0]))

		gl.DeleteShader(vert)
		gl.DeleteShader(frag)
		return 0
	}

	program := gl.CreateProgram()

	gl.AttachShader(program, vert)
	gl.AttachShader(program, frag)

	gl.LinkProgram(program)

	gl.DeleteShader(vert)
	gl.DeleteShader(frag)

	gl.GetProgramiv(program, gl.LINK_STATUS, &status)

	if status == 0 {
		error: [512]u8
		gl.GetProgramInfoLog(program, 512, nil, &error[0])
		fmt.printf("shader link error (%s, %s):\n %s \n", vertex_shader_path, fragment_shader_path, cstring(&error[0]))

		gl.DeleteProgram(program)
		return 0
	}

	return program
}
