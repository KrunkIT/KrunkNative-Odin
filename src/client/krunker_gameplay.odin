package main

import shared "../shared"
import kproto "../krunker"
import "core:fmt"

krunker_client_live_class_window :: proc(client: ^Client, now: f64) -> bool {
	world := &client.krunker_world
	if !client.krunker.connected || !(world.is_comp || world.is_ranked) { return false }
	if world.countdown == .WAITING { return true }
	return (world.countdown == .WARMUP || world.countdown == .INTERMISSION) &&
		world.countdown_remaining > f32(max(0, now-world.countdown_received_at))
}

krunker_client_respawn_remaining :: proc(client: ^Client, now: f64) -> f32 {
	if !client.krunker.connected { return 0 }
	return f32(max(0, client.krunker_world.respawn_available_at-now))
}

krunker_client_countdown_label :: proc(client: ^Client, now: f64) -> string {
	if !client.krunker.connected { return "" }
	world := &client.krunker_world
	remaining := max(0, int(world.countdown_remaining-f32(max(0, now-world.countdown_received_at))+0.999))
	switch world.countdown {
	case .WAITING: return "Waiting for players"
	case .WARMUP: return fmt.tprintf("Warmup ends in %02d:%02d", remaining/60, remaining%60)
	case .STARTING: return fmt.tprintf("Match starts in %02d:%02d", remaining/60, remaining%60)
	case .INTERMISSION: return fmt.tprintf("Intermission %02d:%02d", remaining/60, remaining%60)
	case .NONE:
	}
	return ""
}

krunker_client_apply_metadata :: proc(client: ^Client, player: ^shared.Player, source: ^kproto.Krunker_World_Player) {
	if source.health < player.health { shared.player_emit_presentation(player, .DAMAGE) }
	player.health, player.max_health = source.health, i32(source.max_health)
	player.score, player.kills, player.deaths = source.score, source.kills, source.deaths
	if source.controls_revision > 0 {
		player.noclip, player.frozen, player.unlimited_ammo = source.noclip, source.frozen, source.unlimited_ammo
		player.speed_boost = source.speed_boost
	}
	if player.is_you { player.interact_progress = client.krunker_world.interact_progress }
}

krunker_client_timer_label :: proc(client: ^Client) -> string {
	world := &client.krunker_world
	if client.krunker.connected && world.has_match && world.timer_kind != 0 && len(world.timer_text) > 0 { return world.timer_text }
	remaining := max(0, int(client.game.match.time_remaining + 0.999))
	return fmt.tprintf("%02d:%02d", remaining/60, remaining%60)
}

// Advance display clocks from the last server value. Never run local scoring,
// objective rotation, overtime, or round transitions for a live socket.
krunker_client_sync_match :: proc(client: ^Client, now: f64) {
	world := &client.krunker_world
	if !world.has_match { return }
	client.game.match = world.match
	match := &client.game.match
	if kproto.krunker_world_clocks_running(world) {
		if world.timer_kind == 0 { match.time_remaining = max(0, match.time_remaining - f32(max(0, now-world.timer_received_at))) }
		match.objective.rotation_remaining = max(0, match.objective.rotation_remaining - f32(max(0, now-world.objective_received_at)))
	}
	if match.phase == .WARMUP { match.phase_remaining = max(0, match.phase_remaining - f32(max(0, now-world.lockout_received_at))) }
	match.objective.active_object_index, match.objective.active_zone = -1, -1
	if client.game.map_inst == nil { return }
	for index in client.game.objective_indices {
		object := client.game.map_inst.objects[index]
		if object.objective_id != world.objective_uid { continue }
		match.objective.active_object_index, match.objective.active_zone = index, object.objective_id
		// uobj contains occupant count, never a team ID. Team ownership cannot
		// be inferred from this message.
		match.objective.contested = client.game.mode != nil && !client.game.mode.config.teams && world.objective_occupants > 1
		break
	}
}

krunker_client_match_reason :: proc(client: ^Client) -> string {
	world := &client.krunker_world
	if !client.krunker.connected || !world.has_match { return "" }
	if world.match.phase == .ENDED {
		if world.timer_kind == 3 { return "Match abandoned; waiting for the next round" }
		return "Match over; waiting for the next round"
	}
	return ""
}

krunker_client_hit_color :: proc(client: ^Client, now: f64) -> (shared.Vec4, bool) {
	world := &client.krunker_world
	visible := client.krunker.connected && world.hit_revision > 0 && now >= world.last_hit_at && now-world.last_hit_at < 0.35
	return (shared.Vec4{1, 0.25, 0.2, 1} if world.hit_lethal else shared.Vec4{1, 1, 1, 1}), visible
}
