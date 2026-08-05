package main

import "core:fmt"
import "core:math"
import "core:strings"
import gl "vendor:OpenGL"
import stbi "vendor:stb/image"
import shared "../shared"

// NOTE: obj loading needs a cstring; keep it simple & allocate per call
load_obj_model :: proc(path: string, transform_y: bool) -> ^Geometry {
	if cached, ok := g_geometry_cache[path]; ok {
		cached.ref_count += 1
		cached.last_used = resource_touch()
		return cached
	}

	obj_data, ok := shared.read_file(path)
	if !ok {
		fmt.eprintf("Failed to read obj: %s\n", path)
		return nil
	}
	defer delete(obj_data)

	vertices := parse_obj(obj_data, transform_y)
	if vertices == nil {
		return nil
	}
	defer delete(vertices)

	geometry := new(Geometry)

	vao, vbo, ebo: u32
	gl.GenVertexArrays(1, &vao)
	gl.GenBuffers(1, &vbo)
	gl.GenBuffers(1, &ebo)

	gl.BindVertexArray(vao)

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(Vertex), &vertices[0], gl.STATIC_DRAW)

	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo)

	indices := make([]u32, len(vertices))
	defer delete(indices)
	for i in 0 ..< len(vertices) {
		indices[i] = u32(i)
	}

	gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), &indices[0], gl.STATIC_DRAW)

	stride := i32(size_of(Vertex))

	gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, stride, 0)
	gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, stride, uintptr(3 * size_of(f32)))

	gl.EnableVertexAttribArray(0)
	gl.EnableVertexAttribArray(1)

	geometry.vao = vao
	geometry.vbo = vbo
	geometry.ebo = ebo
	geometry.index_count = i32(len(indices))
	geometry.cache_key = strings.clone(path)
	geometry.ref_count = 1
	geometry.last_used = resource_touch()

	g_geometry_cache[geometry.cache_key] = geometry
	resource_trim_geometry_cache()

	return geometry
}

OBJ_Index :: struct {
	position: int,
	texcoord: int,
}

// Minimal OBJ parser (positions + independent texcoords, triangulated faces).
parse_obj :: proc(data: []byte, transform_y: bool) -> []Vertex {
	positions: [dynamic]shared.Vec3
	texcoords: [dynamic]shared.Vec2
	out: [dynamic]Vertex

	text := string(data)
	lines := strings.split_lines(text)
	defer delete(lines)

	bounds_min := shared.Vec3{9999.0, 9999.0, 9999.0}

	for line in lines {
		fields := strings.fields(line)
		if len(fields) == 0 {
			continue
		}

		switch fields[0] {
		case "v":
			if len(fields) >= 4 {
				append(&positions, shared.Vec3{
					strconv_f32(fields[1]),
					strconv_f32(fields[2]),
					strconv_f32(fields[3]),
				})
			}
		case "vt":
			if len(fields) >= 3 {
				append(&texcoords, shared.Vec2{
					strconv_f32(fields[1]),
					strconv_f32(fields[2]),
				})
			}
		case "f":
			// face indices are 1-based; support v or v/vt or v//vn
			if len(fields) >= 4 {
				face_idx := make([]OBJ_Index, len(fields) - 1)
				defer delete(face_idx)

				for i in 1 ..< len(fields) {
					parts := strings.split(fields[i], "/")

					if len(parts) > 0 {
						face_idx[i - 1].position = atoi_safe(parts[0])
					}
					if len(parts) > 1 && len(parts[1]) > 0 {
						face_idx[i - 1].texcoord = atoi_safe(parts[1])
					}

					delete(parts)
				}

				// triangulate fan
				for i := 1; i + 1 < len(face_idx); i += 1 {
					v0 := get_vertex(positions, texcoords, face_idx[0], &bounds_min)
					v1 := get_vertex(positions, texcoords, face_idx[i], &bounds_min)
					v2 := get_vertex(positions, texcoords, face_idx[i + 1], &bounds_min)

					append(&out, v0, v1, v2)
				}
			}
		}
	}

	delete(positions)
	delete(texcoords)

	if transform_y {
		for i in 0 ..< len(out) {
			out[i].position.y -= bounds_min.y
		}
	}

	return out[:]
}

