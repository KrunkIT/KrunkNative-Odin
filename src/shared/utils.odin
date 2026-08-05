package shared

import "core:math"
import "core:os"
import "core:strings"

concat :: proc(a, b: string) -> string {
	return strings.concatenate({a, b})
}

assets_path :: proc() -> string {
	wd, err := os.get_working_directory(context.temp_allocator)
	if err != nil {
		return "./assets/"
	}

	// When built via cmake or run from a build directory, assets live one level
	// up. Compare the trailing directory name so this also works on Windows
	// (backslashes) rather than only matching Unix-style "/bin" suffixes.
	dir := strings.trim_right(wd, "/\\")
	sep := strings.last_index_any(dir, "/\\")
	base := dir[sep + 1:] if sep >= 0 else dir

	switch base {
	case "bin", "cmake-build-debug", "cmake-build-release":
		return "../assets/"
	}

	return "./assets/"
}

read_file :: proc(path: string) -> (data: []byte, ok: bool) {
	buffer, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		return nil, false
	}

	return buffer, true
}

// #RGA, #RGBA, #RRGGBB, #RRGGBBAA
parse_hex_color :: proc(hex_str: string, out: ^Vec4) -> bool {
	if len(hex_str) < 2 || hex_str[0] != '#' {
		return false
	}

	hex_len := len(hex_str) - 1
	if hex_len != 3 && hex_len != 4 && hex_len != 6 && hex_len != 8 {
		return false
	}

	channels: [4]u8

	for i in 0 ..< hex_len {
		value := hex_str[i + 1]

		parsed: u8

		if value >= 'A' && value <= 'F' {
			parsed = value - 'A' + 10
		} else if value >= 'a' && value <= 'f' {
			parsed = value - 'a' + 10
		} else if value >= '0' && value <= '9' {
			parsed = value - '0'
		} else {
			return false
		}

		if hex_len < 6 {
			if i > 3 {
				break
			}

			channels[i] = parsed << 4 | parsed
		} else {
			channels[i / 2] |= parsed << (i % 2 == 0 ? 4 : 0)
		}
	}

	out.x = f32(channels[0]) / 255.0
	out.y = f32(channels[1]) / 255.0
	out.z = f32(channels[2]) / 255.0
	out.w = hex_len == 4 || hex_len == 8 ? f32(channels[3]) / 255.0 : 1.0

	return true
}

hex_to_vec :: proc(hex: i32) -> Vec4 {
	return Vec4 {
		f32(hex >> 16 & 0xff) / 255.0,
		f32(hex >> 8 & 0xff) / 255.0,
		f32(hex & 0xff) / 255.0,
		1.0,
	}
}

normalize_angle :: proc(angle: f32) -> f32 {
	angle := angle
	angle = math.mod(angle + math.PI, math.PI * 2.0)

	if angle < 0 {
		return angle + math.PI
	}

	return angle - math.PI
}

progress_on_line :: proc(line_start, line_end, point: Vec2) -> f32 {
	dir := Vec2{line_end.x - line_start.x, line_end.y - line_start.y}
	return (dir.x * (point.x - line_start.x) + (point.y - line_start.y) * dir.y) / (dir.x * dir.x + dir.y * dir.y)
}

line_in_rect :: proc(origin, direction, obj_origin, obj_scale: Vec3) -> f32 {
	if direction.x > 0.0 && obj_origin.x + obj_scale.x * 0.5 < origin.x ||
	   direction.x < 0.0 && obj_origin.x - obj_scale.x * 0.5 > origin.x ||
	   direction.y > 0.0 && obj_origin.y + obj_scale.y < origin.y ||
	   direction.y < 0.0 && obj_origin.y > origin.y ||
	   direction.z > 0.0 && obj_origin.z + obj_scale.z * 0.5 < origin.z ||
	   direction.z < 0.0 && obj_origin.z - obj_scale.z * 0.5 > origin.z {
		return -1.0
	}

	tx1 := (obj_origin.x - obj_scale.x * 0.5 - origin.x) / direction.x
	tx2 := (obj_origin.x + obj_scale.x * 0.5 - origin.x) / direction.x
	ty1 := (obj_origin.y - origin.y) / direction.y
	ty2 := (obj_origin.y + obj_scale.y - origin.y) / direction.y
	tz1 := (obj_origin.z - obj_scale.z * 0.5 - origin.z) / direction.z
	tz2 := (obj_origin.z + obj_scale.z * 0.5 - origin.z) / direction.z

	tmin := max(max(min(tx1, tx2), min(ty1, ty2)), min(tz1, tz2))
	tmax := min(min(max(tx1, tx2), max(ty1, ty2)), max(tz1, tz2))

	if tmin <= tmax && tmin > 0 {
		return tmin
	}

	return -1.0
}

ray_box_hit :: proc(origin, direction, obj_origin, obj_scale: Vec3) -> (t: f32, normal: Vec3, ok: bool) {
	box_min := Vec3{
		obj_origin.x - obj_scale.x * 0.5,
		obj_origin.y,
		obj_origin.z - obj_scale.z * 0.5,
	}
	box_max := Vec3{
		obj_origin.x + obj_scale.x * 0.5,
		obj_origin.y + obj_scale.y,
		obj_origin.z + obj_scale.z * 0.5,
	}

	t_near: f32 = 0.0
	t_far: f32 = 1.0
	near_normal := Vec3{}

	for axis in 0 ..< 3 {
		o := origin[axis]
		d := direction[axis]

		if math.abs(d) < 1e-8 {
			if o < box_min[axis] || o > box_max[axis] {
				return 0, {}, false
			}
			continue
		}

		t1 := (box_min[axis] - o) / d
		t2 := (box_max[axis] - o) / d
		axis_normal := Vec3{}
		axis_normal[axis] = d > 0 ? -1.0 : 1.0

		if t1 > t2 {
			t1, t2 = t2, t1
		}

		if t1 > t_near {
			t_near = t1
			near_normal = axis_normal
		}
		t_far = min(t_far, t2)

		if t_near > t_far {
			return 0, {}, false
		}
	}

	if t_near < 0.0 || t_near > 1.0 {
		return 0, {}, false
	}

	return t_near, near_normal, true
}

angles_from_sides :: proc(a, b, c: f32) -> [3]f32 {
	return [3]f32 {
		math.acos((b * b + c * c - a * a) / (2.0 * b * c)),
		math.acos((a * a + c * c - b * b) / (2.0 * a * c)),
		math.acos((a * a + b * b - c * c) / (2.0 * a * b)),
	}
}

crop :: proc(x, lim: f32) -> f32 {
	if x <= lim && x >= -lim {
		return 0
	}

	return x
}

mat3x3 :: proc(a, b: [9]f32) -> [9]f32 {
	out: [9]f32

	for i in 0 ..< 3 {
		for j in 0 ..< 3 {
			sum: f32
			for k in 0 ..< 3 {
				sum += a[i * 3 + k] * b[k * 3 + j]
			}

			out[i * 3 + j] = sum
		}
	}

	return out
}

mat4x4 :: proc(a, b: Mat4) -> Mat4 {
	return a * b
}
