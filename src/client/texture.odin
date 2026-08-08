package main

import "core:fmt"
import "core:math"
import "core:strings"
import gl "vendor:OpenGL"
import stbi "vendor:stb/image"

Texture :: struct {
	id:     u32,
	width:  i32,
	height: i32,
}

Texture_Manager :: struct {
	textures: map[u32]u32, // maps texture index to OpenGL GLuint texture handle
	fallback: u32,
}

g_impact_texture: u32

texture_manager_init :: proc() -> Texture_Manager {
	tm: Texture_Manager
	tm.textures = make(map[u32]u32)

	// These indices are the same prefab texture indices used by the original
	// KrunkNative client. Keep the list in index order; map JSON stores only the
	// numeric index in its "t" field.
	texture_names := [?]string{
		"wall", "dirt", "floor", "grid", "grey", "sand", "roof", "flag",
		"grass", "check", "lines", "brick", "link", "liquid", "grain", "fabric", "tile",
	}

	for name, idx in texture_names {
		path := strings.concatenate({"assets/textures/", name, "_0.png"})
		tex, ok := texture_load_from_file(path)
		if !ok {
			fmt.eprintf("Failed to load texture %d: %s\n", idx, path)
			continue
		}
		tm.textures[u32(idx)] = tex.id
		fmt.printf("Loaded texture %d: %s (%dx%d)\n", idx, path, tex.width, tex.height)
	}

	// The supplied asset pack has no default_0.png. sand_0.png is the closest
	// equivalent and is also what the map set expects for its default material.
	if _, ok := tm.textures[5]; !ok {
		fallback_tex, fallback_ok := texture_load_from_file("assets/textures/sand_0.png")
		if fallback_ok {
			tm.textures[5] = fallback_tex.id
		}
	}

	if wall, ok := tm.textures[0]; ok {
		tm.fallback = wall
	} else if sand, ok := tm.textures[5]; ok {
		tm.fallback = sand
	}
	return tm
}

texture_manager_get :: proc(tm: ^Texture_Manager, idx: u32) -> u32 {
	if handle, ok := tm.textures[idx]; ok {
		return handle
	}
	return tm.fallback
}

upload_rgba_texture :: proc(pixels: []u8, width, height: i32) -> u32 {
	tex_id: u32
	gl.GenTextures(1, &tex_id)
	gl.BindTexture(gl.TEXTURE_2D, tex_id)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST_MIPMAP_NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, &pixels[0])
	gl.GenerateMipmap(gl.TEXTURE_2D)
	gl.BindTexture(gl.TEXTURE_2D, 0)
	g_active_texture = 0
	return tex_id
}

impact_texture_get :: proc() -> u32 {
	if g_impact_texture != 0 {
		return g_impact_texture
	}

	size :: 64
	pixels := make([]u8, size * size * 4)
	defer delete(pixels)

	for y := 0; y < size; y += 1 {
		for x := 0; x < size; x += 1 {
			dx := (f32(x) + 0.5) / (f32(size) * 0.5) - 1.0
			dy := (f32(y) + 0.5) / (f32(size) * 0.5) - 1.0
			radius := math.sqrt(dx * dx + dy * dy)
			angle := math.atan2(dy, dx)
			edge := 0.88 + 0.05 * math.sin(angle * 7.0) + 0.025 * math.sin(angle * 13.0 + 0.7)

			shade: u8
			alpha: u8
			if radius < edge {
				fade := clamp((edge - radius) / 0.08, 0.0, 1.0)
				if radius > edge - 0.18 {
					shade = 82
				} else {
					shade = 18
				}
				alpha = u8(235.0 * fade)
			}

			idx := (y * size + x) * 4
			pixels[idx + 0] = shade
			pixels[idx + 1] = u8(f32(shade) * 0.9)
			pixels[idx + 2] = u8(f32(shade) * 0.78)
			pixels[idx + 3] = alpha
		}
	}

	g_impact_texture = upload_rgba_texture(pixels, size, size)
	return g_impact_texture
}

// 0: Wall (Sandstone plaster with subtle brick joints)
create_procedural_wall_texture :: proc() -> u32 {
	pix := make([]u8, 64 * 64 * 4)
	defer delete(pix)
	for y := 0; y < 64; y += 1 {
		for x := 0; x < 64; x += 1 {
			idx := (y * 64 + x) * 4
			is_joint := (y % 16 == 0) || (x % 32 == (y / 16 % 2 * 16))
			if is_joint {
				pix[idx + 0] = 160; pix[idx + 1] = 140; pix[idx + 2] = 120; pix[idx + 3] = 255
			} else {
				noise := u8((x * 7 + y * 13) % 25)
				pix[idx + 0] = 210 - noise; pix[idx + 1] = 190 - noise; pix[idx + 2] = 165 - noise; pix[idx + 3] = 255
			}
		}
	}
	return upload_rgba_texture(pix, 64, 64)
}