get_vertex :: proc(
	positions: [dynamic]shared.Vec3,
	texcoords: [dynamic]shared.Vec2,
	index: OBJ_Index,
	bounds_min: ^shared.Vec3,
) -> Vertex {
	vertex := Vertex{}

	position_index := resolve_obj_index(index.position, len(positions))
	if position_index >= 0 && position_index < len(positions) {
		pos := positions[position_index]
		vertex.position = pos

		if pos.x < bounds_min.x {
			bounds_min.x = pos.x
		}
		if pos.y < bounds_min.y {
			bounds_min.y = pos.y
		}
		if pos.z < bounds_min.z {
			bounds_min.z = pos.z
		}
	}

	texcoord_index := resolve_obj_index(index.texcoord, len(texcoords))
	if texcoord_index >= 0 && texcoord_index < len(texcoords) {
		vertex.tex_coord = texcoords[texcoord_index]
	}

	return vertex
}

resolve_obj_index :: proc(index, count: int) -> int {
	if index > 0 {
		return index - 1
	}
	if index < 0 {
		return count + index
	}

	return -1
}

strconv_f32 :: proc(s: string) -> f32 {
	f, _ := strconv_parse_f32(s)
	return f
}

strconv_parse_f32 :: proc(s: string) -> (f32, bool) {
	if len(s) == 0 {
		return 0, false
	}

	// use fmt/parse for accuracy
	val, ok := parse_float(s)
	return val, ok
}

parse_float :: proc(s: string) -> (f32, bool) {
	// simple fallback: use the standard library via strconv
	// (implemented as a tiny helper to avoid pulling heavy deps)
	val: f32
	neg := false
	idx := 0

	if idx < len(s) && (s[idx] == '-' || s[idx] == '+') {
		neg = s[idx] == '-'
		idx += 1
	}

	int_part: f32
	has_digit := false

	for idx < len(s) && s[idx] >= '0' && s[idx] <= '9' {
		int_part = int_part * 10 + f32(s[idx] - '0')
		idx += 1
		has_digit = true
	}

	frac: f32
	scale := 1.0

	if idx < len(s) && s[idx] == '.' {
		idx += 1

		for idx < len(s) && s[idx] >= '0' && s[idx] <= '9' {
			frac = frac * 10 + f32(s[idx] - '0')
			scale *= 10
			idx += 1
			has_digit = true
		}
	}

	if !has_digit {
		return 0, false
	}

	val = int_part + frac / f32(scale)

	if idx < len(s) && (s[idx] == 'e' || s[idx] == 'E') {
		idx += 1
		exp_neg := false

		if idx < len(s) && (s[idx] == '-' || s[idx] == '+') {
			exp_neg = s[idx] == '-'
			idx += 1
		}

		exp: i32
		for idx < len(s) && s[idx] >= '0' && s[idx] <= '9' {
			exp = exp * 10 + i32(s[idx] - '0')
			idx += 1
		}

		if exp_neg {
			exp = -exp
		}

		power := f32(1.0)
		if exp > 0 {
			for i in 0 ..< exp {
				power *= 10
			}
		} else {
			for i in 0 ..< -exp {
				power /= 10
			}
		}

		val *= power
	}

	if neg {
		val = -val
	}

	return val, true
}

atoi_safe :: proc(s: string) -> int {
	if len(s) == 0 {
		return 0
	}

	n := 0
	neg := false
	idx := 0

	if s[idx] == '-' {
		neg = true
		idx += 1
	}

	for idx < len(s) && s[idx] >= '0' && s[idx] <= '9' {
		n = n * 10 + int(s[idx] - '0')
		idx += 1
	}

	if neg {
		n = -n
	}

	return n
}

