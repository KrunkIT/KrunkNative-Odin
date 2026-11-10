package shared

// Optional, client-consumed effects. Dedicated servers never enable this queue.
// These events do not affect simulation or go over the network.
Presentation_Kind :: enum { FIRE, RELOAD, SWAP, STEP, JUMP, LAND, SLIDE, DAMAGE, HIT, EXPLOSION }
Presentation_Event :: struct {
	kind: Presentation_Kind,
	uid, weapon_id: i32,
	position: Vec3,
	value: f32,
	headshot: bool,
}

game_emit_presentation :: proc(game: ^Game, event: Presentation_Event) {
	if game == nil || !game.presentation_enabled { return }
	if len(game.presentation_events) >= 256 { ordered_remove(&game.presentation_events, 0) }
	append(&game.presentation_events, event)
}

player_emit_presentation :: proc(player: ^Player, kind: Presentation_Kind) {
	if player == nil || player.game == nil || !player.game.presentation_enabled { return }
	weapon_id: i32 = -1
	if player.loadout_index >= 0 && player.loadout_index < player.loadout_size { weapon_id = player.loadout[player.loadout_index] }
	game_emit_presentation(player.game, {
		kind = kind, uid = player.uid, weapon_id = weapon_id,
		position = player.position + Vec3{0, player.height - GAME_CONSTANTS.camera_height, 0},
		value = player.crouch_val,
	})
}
