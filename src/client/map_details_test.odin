package main

import "core:encoding/json"
import "core:testing"
import "core:strings"
import menuui "../menu"
import shared "../shared"

when ODIN_TEST {
	@(test)
	map_detail_visibility_preview_and_restore :: proc(t: ^testing.T) {
		for name in ([2]string{"burg", "sandstorm_v3"}) {
			path := strings.concatenate({shared.assets_path(), "maps/", name, ".json"})
			map_inst, ok := shared.map_load_from_file(path)
			delete(path)
			if !testing.expect(t, ok) { continue }
			defer shared.map_destroy(map_inst)
			meshes := make([]Mesh, len(map_inst.objects))
			defer delete(meshes)
			cat_count, extra_count := 0, 0
			for object, i in map_inst.objects {
				raw := object.raw_data.(json.Object)
				visible := shared.get_json_f32(raw["v"]) != 1
				meshes[i] = {visible=visible, map_detail_visible=visible, map_detail=map_object_detail(object)}
				object.mesh = rawptr(&meshes[i])
				if meshes[i].map_detail == .CAT { cat_count += 1 }
				if meshes[i].map_detail == .EXTRA_PROP { extra_count += 1 }
			}
			testing.expect(t, cat_count>0 && extra_count>0, "both real maps must exercise cats and loose decorative props")
			client := Client{visual_settings=menuui.DEFAULT_VISUAL_SETTINGS}
			client.game.map_inst = map_inst
			client.menu.page = .SETTINGS
			menuui.prepare_settings(&client.menu, {visuals=client.visual_settings})
			menuui.activate(&client.menu, {action={kind=.VISUAL_TOGGLE, index=0}})
			preview, _ := client_graphics_values(&client)
			client_update_map_details(&client, preview)
			for mesh in meshes {
				testing.expect(t, mesh.visible == (mesh.map_detail_visible && mesh.map_detail!=.CAT), "Hide cats must hide every cat and preserve other models")
			}
			menuui.activate(&client.menu, {action={kind=.VISUAL_TOGGLE, index=1}})
			preview, _ = client_graphics_values(&client)
			client_update_map_details(&client, preview)
			for mesh in meshes {
				testing.expect(t, mesh.visible == (mesh.map_detail_visible && mesh.map_detail==.NONE), "Hide extra props must hide clutter while retaining buildings and map geometry")
			}
			menuui.activate(&client.menu, {action={kind=.SETTINGS_CANCEL}})
			restored, _ := client_graphics_values(&client)
			client_update_map_details(&client, restored)
			for mesh in meshes {
				testing.expect(t, mesh.visible==mesh.map_detail_visible, "Cancel must restore the map's authored visibility, including hidden meshes")
			}
		}
	}
}