create_cube_geo :: proc() -> ^Geometry {
	if g_cube_geometry != nil {
		return g_cube_geometry
	}

	// FRONT/BACK/LEFT/RIGHT/TOP/BOTTOM quads (position + texcoord)
	cube_vertices := [?]Vertex{
		// FRONT
		{{-0.5, 0.0, 0.5}, {0.0, 0.0}},
		{{0.5, 1.0, 0.5}, {1.0, 1.0}},
		{{-0.5, 1.0, 0.5}, {0.0, 1.0}},
		{{0.5, 0.0, 0.5}, {1.0, 0.0}},
		// BACK
		{{0.5, 0.0, -0.5}, {0.0, 0.0}},
		{{-0.5, 1.0, -0.5}, {1.0, 1.0}},
		{{0.5, 1.0, -0.5}, {0.0, 1.0}},
		{{-0.5, 0.0, -0.5}, {1.0, 0.0}},
		// LEFT
		{{-0.5, 0.0, -0.5}, {0.0, 0.0}},
		{{-0.5, 1.0, 0.5}, {1.0, 1.0}},
		{{-0.5, 1.0, -0.5}, {0.0, 1.0}},
		{{-0.5, 0.0, 0.5}, {1.0, 0.0}},
		// RIGHT
		{{0.5, 0.0, 0.5}, {0.0, 0.0}},
		{{0.5, 1.0, -0.5}, {1.0, 1.0}},
		{{0.5, 1.0, 0.5}, {0.0, 1.0}},
		{{0.5, 0.0, -0.5}, {1.0, 0.0}},
		// TOP
		{{-0.5, 1.0, 0.5}, {0.0, 0.0}},
		{{0.5, 1.0, -0.5}, {1.0, 1.0}},
		{{-0.5, 1.0, -0.5}, {0.0, 1.0}},
		{{0.5, 1.0, 0.5}, {1.0, 0.0}},
		// BOTTOM
		{{-0.5, 0.0, -0.5}, {0.0, 0.0}},
		{{0.5, 0.0, 0.5}, {1.0, 1.0}},
		{{-0.5, 0.0, 0.5}, {0.0, 1.0}},
		{{0.5, 0.0, -0.5}, {1.0, 0.0}},
	}

	cube_indices := [?]u32{
		0, 1, 2, 0, 3, 1, // FRONT
		4, 5, 6, 4, 7, 5, // BACK
		8, 9, 10, 8, 11, 9, // LEFT
		12, 13, 14, 12, 15, 13, // RIGHT
		16, 17, 18, 16, 19, 17, // TOP
		20, 21, 22, 20, 23, 21, // BOTTOM
	}

	g_cube_geometry = create_geometry(cube_vertices[:], cube_indices[:])
	g_cube_geometry.permanent = true
	return g_cube_geometry
}

create_plane_geo :: proc() -> ^Geometry {
	if g_plane_geometry != nil {
		return g_plane_geometry
	}

	plane_vertices := [?]Vertex{
		{{-0.5, 1.0, 0.5}, {0.0, 0.0}},
		{{0.5, 1.0, -0.5}, {1.0, 1.0}},
		{{-0.5, 1.0, -0.5}, {0.0, 1.0}},
		{{0.5, 1.0, 0.5}, {1.0, 0.0}},
	}

	plane_indices := [?]u32{0, 1, 2, 0, 3, 1}

	g_plane_geometry = create_geometry(plane_vertices[:], plane_indices[:])
	g_plane_geometry.permanent = true
	return g_plane_geometry
}