// 1: Dirt (Granular earth brown)
create_procedural_dirt_texture :: proc() -> u32 {
	pix := make([]u8, 64 * 64 * 4)
	defer delete(pix)
	for y := 0; y < 64; y += 1 {
		for x := 0; x < 64; x += 1 {
			idx := (y * 64 + x) * 4
			noise := u8((x * 17 + y * 31) % 35)
			pix[idx + 0] = 110 - noise; pix[idx + 1] = 75 - noise; pix[idx + 2] = 45 - noise; pix[idx + 3] = 255
		}
	}
	return upload_rgba_texture(pix, 64, 64)
}

// 2: Wood / Floor planks
create_procedural_wood_texture :: proc() -> u32 {
	pix := make([]u8, 64 * 64 * 4)
	defer delete(pix)
	for y := 0; y < 64; y += 1 {
		for x := 0; x < 64; x += 1 {
			idx := (y * 64 + x) * 4
			is_seam := (y % 16 == 0)
			grain := u8((x * 3 + y * 29) % 20)
			if is_seam {
				pix[idx + 0] = 60; pix[idx + 1] = 35; pix[idx + 2] = 15; pix[idx + 3] = 255
			} else {
				pix[idx + 0] = 160 - grain; pix[idx + 1] = 105 - grain; pix[idx + 2] = 60 - grain; pix[idx + 3] = 255
			}
		}
	}
	return upload_rgba_texture(pix, 64, 64)
}

// 3: Metal Grid
create_procedural_grid_texture :: proc() -> u32 {
	pix := make([]u8, 64 * 64 * 4)
	defer delete(pix)
	for y := 0; y < 64; y += 1 {
		for x := 0; x < 64; x += 1 {
			idx := (y * 64 + x) * 4
			grid := (x % 8 == 0) || (y % 8 == 0)
			if grid {
				pix[idx + 0] = 70; pix[idx + 1] = 75; pix[idx + 2] = 80; pix[idx + 3] = 255
			} else {
				pix[idx + 0] = 140; pix[idx + 1] = 145; pix[idx + 2] = 150; pix[idx + 3] = 255
			}
		}
	}
	return upload_rgba_texture(pix, 64, 64)
}

// 4: Concrete
create_procedural_concrete_texture :: proc() -> u32 {
	pix := make([]u8, 64 * 64 * 4)
	defer delete(pix)
	for y := 0; y < 64; y += 1 {
		for x := 0; x < 64; x += 1 {
			idx := (y * 64 + x) * 4
			noise := u8((x * 11 + y * 23) % 20)
			val := 150 - noise
			pix[idx + 0] = val; pix[idx + 1] = val; pix[idx + 2] = val + 5; pix[idx + 3] = 255
		}
	}
	return upload_rgba_texture(pix, 64, 64)
}

// 5: Sand
create_procedural_sand_texture :: proc() -> u32 {
	pix := make([]u8, 64 * 64 * 4)
	defer delete(pix)
	for y := 0; y < 64; y += 1 {
		for x := 0; x < 64; x += 1 {
			idx := (y * 64 + x) * 4
			noise := u8((x * 13 + y * 19) % 20)
			pix[idx + 0] = 225 - noise; pix[idx + 1] = 200 - noise; pix[idx + 2] = 140 - noise; pix[idx + 3] = 255
		}
	}
	return upload_rgba_texture(pix, 64, 64)
}

// 6: Roof tiles
create_procedural_roof_texture :: proc() -> u32 {
	pix := make([]u8, 64 * 64 * 4)
	defer delete(pix)
	for y := 0; y < 64; y += 1 {
		for x := 0; x < 64; x += 1 {
			idx := (y * 64 + x) * 4
			line := (y % 12 == 0)
			if line {
				pix[idx + 0] = 40; pix[idx + 1] = 45; pix[idx + 2] = 50; pix[idx + 3] = 255
			} else {
				pix[idx + 0] = 85; pix[idx + 1] = 90; pix[idx + 2] = 100; pix[idx + 3] = 255
			}
		}
	}
	return upload_rgba_texture(pix, 64, 64)
}

// 7: Cloth
create_procedural_cloth_texture :: proc() -> u32 {
	pix := make([]u8, 64 * 64 * 4)
	defer delete(pix)
	for y := 0; y < 64; y += 1 {
		for x := 0; x < 64; x += 1 {
			idx := (y * 64 + x) * 4
			noise := u8((x + y) % 2 == 0 ? 15 : 0)
			pix[idx + 0] = 200 - noise; pix[idx + 1] = 40 - noise; pix[idx + 2] = 40 - noise; pix[idx + 3] = 255
		}
	}
	return upload_rgba_texture(pix, 64, 64)
}

