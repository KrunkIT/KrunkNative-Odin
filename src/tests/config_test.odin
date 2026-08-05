package main

import "core:fmt"

import shared "../shared"

test_gameplay_config :: proc() -> bool {
	config := shared.config_load_gameplay()
	defer shared.config_destroy_gameplay(config)

	defaults_ok :=
		len(config.weapons) == len(shared.WEAPONS_LIST) &&
		len(config.classes) == len(shared.CLASSES_LIST) &&
		config.weapons[0] != shared.WEAPONS_LIST[0] &&
		config.weapons[0].name == shared.WEAPONS_LIST[0].name &&
		config.weapons[0].damage == shared.WEAPONS_LIST[0].damage &&
		config.classes[0].name == shared.CLASSES_LIST[0].name &&
		config.classes[0].health == shared.CLASSES_LIST[0].health
	if !defaults_ok {
		fmt.eprintln("Gameplay config default-copy test failed")
		return false
	}

	weapon_default_damage := shared.WEAPONS_LIST[0].damage
	class_default_name := shared.CLASSES_LIST[0].name

	weapon_ok := shared.config_apply_toml(
		config,
		`
[weapons.awp]
damage = 42.5
origin = [1, 2, 3]
sound = "sounds/awp_fire.wav"
`,
	)
	class_ok := shared.config_apply_toml(
		config,
		`
[classes.triggerman]
name = "Configured"
health = 125
`,
	)
	override_ok :=
		weapon_ok &&
		class_ok &&
		config.weapons[0].damage == 42.5 &&
		config.weapons[0].origin == shared.Vec3{1, 2, 3} &&
		config.weapons[0].sound == "sounds/awp_fire.wav" &&
		config.classes[0].name == "Configured" &&
		config.classes[0].health == 125 &&
		shared.WEAPONS_LIST[0].damage == weapon_default_damage &&
		shared.CLASSES_LIST[0].name == class_default_name
	if !override_ok {
		fmt.eprintln("Gameplay config partial-override test failed")
		return false
	}

	// Named loadouts must resolve to stable weapon indices.
	loadout_ok := shared.config_apply_toml(
		config,
		`
[classes.trooper]
loadout = ["ak47", "deagle", "knife"]
`,
	)
	if !loadout_ok ||
		len(config.classes[13].loadout) != 3 ||
		config.classes[13].loadout[0] != 1 ||
		config.classes[13].loadout[1] != 10 ||
		config.classes[13].loadout[2] != 12 {
		fmt.eprintln("Gameplay config named-loadout resolution test failed")
		return false
	}

	fmt.println("Gameplay config tests OK")
	return true
}
