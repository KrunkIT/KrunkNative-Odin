package menu

// Zero preserves the existing rendering of both local and remote trails.
Trail_Settings :: struct { hide_others, hide_yours: bool }

settings_trails :: proc(state: ^State) {
	settings_section("Bullet trails", state.scale)
	settings_toggle_row(state, "Bullet trails", "BulletTrails", !state.settings_draft.trails.hide_others, {kind=.TRAILS_TOGGLE})
	settings_toggle_row(state, "Your trails", "YourTrails", !state.settings_draft.trails.hide_yours, {kind=.TRAILS_TOGGLE, index=1})
	settings_note("Bullet trails shows other players' shots. Your trails shows your own shots. These controls are independent.", state.scale)
}
