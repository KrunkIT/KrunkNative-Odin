package krunker

import shared "../shared"

Krunker_Projectile_Event :: struct {
	kind: enum { SPAWN, END, EXPLOSION },
	position: shared.Vec3,
	angles: shared.Vec2,
	id, weapon_id, owner_sid: i32,
	by_shot_count: bool,
	radius: f32,
}

// pr(x,y,z,yaw,pitch,weapon,sid,custom?,customConfig?,ownerSid?),
// pre(sidOrLocalShotCount,byLocalShotCount,x?,y?,z?,impact?), ex(x,y,z,radius,...).
// Custom projectiles use a separate scripting registry; do not treat those
// indices as ordinary weapons.
krunker_world_apply_projectile :: proc(state: ^Krunker_World_State, packet: []Krunker_Msgpack_Value, opcode: string) -> bool {
	event := Krunker_Projectile_Event{owner_sid = -1}
	if opcode == "pre" {
		if len(packet) < 3 { return false }
		id, ok := krunker_world_bounded_number(packet[1], 0, 2147483647); if !ok { return false }
		event.kind, event.id, event.by_shot_count = .END, i32(id), krunker_world_bool(packet[2])
	} else {
		if len(packet) < (8 if opcode == "pr" else 5) { return false }
		for i in 0..<3 {
			n, ok := krunker_world_bounded_number(packet[i+1], -1e7, 1e7); if !ok { return false }
			event.position[i] = f32(n)
		}
		if opcode == "ex" {
			n, ok := krunker_world_bounded_number(packet[4], 0, 10000); if !ok { return false }
			event.kind, event.radius = .EXPLOSION, f32(n)
		} else {
			if len(packet) > 8 && krunker_world_bool(packet[8]) { return false }
			yaw, yaw_ok := krunker_world_bounded_number(packet[4], -1e7, 1e7)
			pitch, pitch_ok := krunker_world_bounded_number(packet[5], -1e7, 1e7)
			weapon, weapon_ok := krunker_world_bounded_number(packet[6], 0, 1000)
			id, id_ok := krunker_world_bounded_number(packet[7], 0, 2147483647)
			if !yaw_ok || !pitch_ok || !weapon_ok || !id_ok { return false }
			event.kind, event.id, event.weapon_id = .SPAWN, i32(id), i32(weapon)
			event.angles = {f32(pitch), f32(yaw)}
			if len(packet) > 10 { if sid, ok := krunker_world_bounded_number(packet[10], 0, 2147483647); ok { event.owner_sid = i32(sid) } }
		}
	}
	if len(state.projectile_events) >= 256 { ordered_remove(&state.projectile_events, 0) }
	append(&state.projectile_events, event)
	return true
}
