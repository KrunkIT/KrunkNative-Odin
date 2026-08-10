package main

import shared "../shared"

// low 4 bytes = VBO, high 4 bytes = EBO
Geometry :: struct {
	vao:         u32,
	vbo:         u32,
	ebo:         u32,
	index_count: i32,
	cache_key:   string,
	ref_count:   u32,
	last_used:   u64,
	permanent:   bool,
}

Texture_Cache_Entry :: struct {
	id:         u32,
	width:      i32,
	height:     i32,
	cache_key:  string,
	ref_count:  u32,
	last_used:  u64,
}

Vertex :: struct {
	position:  shared.Vec3,
	tex_coord: shared.Vec2,
}

Rotation_Order :: enum {
	INTRINSIC,
	EXTRINSIC,
}

Material_VTable :: struct {
	update_uniforms: proc(rawptr),
}

Material :: struct {
	vtable:      ^Material_VTable,
	wireframe:   bool,
	transparent: bool,
	program:     u32,
}

Quad_Material :: struct {
	using base: Material,
	color: shared.Vec4,
	aspect: f32,
	border_bottom_left_radius: f32,
	border_bottom_right_radius: f32,
	border_top_left_radius: f32,
	border_top_right_radius: f32,
	r_clip: f32,
	texture_viewport: [4]f32,
	texture: u32,
}

Text_Material :: struct {
	using base: Material,
	color: shared.Vec4,
	texture: u32,
}

Basic_Material :: struct {
	using base: Material,
	is_ramp: bool,
	is_ladder: bool,
	use_face_tex_scaling: bool,
	face_scale: shared.Vec3,
	color: shared.Vec4,
	emissive: shared.Vec4,
	texture_repeat: shared.Vec2,
	texture_offset: shared.Vec2,
	texture: u32,
}

Mesh_Transform :: struct {
	parent:         ^Mesh_Transform,
	rotation_order: Rotation_Order,
	position:       shared.Vec3,
	rotation:       shared.Vec3,
	scale:          shared.Vec3,
}

Mesh :: struct {
	transform: Mesh_Transform,
	visible:   bool,
	geometry:  ^Geometry,
	transform_matrix:    shared.Mat4,
	camera_space_matrix: shared.Mat4, // temporary - used during scene depth sort
	material:  ^Material,
}

Color_Cube :: struct {
	transform:  Mesh_Transform,
	mesh_count: i32,
	meshes:     [dynamic]^Mesh,
}

Player_Crouched_Leg :: struct {
	anchor: Mesh_Transform,
	upper:  ^Mesh,
	joint:  ^Mesh,
	lower:  ^Color_Cube,
}

Player_Arm_Mesh :: struct {
	extender: ^Mesh, // first person
	upper:    ^Mesh, // third person
	joint:    ^Mesh,
	lower:    ^Color_Cube,
	anchor:   Mesh_Transform,
}

Player_Arms :: struct {
	anchor: Mesh_Transform,
	left:   ^Player_Arm_Mesh,
	right:  ^Player_Arm_Mesh,
	weapon_left:  ^Mesh,
	weapon_right: ^Mesh,
}

Player_Mesh :: struct {
	anchor:            ^Mesh_Transform,
	body_anchor:       ^Mesh_Transform,
	upper_body_anchor: ^Mesh_Transform,
	head:              ^Color_Cube,
	body:              ^Color_Cube,
	legs:              [2]^Color_Cube,
	crouched_legs:     [2]^Player_Crouched_Leg,
	arms:              [dynamic]^Player_Arms,
}

Scene :: struct {
	mesh_count: i32,
	meshes:     [dynamic]^Mesh,
}

Camera :: struct {
	near: f32,
	far:  f32,
	fov:  f32,
	zoom: f32,
	position:            shared.Vec3,
	rotation:            shared.Vec3,
	projection_matrix:   shared.Mat4,
	world_inverse_matrix: shared.Mat4,
}

UI :: struct {
	material:      ^Quad_Material,
	text_material: ^Text_Material,
	vao:           u32,
	vbo:           u32,
	width:         f32,
	height:        f32,
	scale:         f32,
}

Glyph_Cache_Entry :: struct {
	texture:   u32,
	size:      shared.Vec2,
	h_bearing: shared.Vec2,
	v_bearing: shared.Vec2,
	advance:   f32,
}

Impact_Marker :: struct {
	mesh:     ^Mesh,
	position: shared.Vec3,
	lifetime: f32,
}

Tracer_Marker :: struct {
	mesh:           ^Mesh,
	lifetime:       f32,
	total_lifetime: f32,
}

// Asset caches (keyed by path)
g_geometry_cache: map[string]^Geometry
g_texture_cache:  map[string]^Texture_Cache_Entry
g_texture_by_id:  map[u32]^Texture_Cache_Entry
g_glyph_cache:    map[u8]^Glyph_Cache_Entry

g_resource_clock: u64

MAX_CACHED_TEXTURES :: 128
MAX_CACHED_GEOMETRIES :: 64

g_cube_geometry:  ^Geometry
g_plane_geometry: ^Geometry
g_ramp_geometry:  ^Geometry

g_blank_texture:  u32
g_active_texture: u32
g_active_shader:  u32
