package main

import "core:encoding/json"
import menuui "../menu"
import shared "../shared"

Map_Detail :: enum { NONE, CAT, EXTRA_PROP }

map_object_detail :: proc(object: ^shared.Object) -> Map_Detail {
	raw, ok := object.raw_data.(json.Object)
	if ok {
		if aid, is_string := raw["aid"].(json.String); is_string {
			// Material suffixes (e.g. a/e/t) do not change the asset identity.
			end := 0
			for end < len(aid) && aid[end] >= '0' && aid[end] <= '9' { end += 1 }
			switch string(aid[:end]) {
			case "61806", "61814", "61815", "61818", "61820", "61821", "61822", "61823", "61824": return .CAT
			case "30061", "30082", "30162": return .EXTRA_PROP // Loose planks, rubble/junk, fabric.
			}
		}
	}
	if object.prefab == .GRASS { return .EXTRA_PROP }
	return .NONE
}

client_update_map_details :: proc(client: ^Client, settings: menuui.Visual_Settings) {
	if client.game.map_inst == nil { return }
	for object in client.game.map_inst.objects {
		if object.mesh == nil { continue }
		mesh := cast(^Mesh)object.mesh
		#partial switch mesh.map_detail {
		case .CAT: mesh.visible = mesh.map_detail_visible && !settings.hide_cats
		case .EXTRA_PROP: mesh.visible = mesh.map_detail_visible && !settings.hide_extra_props
		}
	}
}
