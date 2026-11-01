package main

import "core:encoding/json"
import "core:fmt"
import krunker "../krunker"

test_krunker_seek_query :: proc() -> bool {
	versions := []string{"1.0.0", "fixtureOpaqueVersion0123456789abcd", "quoted\"version\\path\nü"}
	for version in versions {
		query, ok := krunker.krunker_seek_data_query(version)
		if !ok { fmt.eprintln("Seek dataQuery serialization failed"); return false }
		value, err := json.parse_string(query)
		delete(query)
		if err != .None { fmt.eprintln("Seek dataQuery is not valid JSON"); return false }
		object, object_ok := value.(json.Object)
		parsed_version, version_ok := object["v"].(json.String)
		matches := object_ok && version_ok && len(object) == 1 && string(parsed_version) == version
		json.destroy_value(value)
		if !matches { fmt.eprintln("Seek dataQuery version did not round trip"); return false }
	}
	encoded := krunker.network_url_encode(`{"v":"1.0.0"}`)
	defer delete(encoded)
	if encoded != "%7B%22v%22%3A%221.0.0%22%7D" { fmt.eprintln("Seek dataQuery percent encoding incorrect"); return false }
	fmt.println("Krunker seek-game dataQuery JSON/escaping tests OK")
	return true
}
