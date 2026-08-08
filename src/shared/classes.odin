package shared

CLASS_TRIGGERMAN := Class_Config {
	name            = "Triggerman",
	icon_index      = 0,
	loadout         = []i32{1},
	secondary       = true,
	wall_jump       = false,
	colors          = [6]i32{0xA77860, 0x3D3D3D, 0x232323, 0x282828, 0x6C5042, 0xBFBFBF},
	health          = 100,
	health_segments = 6,
	regen           = 0.1,
	speed           = 1.05,
}

CLASS_HUNTER := Class_Config {
	name            = "Hunter",
	icon_index      = 1,
	loadout         = []i32{0},
	secondary       = true,
	wall_jump       = false,
	colors          = [6]i32{0xA77860, 0x7B573D, 0x634732, 0x282828, 0x634732, 0x3D2B1D},
	health          = 60,
	health_segments = 5,
	regen           = 0.1,
	speed           = 1.05,
}

CLASS_RUN_N_GUN := Class_Config {
	name            = "Run N Gun",
	icon_index      = 2,
	loadout         = []i32{3},
	secondary       = false,
	wall_jump       = true,
	colors          = [6]i32{0xA77860, 0x3E6382, 0x2F4B63, 0x282828, 0x634732, 0x1A2B3A},
	health          = 100,
	health_segments = 6,
	regen           = 0.1,
	speed           = 1.18,
}

CLASS_SPRAY_N_PRAY := Class_Config {
	name            = "Spray N Pray",
	icon_index      = 3,
	texts           = []string{"Calling in the Big Guns?", "Remember - No Russian.", "Pesky Snipers..."},
	loadout         = []i32{3},
	secondary       = false,
	wall_jump       = false,
	colors          = [6]i32{0xA77860, 0x586849, 0x49563C, 0x282828, 0x282828, 3160103},
	health          = 170,
	health_segments = 7,
	regen           = 0.05,
	speed           = 0.95,
}

CLASS_VINCE := Class_Config {
	name            = "Vince",
	icon_index      = 4,
	texts           = []string{"..."},
	loadout         = []i32{5},
	secondary       = true,
	wall_jump       = false,
	colors          = [6]i32{8412234, 5526119, 4144461, 0x282828, 0x282828, 2697267},
	health          = 90,
	health_segments = 6,
	regen           = 0.1,
	speed           = 1.0,
}

CLASS_DETECTIVE := Class_Config {
	name            = "Detective",
	icon_index      = 5,
	texts           = []string{"I'm onto something"},
	loadout         = []i32{4},
	secondary       = false,
	wall_jump       = false,
	colors          = [6]i32{0xA77860, 7360054, 4410462, 0x282828, 0x634732, 4140062},
	health          = 100,
	health_segments = 6,
	regen           = 0.1,
	speed           = 1.0,
}

CLASS_MARKSMAN := Class_Config {
	name            = "Marksman",
	icon_index      = 6,
	loadout         = []i32{7},
	secondary       = true,
	wall_jump       = false,
	colors          = [6]i32{0xA77860, 0x586849, 0x49563C, 0x282828, 0x282828, 2699298},
	health          = 90,
	health_segments = 6,
	regen           = 0.1,
	speed           = 1.0,
}

CLASS_ROCKETEER := Class_Config {
	name            = "Rocketeer",
	icon_index      = 7,
	texts           = []string{"..."},
	loadout         = []i32{8},
	secondary       = false,
	wall_jump       = false,
	colors          = [6]i32{0xA77860, 0x586849, 0x49563C, 0x282828, 0x6C5042, 0x2B3324},
	health          = 130,
	health_segments = 7,
	regen           = 0.1,
	speed           = 0.86,
}

CLASS_AGENT := Class_Config {
	name            = "Agent",
	icon_index      = 8,
	loadout         = []i32{9},
	secondary       = false,
	wall_jump       = true,
	colors          = [6]i32{0xA77860, 0x3D3D3D, 0x232323, 0x282828, 0x282828, 0xBFBFBF},
	health          = 100,
	health_segments = 6,
	regen           = 0.1,
	speed           = 1.2,
}

CLASS_RUNNER := Class_Config {
	name            = "Runner",
	icon_index      = 9,
	texts           = []string{"You sure about this?", "...", "Oh boy", "I don't know about this...", "Not me again..."},
	loadout         = []i32{12},
	secondary       = false,
	wall_jump       = true,
	colors          = [6]i32{0xA77860, 0x3D3D3D, 0x232323, 0x282828, 0x282828, 0x232323},
	health          = 120,
	health_segments = 6,
	regen           = 0.2,
	speed           = 1.0,
}

CLASS_DEAGLER := Class_Config {
	name            = "Deagler",
	icon_index      = 10,
	loadout         = []i32{10},
	secondary       = false,
	wall_jump       = false,
	colors          = [6]i32{0xA77860, 0x3D3D3D, 0x232323, 0x282828, 0x282828, 0x232323},
	health          = 60,
	health_segments = 5,
	regen           = 0.1,
	speed           = 1.0,
}

CLASS_BOWMAN := Class_Config {
	name            = "Bowman",
	icon_index      = 11,
	loadout         = []i32{13},
	secondary       = true,
	wall_jump       = false,
	colors          = [6]i32{0xA77860, 0x916C52, 0x6043E2, 0x282828, 0x282828, 0x473527},
	health          = 100,
	health_segments = 6,
	regen           = 0.1,
	speed           = 1.0,
}

CLASS_COMMANDO := Class_Config {
	name            = "Commando",
	icon_index      = 12,
	loadout         = []i32{14},
	secondary       = true,
	wall_jump       = false,
	colors          = [6]i32{0xA77860, 0x3D3D3D, 0x232323, 0x282828, 0x995C2C, 0x171717},
	health          = 100,
	health_segments = 6,
	regen           = 0.1,
	speed           = 1.0,
}

CLASS_TROOPER := Class_Config {
	name            = "Trooper",
	icon_index      = 13,
	loadout         = []i32{18},
	secondary       = false,
	wall_jump       = false,
	colors          = [6]i32{0xA77860, 0xBDC2C9, 0xBDC2C9, 0x2E2E2E, 0x282828, 0x2E2E2E},
	health          = 100,
	health_segments = 6,
	regen           = 0.1,
	speed           = 1.0,
}

CLASSES_LIST := [?]Class_Config{
	CLASS_TRIGGERMAN,
	CLASS_HUNTER,
	CLASS_RUN_N_GUN,
	CLASS_SPRAY_N_PRAY,
	CLASS_VINCE,
	CLASS_DETECTIVE,
	CLASS_MARKSMAN,
	CLASS_ROCKETEER,
	CLASS_AGENT,
	CLASS_RUNNER,
	CLASS_DEAGLER,
	CLASS_BOWMAN,
	CLASS_COMMANDO,
	CLASS_TROOPER,
}

// Stable class IDs enabled by the standard ruleset. Other classes remain
// addressable by name for custom servers and command-line testing.
ROTATION_CLASSES := [?]i32{0, 1, 2, 3, 5, 6, 8, 12, 13}

class_rotation_count :: proc() -> int {
	return len(ROTATION_CLASSES)
}

class_rotation_id :: proc(index: int) -> i32 {
	if index < 0 || index >= len(ROTATION_CLASSES) {
		return -1
	}
	return ROTATION_CLASSES[index]
}

class_is_in_rotation :: proc(class_id: i32) -> bool {
	for allowed in ROTATION_CLASSES {
		if class_id == allowed {
			return true
		}
	}
	return false
}