create_ramp_geo :: proc() -> ^Geometry {
	if g_ramp_geometry != nil {
		return g_ramp_geometry
	}

	ramp_vertices := [?]Vertex{
		// TOP
		{{-0.5, 0.0, 0.5}, {0.0, 0.0}},
		{{0.5, 1.0, -0.5}, {1.0, 1.0}},
		{{-0.5, 1.0, -0.5}, {0.0, 1.0}},
		{{0.5, 0.0, 0.5}, {1.0, 0.0}},
		// BOTTOM
		{{-0.5, 0.0, -0.5}, {0.0, 0.0}},
		{{0.5, 0.0, 0.5}, {1.0, 1.0}},
		{{-0.5, 0.0, 0.5}, {0.0, 1.0}},
		{{0.5, 0.0, -0.5}, {1.0, 0.0}},
		// LEFT
		{{-0.5, 0.0, -0.5}, {0.0, 0.0}},
		{{-0.5, 0.0, 0.5}, {1.0, 0.0}},
		{{-0.5, 1.0, -0.5}, {0.0, 1.0}},
		// RIGHT
		{{0.5, 0.0, 0.5}, {0.0, 0.0}},
		{{0.5, 0.0, -0.5}, {1.0, 0.0}},
		{{0.5, 1.0, -0.5}, {0.0, 1.0}},
		// BACK
		{{0.5, 0.0, -0.5}, {0.0, 0.0}},
		{{-0.5, 1.0, -0.5}, {1.0, 1.0}},
		{{0.5, 1.0, -0.5}, {0.0, 1.0}},
		{{-0.5, 0.0, -0.5}, {1.0, 0.0}},
	}

	ramp_indices := [?]u32{
		0, 1, 2, 0, 3, 1, // TOP
		4, 5, 6, 4, 7, 5, // BOTTOM
		8, 9, 10, // LEFT
		11, 12, 13, // RIGHT
		14, 15, 16, 14, 17, 15, // BACK
	}

	g_ramp_geometry = create_geometry(ramp_vertices[:], ramp_indices[:])
	g_ramp_geometry.permanent = true
	return g_ramp_geometry
}

create_geometry :: proc(vertices: []Vertex, indices: []u32) -> ^Geometry {
	geometry := new(Geometry)

	vao, vbo, ebo: u32
	gl.GenVertexArrays(1, &vao)
	gl.GenBuffers(1, &vbo)
	gl.GenBuffers(1, &ebo)

	gl.BindVertexArray(vao)

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(Vertex), &vertices[0], gl.STATIC_DRAW)

	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo)
	gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(u32), &indices[0], gl.STATIC_DRAW)

	stride := i32(size_of(Vertex))

	gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, stride, 0)
	gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, stride, uintptr(3 * size_of(f32)))

	gl.EnableVertexAttribArray(0)
	gl.EnableVertexAttribArray(1)

	geometry.vao = vao
	geometry.vbo = vbo
	geometry.ebo = ebo
	geometry.index_count = i32(len(indices))
	geometry.ref_count = 1

	return geometry
}

