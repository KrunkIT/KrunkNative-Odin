package shared

DEFAULT_GAME_MODE_CONFIG := Game_Mode_Config {
	team_class      = {-1, -1, -1},
	speed_mlt       = {1.0, 1.0, 1.0},
	hitbox_pad      = 1.0,
}

ffa_mode_init :: proc() -> ^Game_Mode {
	mode := new(Game_Mode)
	mode.config = DEFAULT_GAME_MODE_CONFIG
	// The initial public ruleset is objective-focused. Keep the existing mode ID
	// for compatibility while the richer data-driven mode registry is built.
	mode.config.teams = true
	mode.objective = true
	return mode
}

mode_init :: proc(index: i32) -> ^Game_Mode {
	switch index {
	case 0:
		return ffa_mode_init()
	}

	return nil
}

mode_fini :: proc(mode: ^Game_Mode) {
	if mode != nil {
		free(mode)
	}
}