// 8: Grass
create_procedural_grass_texture :: proc() -> u32 {
	pix := make([]u8, 64 * 64 * 4)
	defer delete(pix)
	for y := 0; y < 64; y += 1 {
		for x := 0; x < 64; x += 1 {
			idx := (y * 64 + x) * 4
			noise := u8((x * 23 + y * 37) % 40)
			pix[idx + 0] = 55 - noise/2; pix[idx + 1] = 160 - noise; pix[idx + 2] = 45 - noise/2; pix[idx + 3] = 255
		}
	}
	return upload_rgba_texture(pix, 64, 64)
}

// 9: Checkered floor
create_procedural_check_texture :: proc() -> u32 {
	pix := make([]u8, 64 * 64 * 4)
	defer delete(pix)
	for y := 0; y < 64; y += 1 {
		for x := 0; x < 64; x += 1 {
			idx := (y * 64 + x) * 4
			check := ((x / 16) + (y / 16)) % 2 == 0
			c: u8 = check ? 230 : 30
			pix[idx + 0] = c; pix[idx + 1] = c; pix[idx + 2] = c; pix[idx + 3] = 255
		}
	}
	return upload_rgba_texture(pix, 64, 64)
}

// 10: Hazard stripes
create_procedural_hazard_texture :: proc() -> u32 {
	pix := make([]u8, 64 * 64 * 4)
	defer delete(pix)
	for y := 0; y < 64; y += 1 {
		for x := 0; x < 64; x += 1 {
			idx := (y * 64 + x) * 4
			stripe := ((x + y) / 8) % 2 == 0
			if stripe {
				pix[idx + 0] = 240; pix[idx + 1] = 200; pix[idx + 2] = 20; pix[idx + 3] = 255
			} else {
				pix[idx + 0] = 25; pix[idx + 1] = 25; pix[idx + 2] = 25; pix[idx + 3] = 255
			}
		}
	}
	return upload_rgba_texture(pix, 64, 64)
}

// 11: Red brick wall
create_procedural_brick_texture :: proc() -> u32 {
	pix := make([]u8, 64 * 64 * 4)
	defer delete(pix)
	for y := 0; y < 64; y += 1 {
		for x := 0; x < 64; x += 1 {
			idx := (y * 64 + x) * 4
			row := y / 8
			is_mortar := (y % 8 == 0) || ((x + (row % 2 * 16)) % 32 == 0)
			if is_mortar {
				pix[idx + 0] = 200; pix[idx + 1] = 195; pix[idx + 2] = 185; pix[idx + 3] = 255
			} else {
				noise := u8((x * 7 + y * 11) % 30)
				pix[idx + 0] = 175 - noise; pix[idx + 1] = 60 - noise/2; pix[idx + 2] = 40 - noise/2; pix[idx + 3] = 255
			}
		}
	}
	return upload_rgba_texture(pix, 64, 64)
}

// 13: Liquid (Water/Acid)
create_procedural_water_texture :: proc() -> u32 {
	pix := make([]u8, 64 * 64 * 4)
	defer delete(pix)
	for y := 0; y < 64; y += 1 {
		for x := 0; x < 64; x += 1 {
			idx := (y * 64 + x) * 4
			noise := u8((x * 19 + y * 29) % 30)
			pix[idx + 0] = 30; pix[idx + 1] = 140 - noise; pix[idx + 2] = 220 - noise; pix[idx + 3] = 200
		}
	}
	return upload_rgba_texture(pix, 64, 64)
}

// 16: Ceramic tile
create_procedural_tile_texture :: proc() -> u32 {
	pix := make([]u8, 64 * 64 * 4)
	defer delete(pix)
	for y := 0; y < 64; y += 1 {
		for x := 0; x < 64; x += 1 {
			idx := (y * 64 + x) * 4
			grout := (x % 16 == 0) || (y % 16 == 0)
			if grout {
				pix[idx + 0] = 120; pix[idx + 1] = 120; pix[idx + 2] = 130; pix[idx + 3] = 255
			} else {
				pix[idx + 0] = 230; pix[idx + 1] = 235; pix[idx + 2] = 245; pix[idx + 3] = 255
			}
		}
	}
	return upload_rgba_texture(pix, 64, 64)
}

texture_load_from_file :: proc(filename: string) -> (tex: Texture, ok: bool) {
	c_path := strings.clone_to_cstring(filename)
	defer delete(c_path)

	stbi.set_flip_vertically_on_load(1)

	w, h, channels: i32
	data := stbi.load(c_path, &w, &h, &channels, 4)
	if data == nil {
		return tex, false
	}
	defer stbi.image_free(data)

	tex.width = w
	tex.height = h

	gl.GenTextures(1, &tex.id)
	gl.BindTexture(gl.TEXTURE_2D, tex.id)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST_MIPMAP_NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, data)
	gl.GenerateMipmap(gl.TEXTURE_2D)

	return tex, true
}
