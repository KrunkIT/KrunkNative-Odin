package shared

// Custom map assets are hosted separately from mod.zip. Keep their original
// numeric asset IDs in local filenames; aid suffixes describe material flags.
Map_Custom_Asset :: struct {
	filename:   string,
	alpha_test: f32,
}

map_custom_asset :: proc(aid: string) -> (asset: Map_Custom_Asset, ok: bool) {
	switch aid {
	case "2412a": // Sandstorm coconut palm; 'a' enables browser alphaTest 0.02.
		return {filename = "custom/2412", alpha_test = 0.02}, true
	}
	return {}, false
}
