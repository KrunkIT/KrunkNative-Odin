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
	return test_custom_map_assets() && test_builtin_map_textures()
}

// Verify that every map-authored `t`/`tv` pair has a corresponding image in
// the extracted mod pack. A missing texture otherwise binds the renderer's
// white fallback and makes an entire map surface look untextured.
test_builtin_map_textures :: proc() -> bool {
	texture_names := [?]string{
		"wall", "dirt", "floor", "grid", "grey", "default", "roof", "flag",
		"grass", "check", "lines", "brick", "link", "liquid", "grain", "fabric",
		"tile", "metal", "sand", "snow",
	}
	map_names := [?]string{
		"burg", "citadel", "evacuation", "freight", "industry", "kanji", "littletown",
		"lostworld", "newtown", "oasis", "sandstorm", "sandstorm_v3", "shipyard",
		"soul_sanctum", "subzero", "undergrowth",
	}

	checked := 0
	for name in map_names {
		map_path := strings.concatenate({shared.assets_path(), "maps/", name, ".json"})
		map_inst, loaded := shared.map_load_from_file(map_path)
		delete(map_path)
		if !loaded {
			fmt.eprintf("Map texture test: could not load %s\n", name)
			return false
		}

		failed := false
		for object, object_index in map_inst.objects {
			texture_index := int(object.texture)
			if texture_index == 5 {
				// DEFAULT is intentionally untextured in the live registry.
				continue
			}
			if texture_index < 0 || texture_index >= len(texture_names) {
				fmt.eprintf("Map texture test: %s object=%d has unknown texture index %d\n", name, object_index, texture_index)
				failed = true
				continue
			}

			base_suffix := "_0"
			if texture_index == 8 {
				// Browser registry's GRASS source is grass_1.png.
				base_suffix = "_1"
			}
			texture_file := strings.concatenate({texture_names[texture_index], base_suffix})
			if object.texture_variant > 0 {
				texture_file = fmt.tprintf("%s_%d", texture_file, object.texture_variant)
			}
			texture_path := strings.concatenate({shared.assets_path(), "textures/", texture_file, ".png"})
			if !os.exists(texture_path) {
				fmt.eprintf("Map texture test: %s object=%d t=%d tv=%d missing %s\n", name, object_index, texture_index, object.texture_variant, texture_path)
				failed = true
			}
			delete(texture_path)
			checked += 1
		}
		shared.map_destroy(map_inst)
		if failed {
			return false
		}
	}

	if checked < 1000 {
		fmt.eprintf("Map texture test: expected at least 1000 textured objects, found %d\n", checked)
		return false
	}
	fmt.eprintf("Map texture registry test OK (%d textured objects)\n", checked)
	return true
}

// Exercise every locally exported custom reference, including decorative AI
// assets, so a map update cannot silently leave a model or texture unaccounted.
test_custom_map_assets :: proc() -> bool {
	map_names := [?]string{"sandstorm_v3", "undergrowth", "evacuation"}
	total_assets := 0
	for name in map_names {
		path := strings.concatenate({shared.assets_path(), "maps/", name, ".json"})
		map_inst, loaded := shared.map_load_from_file(path)
		delete(path)
		if !loaded {
			fmt.eprintf("Custom asset test: could not load %s\n", name)
			return false
		}
		failed := false
		asset_count := 0
		for object in map_inst.objects {
			raw, is_object := object.raw_data.(json.Object)
			if !is_object do continue
			aid, is_string := raw["aid"].(json.String)
			if !is_string || len(aid) == 0 do continue
			asset_count += 1
			asset, supported := shared.map_custom_asset(string(aid))
			if !supported {
				fmt.eprintf("Custom asset test: %s aid=%s has no local asset registry entry\n", name, aid)
				failed = true
				continue
			}
			model := strings.concatenate({shared.assets_path(), "models/", asset.filename, ".obj"})
			texture := strings.concatenate({shared.assets_path(), "textures/", asset.filename, ".png"})
			model_data, model_error := os.read_entire_file_from_path(model, context.allocator)
			texture_data, texture_error := os.read_entire_file_from_path(texture, context.allocator)
			if model_error != nil || !strings.contains(string(model_data), "\nv ") || !strings.contains(string(model_data), "\nf ") {
				fmt.eprintf("Custom asset test: %s aid=%s missing or invalid OBJ %s\n", name, aid, model)
				failed = true
			}
			png_signature := []u8{137, 80, 78, 71, 13, 10, 26, 10}
			png_ok := texture_error == nil && len(texture_data) >= len(png_signature)
			if png_ok {
				for byte, index in png_signature {
					if texture_data[index] != byte do png_ok = false
				}
			}
			if !png_ok {
				fmt.eprintf("Custom asset test: %s aid=%s missing or invalid PNG %s\n", name, aid, texture)
				failed = true
			}
			delete(model_data)
			delete(texture_data)
			delete(model)
			delete(texture)
		}
		shared.map_destroy(map_inst)
		total_assets += asset_count
		if failed {
			fmt.eprintf("Custom asset test: map=%s failed=%v asset_count=%d\n", name, failed, asset_count)
			return false
		}
	}
	if total_assets < 100 {
		fmt.eprintf("Custom asset test: expected current Sandstorm decorations, found %d custom references\n", total_assets)
		return false
	}
	window, window_ok := shared.map_custom_asset("2885t")
	palm, palm_ok := shared.map_custom_asset("2412a")
	emissive, emissive_ok := shared.map_custom_asset("63224e")
	if !window_ok || !palm_ok || !emissive_ok || window.filename != "custom/2885" || window.alpha_test != 0 || palm.alpha_test != 0.02 || !emissive.emissive {
		fmt.eprintln("Custom asset test: numeric asset ID or material suffix resolved incorrectly")
		return false
	}
	bad_aids := [?]string{"", "unknown", "999999", "../2412a", "2412.obj", "2412g", "2412q", "2412f"}
	for aid in bad_aids {
		if _, supported := shared.map_custom_asset(aid); supported {
			fmt.eprintf("Custom asset test: unsupported aid=%s accepted as a static OBJ\n", aid)
			return false
		}
	}
	fmt.println("Map custom asset registry/OBJ/PNG/material suffix tests OK")
	return true
}