create_ladder_geo :: proc(height: f32) -> ^Geometry {
	steps := int(height / 6.0)

	vertices: [dynamic]Vertex
	indices: [dynamic]u32
	defer delete(vertices)
	defer delete(indices)

	// two rails using the cube
	for i in 0 ..< 2 {
		v_offset := len(vertices)

		rails := [?]Vertex{
			// FRONT
			{{-0.5, 0.0, 0.5}, {0.0, 0.0}},
			{{0.5, 1.0, 0.5}, {1.0, 1.0}},
			{{-0.5, 1.0, 0.5}, {0.0, 1.0}},
			{{0.5, 0.0, 0.5}, {1.0, 0.0}},
			// BACK
			{{0.5, 0.0, -0.5}, {0.0, 0.0}},
			{{-0.5, 1.0, -0.5}, {1.0, 1.0}},
			{{0.5, 1.0, -0.5}, {0.0, 1.0}},
			{{-0.5, 0.0, -0.5}, {1.0, 0.0}},
			// LEFT
			{{-0.5, 0.0, -0.5}, {0.0, 0.0}},
			{{-0.5, 1.0, 0.5}, {1.0, 1.0}},
			{{-0.5, 1.0, -0.5}, {0.0, 1.0}},
			{{-0.5, 0.0, 0.5}, {1.0, 0.0}},
			// RIGHT
			{{0.5, 0.0, 0.5}, {0.0, 0.0}},
			{{0.5, 1.0, -0.5}, {1.0, 1.0}},
			{{0.5, 1.0, 0.5}, {0.0, 1.0}},
			{{0.5, 0.0, -0.5}, {1.0, 0.0}},
			// TOP
			{{-0.5, 1.0, 0.5}, {0.0, 0.0}},
			{{0.5, 1.0, -0.5}, {1.0, 1.0}},
			{{-0.5, 1.0, -0.5}, {0.0, 1.0}},
			{{0.5, 1.0, 0.5}, {1.0, 0.0}},
			// BOTTOM
			{{-0.5, 0.0, -0.5}, {0.0, 0.0}},
			{{0.5, 0.0, 0.5}, {1.0, 1.0}},
			{{-0.5, 0.0, 0.5}, {0.0, 1.0}},
			{{0.5, 0.0, -0.5}, {1.0, 0.0}},
		}

		rail_indices := [?]u32{
			0, 1, 2, 0, 3, 1, 4, 5, 6, 4, 7, 5, 8, 9, 10, 8, 11, 9, 12, 13, 14, 12, 15, 13, 16, 17, 18, 16, 19, 17, 20, 21, 22, 20, 23, 21,
		}

		for v in rails {
			scaled := v
			scaled.position.x *= shared.GAME_CONSTANTS.ladder_scale * 2.0
			scaled.position.z *= shared.GAME_CONSTANTS.ladder_scale * 2.0
			scaled.position.y *= height + 2.0
			scaled.position.x += shared.GAME_CONSTANTS.ladder_width * (i == 1 ? 1.0 : -1.0)

			append(&vertices, scaled)
		}

		for idx in rail_indices {
			append(&indices, u32(v_offset) + idx)
		}
	}

	for i in 0 ..< steps {
		v_offset := len(vertices)

		step_vertices := [?]Vertex{
			{{-0.5, 1.0, 0.5}, {0.0, 0.0}},
			{{0.5, 1.0, -0.5}, {1.0, 1.0}},
			{{-0.5, 1.0, -0.5}, {0.0, 1.0}},
			{{0.5, 1.0, 0.5}, {1.0, 0.0}},
		}

		for v in step_vertices {
			scaled := v
			scaled.position.y -= 1.0
			scaled.position.x *= shared.GAME_CONSTANTS.ladder_width * 2.0
			scaled.position.z *= shared.GAME_CONSTANTS.ladder_scale * 2.0

			// rotate ~90deg about x
			tmp_y := scaled.position.y
			tmp_z := scaled.position.z
			scaled.position.y = tmp_y * math.cos(PI * 0.5) + tmp_z * -math.sin(PI * 0.5)
			scaled.position.z = tmp_y * math.sin(PI * 0.5) + tmp_z * math.cos(PI * 0.5)

			scaled.position.y += f32(i + 1) * 6.0

			append(&vertices, scaled)
		}

		append(&indices, u32(v_offset), u32(v_offset) + 1, u32(v_offset) + 2, u32(v_offset), u32(v_offset) + 3, u32(v_offset) + 1)
	}

	geometry := create_geometry(vertices[:], indices[:])
	return geometry
}

PI: f32 = 3.14159265358979323846

// texture loading with cache
load_texture :: proc(path: string) -> u32 {
	if cached, ok := g_texture_cache[path]; ok {
		cached.ref_count += 1
		cached.last_used = resource_touch()
		return cached.id
	}

	c_path := strings.clone_to_cstring(path)
	defer delete(c_path)

	stbi.set_flip_vertically_on_load(1)

	w, h, channels: i32
	data := stbi.load(c_path, &w, &h, &channels, 4)

	if data == nil {
		return 0
	}
	defer stbi.image_free(data)

	texture_id: u32

	gl.GenTextures(1, &texture_id)
	gl.BindTexture(gl.TEXTURE_2D, texture_id)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, data)
	gl.GenerateMipmap(gl.TEXTURE_2D)

	entry := new(Texture_Cache_Entry)
	entry.id = texture_id
	entry.width = w
	entry.height = h
	entry.cache_key = strings.clone(path)
	entry.ref_count = 1
	entry.last_used = resource_touch()

	g_texture_cache[entry.cache_key] = entry
	g_texture_by_id[texture_id] = entry
	resource_trim_texture_cache()

	return texture_id
}

resource_touch :: proc() -> u64 {
	g_resource_clock += 1
	return g_resource_clock
}

