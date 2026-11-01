package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import shared "../shared"

test_sandstorm_palms :: proc() -> bool {
	map_path := strings.concatenate({shared.assets_path(), "maps/", shared.map_asset_name("sandstorm"), ".json"})
	defer delete(map_path)
	map_inst, loaded := shared.map_load_from_file(map_path)
	if !loaded {
		fmt.eprintln("Sandstorm palm test: map could not be loaded")
		return false
	}
	defer shared.map_destroy(map_inst)

	palm_count := 0
	for object in map_inst.objects {
		raw, is_object := object.raw_data.(json.Object)
		if !is_object do continue
		aid, is_string := raw["aid"].(json.String)
		if !is_string || aid != "2412a" do continue

		palm_count += 1
		asset, supported := shared.map_custom_asset(string(aid))
		if object.prefab != .CUSTOM_ASSET || !supported || asset.filename != "custom/2412" || abs(asset.alpha_test - 0.02) > 0.0001 {
			fmt.eprintln("Sandstorm palm test: custom palm resolved to the wrong mesh/material")
			return false
		}
		model_scale := shared.get_json_f32(raw["ms"])
		// The original palm is 33.700444 units tall; map collision dimensions
		// are its bounds multiplied by ms, not the generic tree's dimensions.
		if model_scale <= 0 || abs(object.scale.y - 33.700444 * model_scale) > 0.02 {
			fmt.eprintln("Sandstorm palm test: model scale does not match the map bounds")
			return false
		}
	}
	if palm_count != 36 {
		fmt.eprintf("Sandstorm palm test: expected 36 palms, found %d\n", palm_count)
		return false
	}

	asset, _ := shared.map_custom_asset("2412a")
	model_path := strings.concatenate({shared.assets_path(), "models/", asset.filename, ".obj"})
	texture_path := strings.concatenate({shared.assets_path(), "textures/", asset.filename, ".png"})
	defer delete(model_path)
	defer delete(texture_path)
	if !os.exists(model_path) || !os.exists(texture_path) {
		fmt.eprintln("Sandstorm palm test: original custom model or texture is missing")
		return false
	}
	if _, supported := shared.map_custom_asset("unknown"); supported {
		fmt.eprintln("Sandstorm palm test: unsupported custom asset was substituted")
		return false
	}
	fmt.println("Sandstorm custom palm asset tests OK")
	return true
}
