package shared

import "base:runtime"

// Keep one source of class defaults for the client, server, and simulation.
// Embedding the export also covers packaged installs without krunker-configs/.
CLASS_CONFIG_SOURCE :: #load("../../krunker-configs/class-configs.json", string)

CLASSES_LIST := class_defaults_from_json()

class_defaults_from_json :: proc "contextless" () -> [len(class_config_names)]Class_Config {
	context = runtime.default_context()
	classes, ok := config_parse_class_json(CLASS_CONFIG_SOURCE, context.allocator)
	if !ok {
		panic("Invalid built-in krunker-configs/class-configs.json")
	}
	return classes
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