geometry_release :: proc(geometry: ^Geometry) {
	if geometry == nil || geometry.permanent {
		return
	}

	if geometry.ref_count > 0 {
		geometry.ref_count -= 1
	}
	geometry.last_used = resource_touch()

	if len(geometry.cache_key) == 0 {
		geometry_destroy(geometry)
	} else {
		resource_trim_geometry_cache()
	}
}

texture_release :: proc(texture_id: u32) {
	if texture_id == 0 {
		return
	}

	entry, ok := g_texture_by_id[texture_id]
	if !ok {
		return
	}

	if entry.ref_count > 0 {
		entry.ref_count -= 1
	}
	entry.last_used = resource_touch()
	resource_trim_texture_cache()
}

geometry_destroy :: proc(geometry: ^Geometry) {
	if geometry == nil {
		return
	}

	if geometry.vao != 0 {
		gl.DeleteVertexArrays(1, &geometry.vao)
	}
	if geometry.vbo != 0 {
		gl.DeleteBuffers(1, &geometry.vbo)
	}
	if geometry.ebo != 0 {
		gl.DeleteBuffers(1, &geometry.ebo)
	}
	free(geometry)
}

resource_trim_texture_cache :: proc(force: bool = false) {
	for force || len(g_texture_cache) > MAX_CACHED_TEXTURES {
		oldest: ^Texture_Cache_Entry
		for _, entry in g_texture_cache {
			if entry.ref_count == 0 && (oldest == nil || entry.last_used < oldest.last_used) {
				oldest = entry
			}
		}

		if oldest == nil {
			break
		}

		delete_key(&g_texture_cache, oldest.cache_key)
		delete_key(&g_texture_by_id, oldest.id)
		gl.DeleteTextures(1, &oldest.id)
		delete(oldest.cache_key)
		free(oldest)
	}
}

resource_trim_geometry_cache :: proc(force: bool = false) {
	for force || len(g_geometry_cache) > MAX_CACHED_GEOMETRIES {
		oldest: ^Geometry
		for _, geometry in g_geometry_cache {
			if geometry.ref_count == 0 && (oldest == nil || geometry.last_used < oldest.last_used) {
				oldest = geometry
			}
		}

		if oldest == nil {
			break
		}

		delete_key(&g_geometry_cache, oldest.cache_key)
		key := oldest.cache_key
		oldest.cache_key = ""
		geometry_destroy(oldest)
		delete(key)
	}
}

resource_cache_stats :: proc() -> (textures, geometries: int, estimated_texture_bytes: u64) {
	textures = len(g_texture_cache)
	geometries = len(g_geometry_cache)
	for _, entry in g_texture_cache {
		estimated_texture_bytes += u64(entry.width) * u64(entry.height) * 4
	}
	return
}

resource_print_stats :: proc(label: string) {
	textures, geometries, texture_bytes := resource_cache_stats()
	fmt.printf(
		"[Assets] %s: %d textures (~%.1f MiB RGBA), %d OBJ geometries\n",
		label,
		textures,
		f64(texture_bytes) / (1024.0 * 1024.0),
		geometries,
	)
}

resource_cache_fini :: proc() {
	resource_trim_texture_cache(true)
	resource_trim_geometry_cache(true)
	delete(g_texture_cache)
	delete(g_texture_by_id)
	delete(g_geometry_cache)

	if g_cube_geometry != nil {
		geometry_destroy(g_cube_geometry)
		g_cube_geometry = nil
	}
	if g_plane_geometry != nil {
		geometry_destroy(g_plane_geometry)
		g_plane_geometry = nil
	}
	if g_ramp_geometry != nil {
		geometry_destroy(g_ramp_geometry)
		g_ramp_geometry = nil
	}
	if g_blank_texture != 0 {
		gl.DeleteTextures(1, &g_blank_texture)
		g_blank_texture = 0
	}

	if basic_shader_program != 0 {
		gl.DeleteProgram(basic_shader_program)
		basic_shader_program = 0
	}
	if quad_shader_program != 0 {
		gl.DeleteProgram(quad_shader_program)
		quad_shader_program = 0
	}
	if text_shader_program != 0 {
		gl.DeleteProgram(text_shader_program)
		text_shader_program = 0
	}
}
