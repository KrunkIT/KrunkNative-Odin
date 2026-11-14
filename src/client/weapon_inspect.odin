package main

import "core:math"
import shared "../shared"

INSPECT_MELEE_ARM_ROTATION :: shared.Vec3{-0.6, 2.2, -0.3}
INSPECT_MELEE_ARM_POSITION :: shared.Vec3{-0.1, 1, -1.3}

// Inspect is local presentation. It never changes gameplay input or packets.
// The official wInspect toggles on a press, and cancelInspect restores the pose
// immediately. Our aim_val runs from 0 (hipfire) to 1 (ADS).
client_update_inspect :: proc(client: ^Client, down, enabled, cancel: bool, delta: f32) {
	pressed := down && !client.inspect_pressed
	client.inspect_pressed = down
	player := client.me
	if player == nil {
		client.inspect_angle, client.inspect_time, client.inspect_weapon = 0, 0, nil
		return
	}
	weapon := player.weapon
	allowed := enabled && player.active && weapon != nil
	if allowed {
		allowed = !weapon.no_inspect && player.aim_val <= 0.001 && player.reload_timer <= 0 && player.swap_timer <= 0 &&
			(!weapon.melee || player.can_throw)
	}
	if !allowed || cancel || client.inspect_weapon != weapon || client.inspect_slot != player.loadout_index {
		player.inspecting = false
	}
	if pressed && allowed && !cancel {
		player.inspecting = !player.inspecting
		client.inspect_angle, client.inspect_time = 0, 0
	}
	client.inspect_weapon, client.inspect_slot = weapon, player.loadout_index
	if !player.inspecting {
		client.inspect_angle, client.inspect_time = 0, 0
		return
	}
	// The browser approaches insX by 10% per frame. Preserve that motion at
	// 60 Hz while keeping the duration independent of the native frame rate.
	target: f32 = weapon.melee ? 0.1 : math.PI/2.8
	client.inspect_angle = math.lerp(client.inspect_angle, target, 1-math.pow(f32(0.9), max(0, delta)*60))
	client.inspect_time = min(0.4, client.inspect_time + max(0, delta))
}

client_apply_inspect_pose :: proc(client: ^Client, arms: ^Player_Arms) {
	player := client.me
	if player == nil || !player.inspecting || player.weapon == nil { return }
	angle := client.inspect_angle
	arms.anchor.rotation.y += angle
	arms.anchor.rotation.z -= angle * player.weapon.inspect_rotation
	arms.anchor.position.x -= angle * player.weapon.inspect_mlt
	if !player.weapon.melee || arms.right == nil { return }
	// Default Combat Knife inspAnim: a 400 ms Exponential.Out tween of the
	// right hand and blade, independent of bobbing/leaning preferences.
	p := client.inspect_time >= 0.4 ? f32(1) : 1-math.pow(f32(2), -10*client.inspect_time/0.4)
	arms.right.pivot.rotation += INSPECT_MELEE_ARM_ROTATION * p
	arms.right.pivot.position += INSPECT_MELEE_ARM_POSITION * p
	if arms.weapon_right != nil {
		arms.weapon_right.transform.position.y -= 0.4*p
		arms.weapon_right.transform.position.z -= 0.19*p
		arms.weapon_right.transform.rotation.y -= 0.2*p
	}
}
