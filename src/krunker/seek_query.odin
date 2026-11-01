package krunker

import "core:encoding/json"
import "core:strings"

Krunker_Seek_Query :: struct { v: string }

// Odin's fmt treats braces as format syntax. Serialize the payload instead of
// embedding JSON braces in a format string; also handles escaping in versions.
krunker_seek_data_query :: proc(version: string) -> (string, bool) {
	data, err := json.marshal(Krunker_Seek_Query{v = version})
	defer delete(data)
	if err != nil do return "", false
	return strings.clone(string(data)), true
}

network_url_encode :: proc(value: string) -> string {
	builder, err := strings.builder_make_none()
	if err != nil do return ""
	defer strings.builder_destroy(&builder)
	hex := "0123456789ABCDEF"
	for i in 0 ..< len(value) {
		b := value[i]
		safe := b >= 'a' && b <= 'z' || b >= 'A' && b <= 'Z' || b >= '0' && b <= '9' || b == '-' || b == '_' || b == '.' || b == '~'
		if safe { strings.write_byte(&builder, b) }
		else { strings.write_byte(&builder, '%'); strings.write_byte(&builder, hex[b >> 4]); strings.write_byte(&builder, hex[b & 15]) }
	}
	return strings.clone(strings.to_string(builder))
}
