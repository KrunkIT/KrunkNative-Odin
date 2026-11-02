package shared

import "core:strings"

// Custom map assets are hosted separately from mod.zip. Keep their original
// numeric asset IDs in local filenames; aid suffixes describe material flags.
Map_Custom_Asset :: struct {
	filename:   string,
	alpha_test: f32,
	emissive:   bool,
	// Converted static glTF meshes use their authored origin, unlike OBJ props.
	preserve_origin: bool,
}

map_custom_asset :: proc(aid: string) -> (asset: Map_Custom_Asset, ok: bool) {
	// The live addAsset removes material suffixes before requesting
	// <id>/model.obj and <id>/model.png. Keep model coordinates and rotations
	// unchanged; map ms is the model scale (default 1), while r supplies its
	// rotation. In particular, the t suffix is not an opacity flag.
	end := 0
	for end < len(aid) && aid[end] >= '0' && aid[end] <= '9' {
		end += 1
	}
	if end == 0 do return {}, false
	for ch in aid[end:] {
		if ch < 'a' || ch > 'z' do return {}, false
	}
	// Burg's unanimated, untextured 27432g is converted offline to OBJ. Other
	// glTF/GLB/FBX assets still require their own loader.
	flags := aid[end:]
	if aid == "27432g" do return {filename = "custom/27432", preserve_origin = true}, true
	if strings.contains(flags, "g") || strings.contains(flags, "q") || strings.contains(flags, "f") do return {}, false

	switch aid[:end] {
	case "158":   asset.filename = "custom/158"
	case "632":   asset.filename = "custom/632"
	case "2412":  asset.filename = "custom/2412"
	case "2846":  asset.filename = "custom/2846"
	case "2885":  asset.filename = "custom/2885"
	case "2923":  asset.filename = "custom/2923"
	case "3344":  asset.filename = "custom/3344"
	case "30061": asset.filename = "custom/30061"
	case "30082": asset.filename = "custom/30082"
	case "30162": asset.filename = "custom/30162"
	case "61806": asset.filename = "custom/61806"
	case "61814": asset.filename = "custom/61814"
	case "61815": asset.filename = "custom/61815"
	case "61818": asset.filename = "custom/61818"
	case "61820": asset.filename = "custom/61820"
	case "61821": asset.filename = "custom/61821"
	case "61822": asset.filename = "custom/61822"
	case "61823": asset.filename = "custom/61823"
	case "61824": asset.filename = "custom/61824"
	case "63224": asset.filename = "custom/63224"
	case: return {}, false
	}
	if strings.contains(flags, "a") do asset.alpha_test = 0.02
	asset.emissive = strings.contains(flags, "e")
	return asset, true
}
