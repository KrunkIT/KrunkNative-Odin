package krunker

import "core:mem"

// Minimal MessagePack framing for Krunker's game socket.
//
// Krunker wraps one MessagePack array ([opcode, arg0, ...]) with a two-byte
// trailer.  The trailer is a byte split into two nibbles, not a checksum:
// trailer[0] = counter >> 4, trailer[1] = counter & 0xf.
// The bounded decoder also preserves maps, binary blobs, and extension values
// so unknown server arguments can be logged without lossy coercion.

Krunker_Msgpack_Nil :: struct{}
Krunker_Msgpack_Binary :: struct { data: []byte }
Krunker_Msgpack_Ext :: struct { type_id: i8, data: []byte }
Krunker_Msgpack_Map_Entry :: struct { key, value: Krunker_Msgpack_Value }

Krunker_Msgpack_Value :: union {
	Krunker_Msgpack_Nil,
	bool,
	i64,
	f64,
	string,
	Krunker_Msgpack_Binary,
	Krunker_Msgpack_Ext,
	[]Krunker_Msgpack_Value,
	[]Krunker_Msgpack_Map_Entry,
}

krunker_msgpack_nil :: proc() -> Krunker_Msgpack_Value {
	return Krunker_Msgpack_Nil{}
}

krunker_msgpack_bool :: proc(value: bool) -> Krunker_Msgpack_Value {
	return value
}

krunker_msgpack_int :: proc(value: i64) -> Krunker_Msgpack_Value {
	return value
}

krunker_msgpack_float :: proc(value: f64) -> Krunker_Msgpack_Value {
	return value
}

krunker_msgpack_string :: proc(value: string) -> Krunker_Msgpack_Value {
	return value
}

krunker_msgpack_array :: proc(value: []Krunker_Msgpack_Value) -> Krunker_Msgpack_Value {
	return value
}

krunker_msgpack_binary :: proc(value: []byte) -> Krunker_Msgpack_Value { return Krunker_Msgpack_Binary{value} }
krunker_msgpack_ext :: proc(type_id: i8, value: []byte) -> Krunker_Msgpack_Value { return Krunker_Msgpack_Ext{type_id, value} }
krunker_msgpack_map :: proc(value: []Krunker_Msgpack_Map_Entry) -> Krunker_Msgpack_Value { return value }

krunker_msgpack_write_u16 :: proc(out: ^[dynamic]byte, value: u16) {
	append(out, byte(value >> 8), byte(value))
}

krunker_msgpack_write_u32 :: proc(out: ^[dynamic]byte, value: u32) {
	append(out,
		byte(value >> 24),
		byte(value >> 16),
		byte(value >> 8),
		byte(value),
	)
}

krunker_msgpack_write_u64 :: proc(out: ^[dynamic]byte, value: u64) {
	append(out,
		byte(value >> 56),
		byte(value >> 48),
		byte(value >> 40),
		byte(value >> 32),
		byte(value >> 24),
		byte(value >> 16),
		byte(value >> 8),
		byte(value),
	)
}

krunker_msgpack_write_value :: proc(out: ^[dynamic]byte, value: Krunker_Msgpack_Value) -> bool {
	#partial switch typed in value {
	case Krunker_Msgpack_Nil:
		append(out, 0xc0)
	case bool:
		append(out, typed ? 0xc3 : 0xc2)
	case i64:
		if typed >= 0 {
			u := u64(typed)
			switch {
			case u < 0x80:
				append(out, byte(u))
			case u < 0x100:
				append(out, 0xcc, byte(u))
			case u < 0x10000:
				append(out, 0xcd)
				krunker_msgpack_write_u16(out, u16(u))
			case u < 0x100000000:
				append(out, 0xce)
				krunker_msgpack_write_u32(out, u32(u))
			case:
				append(out, 0xcf)
				krunker_msgpack_write_u64(out, u)
			}
		} else if typed >= -32 {
			append(out, byte(i8(typed)))
		} else if typed >= -128 {
			append(out, 0xd0, byte(i8(typed)))
		} else if typed >= -32768 {
			append(out, 0xd1)
			krunker_msgpack_write_u16(out, u16(i16(typed)))
		} else if typed >= -2147483648 {
			append(out, 0xd2)
			krunker_msgpack_write_u32(out, u32(i32(typed)))
		} else {
			append(out, 0xd3)
			krunker_msgpack_write_u64(out, u64(typed))
		}
	case f64:
		append(out, 0xcb)
		krunker_msgpack_write_u64(out, transmute(u64)typed)
	case string:
		length := len(typed)
		switch {
		case length < 0x20:
			append(out, byte(0xa0 + length))
		case length < 0x100:
			append(out, 0xd9, byte(length))
		case length < 0x10000:
			append(out, 0xda)
			krunker_msgpack_write_u16(out, u16(length))
		case:
			append(out, 0xdb)
			krunker_msgpack_write_u32(out, u32(length))
		}
		for i in 0..<len(typed) {
			append(out, typed[i])
		}
	case Krunker_Msgpack_Binary:
		length := len(typed.data)
		switch { case length < 0x100: append(out, 0xc4, byte(length)); case length < 0x10000: append(out, 0xc5); krunker_msgpack_write_u16(out, u16(length)); case: append(out, 0xc6); krunker_msgpack_write_u32(out, u32(length)) }
		append(out, ..typed.data)
	case Krunker_Msgpack_Ext:
		length := len(typed.data)
		switch { case length == 1: append(out, 0xd4); case length == 2: append(out, 0xd5); case length == 4: append(out, 0xd6); case length == 8: append(out, 0xd7); case length == 16: append(out, 0xd8); case length < 0x100: append(out, 0xc7, byte(length)); case length < 0x10000: append(out, 0xc8); krunker_msgpack_write_u16(out, u16(length)); case: append(out, 0xc9); krunker_msgpack_write_u32(out, u32(length)) }
		append(out, byte(typed.type_id)); append(out, ..typed.data)
	case []Krunker_Msgpack_Map_Entry:
		length := len(typed)
		switch { case length < 0x10: append(out, byte(0x80 + length)); case length < 0x10000: append(out, 0xde); krunker_msgpack_write_u16(out, u16(length)); case: append(out, 0xdf); krunker_msgpack_write_u32(out, u32(length)) }
		for &entry in typed { if !krunker_msgpack_write_value(out, entry.key) || !krunker_msgpack_write_value(out, entry.value) { return false } }
	case []Krunker_Msgpack_Value:
		length := len(typed)
		switch {
		case length < 0x10:
			append(out, byte(0x90 + length))
		case length < 0x10000:
			append(out, 0xdc)
			krunker_msgpack_write_u16(out, u16(length))
		case:
			append(out, 0xdd)
			krunker_msgpack_write_u32(out, u32(length))
		}
		for &element in typed {
			if !krunker_msgpack_write_value(out, element) {
				return false
			}
		}
	}
	return true
}

// krunker_msgpack_encode_packet serializes [opcode, args...] and appends the
// two-byte nibble trailer.  The caller owns the returned dynamic array.
krunker_msgpack_encode_packet :: proc(opcode: string, args: []Krunker_Msgpack_Value, counter: u8) -> ([]byte, bool) {
	values := make([dynamic]Krunker_Msgpack_Value, len(args) + 1)
	defer delete(values)
	values[0] = krunker_msgpack_string(opcode)
	for arg, i in args {
		values[i + 1] = arg
	}

	out := make([dynamic]byte, 0, 64)
	if !krunker_msgpack_write_value(&out, krunker_msgpack_array(values[:])) {
		delete(out)
		return nil, false
	}
	append(&out, byte((counter >> 4) & 0x0f), byte(counter & 0x0f))
	return out[:], true
}

// The live server requires +37, confirmed with continuous traffic and the
// reference hoster's nibble counter. The archived browser snapshot uses +3;
// its idle spawn probe sends too few packets to expose that incompatibility.
// cptR is the one opcode that does not advance the counter.
krunker_msgpack_counter_next :: proc(counter: u8, opcode: string) -> u8 {
	if opcode == "cptR" {
		return counter
	}
	return counter + 37
}

krunker_msgpack_decode_trailer :: proc(packet: []byte) -> (counter: u8, body: []byte, ok: bool) {
	if len(packet) < 3 {
		return 0, nil, false
	}
	hi := packet[len(packet) - 2]
	lo := packet[len(packet) - 1]
	if hi > 0x0f || lo > 0x0f {
		return 0, nil, false
	}
	return (hi << 4) | lo, packet[:len(packet) - 2], true
}

// krunker_msgpack_peek_opcode validates the outer array and decodes only its
// first string element.  It is useful for dispatch/logging while the complete
// argument decoder is still being ported; it never allocates or interprets
// opcode arguments.
krunker_msgpack_peek_opcode :: proc(packet: []byte) -> (opcode: string, counter: u8, ok: bool) {
	decoded_counter, body, trailer_ok := krunker_msgpack_decode_trailer(packet)
	if !trailer_ok || len(body) < 2 {
		return "", 0, false
	}
	offset := 0
	array_header := body[offset]
	offset += 1
	switch {
	case array_header >= 0x91 && array_header <= 0x9f:
	case array_header == 0xdc:
		if len(body) < offset + 2 { return "", 0, false }
		if body[offset] == 0 && body[offset + 1] == 0 { return "", 0, false }
		offset += 2
	case array_header == 0xdd:
		if len(body) < offset + 4 { return "", 0, false }
		if body[offset] == 0 && body[offset + 1] == 0 && body[offset + 2] == 0 && body[offset + 3] == 0 { return "", 0, false }
		offset += 4
	case:
		return "", 0, false
	}
	if offset >= len(body) {
		return "", 0, false
	}
	string_header := body[offset]
	offset += 1
	length: int
	switch {
	case string_header >= 0xa0 && string_header <= 0xbf:
		length = int(string_header - 0xa0)
	case string_header == 0xd9:
		if len(body) < offset + 1 { return "", 0, false }
		length = int(body[offset]); offset += 1
	case string_header == 0xda:
		if len(body) < offset + 2 { return "", 0, false }
		length = int(body[offset]) << 8 | int(body[offset + 1]); offset += 2
	case string_header == 0xdb:
		if len(body) < offset + 4 { return "", 0, false }
		length = int(body[offset]) << 24 | int(body[offset + 1]) << 16 | int(body[offset + 2]) << 8 | int(body[offset + 3]); offset += 4
	case:
		return "", 0, false
	}
	if length <= 0 || len(body) < offset + length {
		return "", 0, false
	}
	return string(body[offset:offset + length]), decoded_counter, true
}

// Decoded containers allocate with context.allocator, so a temporary arena
// owned by the receive loop can release an entire frame at once. String,
// binary and extension contents borrow the packet bytes and remain valid only
// while that packet remains alive. No decoder procedure changes the allocator.
KRUNKER_MSGPACK_MAX_DEPTH :: 64
KRUNKER_MSGPACK_MAX_VALUES :: 1_000_000
KRUNKER_MSGPACK_MAX_BYTES :: 16 * 1024 * 1024

Krunker_Msgpack_Reader :: struct {
	data: []byte,
	pos: int,
	values_left: int,
	error: string,
	allocator: mem.Allocator,
}

krunker_msgpack_read_uint :: proc(reader: ^Krunker_Msgpack_Reader, count: int) -> (u64, bool) {
	if count < 0 || count > 8 || count > len(reader.data) - reader.pos {
		reader.error = "truncated MessagePack integer or length"
		return 0, false
	}
	value: u64
	for _ in 0..<count { value = (value << 8) | u64(reader.data[reader.pos]); reader.pos += 1 }
	return value, true
}

krunker_msgpack_read_blob :: proc(reader: ^Krunker_Msgpack_Reader, length: u64) -> ([]byte, bool) {
	if length > KRUNKER_MSGPACK_MAX_BYTES || length > u64(len(reader.data) - reader.pos) {
		reader.error = "MessagePack string/binary/extension exceeds limit or is truncated"
		return nil, false
	}
	start := reader.pos
	reader.pos += int(length)
	return reader.data[start:reader.pos], true
}

krunker_msgpack_read_array :: proc(reader: ^Krunker_Msgpack_Reader, count: u64, depth: int) -> (Krunker_Msgpack_Value, bool) {
	if count > u64(reader.values_left) || count > u64(len(reader.data) - reader.pos) {
		reader.error = "MessagePack array exceeds value budget or is truncated"
		return nil, false
	}
	values := make([]Krunker_Msgpack_Value, int(count), reader.allocator)
	for &value in values {
		decoded, ok := krunker_msgpack_read_value(reader, depth + 1)
		if !ok { return nil, false }
		value = decoded
	}
	return values, true
}

krunker_msgpack_read_map :: proc(reader: ^Krunker_Msgpack_Reader, count: u64, depth: int) -> (Krunker_Msgpack_Value, bool) {
	if count > u64(reader.values_left / 2) || count > u64((len(reader.data) - reader.pos) / 2) {
		reader.error = "MessagePack map exceeds value budget or is truncated"
		return nil, false
	}
	entries := make([]Krunker_Msgpack_Map_Entry, int(count), reader.allocator)
	for &entry in entries {
		key, key_ok := krunker_msgpack_read_value(reader, depth + 1)
		if !key_ok { return nil, false }
		value, value_ok := krunker_msgpack_read_value(reader, depth + 1)
		if !value_ok { return nil, false }
		entry = {key, value}
	}
	return entries, true
}

krunker_msgpack_read_value :: proc(reader: ^Krunker_Msgpack_Reader, depth: int) -> (Krunker_Msgpack_Value, bool) {
	if depth > KRUNKER_MSGPACK_MAX_DEPTH { reader.error = "MessagePack nesting exceeds 64 levels"; return nil, false }
	if reader.values_left <= 0 { reader.error = "MessagePack value budget exhausted"; return nil, false }
	if reader.pos >= len(reader.data) { reader.error = "truncated MessagePack value"; return nil, false }
	reader.values_left -= 1
	head := reader.data[reader.pos]; reader.pos += 1
	if head <= 0x7f { return i64(head), true }
	if head >= 0xe0 { return i64(i8(head)), true }
	if head >= 0xa0 && head <= 0xbf {
		blob, ok := krunker_msgpack_read_blob(reader, u64(head & 0x1f)); if !ok { return nil, false }; return string(blob), true
	}
	if head >= 0x90 && head <= 0x9f { return krunker_msgpack_read_array(reader, u64(head & 0x0f), depth) }
	if head >= 0x80 && head <= 0x8f { return krunker_msgpack_read_map(reader, u64(head & 0x0f), depth) }
	switch head {
	case 0xc0: return Krunker_Msgpack_Nil{}, true
	case 0xc2: return false, true
	case 0xc3: return true, true
	case 0xcc, 0xcd, 0xce, 0xcf:
		count := 1 << uint(head - 0xcc)
		number, ok := krunker_msgpack_read_uint(reader, count); if !ok { return nil, false }
		// Wire u64 values above i64's range are retained as f64, matching JS
		// number semantics. Other unsigned integers retain exact i64 values.
		if number > 0x7fff_ffff_ffff_ffff { return f64(number), true }
		return i64(number), true
	case 0xd0, 0xd1, 0xd2, 0xd3:
		count := 1 << uint(head - 0xd0)
		number, ok := krunker_msgpack_read_uint(reader, count); if !ok { return nil, false }
		switch count { case 1: return i64(i8(number)), true; case 2: return i64(i16(number)), true; case 4: return i64(i32(number)), true; case: return i64(number), true }
	case 0xca:
		number, ok := krunker_msgpack_read_uint(reader, 4); if !ok { return nil, false }; return f64(transmute(f32)u32(number)), true
	case 0xcb:
		number, ok := krunker_msgpack_read_uint(reader, 8); if !ok { return nil, false }; return transmute(f64)number, true
	case 0xd9, 0xda, 0xdb, 0xc4, 0xc5, 0xc6:
		count := 1
		if head == 0xda || head == 0xc5 { count = 2 }; if head == 0xdb || head == 0xc6 { count = 4 }
		length, length_ok := krunker_msgpack_read_uint(reader, count); if !length_ok { return nil, false }
		blob, blob_ok := krunker_msgpack_read_blob(reader, length); if !blob_ok { return nil, false }
		if head >= 0xd9 { return string(blob), true }; return Krunker_Msgpack_Binary{blob}, true
	case 0xdc, 0xdd, 0xde, 0xdf:
		count := 2; if head == 0xdd || head == 0xdf { count = 4 }
		length, length_ok := krunker_msgpack_read_uint(reader, count); if !length_ok { return nil, false }
		if head == 0xdc || head == 0xdd { return krunker_msgpack_read_array(reader, length, depth) }
		return krunker_msgpack_read_map(reader, length, depth)
	case 0xc7, 0xc8, 0xc9, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8:
		length: u64
		if head >= 0xd4 { length = u64(1) << u64(head - 0xd4) } else {
			count := 1 << uint(head - 0xc7)
			decoded_length, ok := krunker_msgpack_read_uint(reader, count); if !ok { return nil, false }; length = decoded_length
		}
		type_id, type_ok := krunker_msgpack_read_uint(reader, 1); if !type_ok { return nil, false }
		blob, blob_ok := krunker_msgpack_read_blob(reader, length); if !blob_ok { return nil, false }
		return Krunker_Msgpack_Ext{i8(type_id), blob}, true
	case:
		reader.error = "reserved or unsupported MessagePack tag"
		return nil, false
	}
}

// A frame may contain multiple concatenated opcode arrays. Every decoded root
// must have a nonempty string or integer opcode (ADD_PLAYERS is integer 0).
krunker_msgpack_decode_packet_with_allocator :: proc(packet: []byte, allocator: mem.Allocator) -> (messages: []Krunker_Msgpack_Value, counter: u8, error: string) {
	decoded_counter, body, trailer_ok := krunker_msgpack_decode_trailer(packet)
	if !trailer_ok { return nil, 0, "invalid or missing two-byte nibble trailer" }
	if len(body) > KRUNKER_MSGPACK_MAX_BYTES { return nil, 0, "MessagePack frame exceeds 16 MiB limit" }
	reader := Krunker_Msgpack_Reader{data = body, values_left = KRUNKER_MSGPACK_MAX_VALUES, allocator = allocator}
	decoded := make([dynamic]Krunker_Msgpack_Value, 0, allocator)
	for reader.pos < len(body) {
		value, ok := krunker_msgpack_read_value(&reader, 0)
		if !ok { return nil, decoded_counter, reader.error }
		array, array_ok := value.([]Krunker_Msgpack_Value)
		if !array_ok || len(array) == 0 { return nil, decoded_counter, "MessagePack root is not a nonempty opcode array" }
		opcode, opcode_ok := array[0].(string)
		_, numeric_opcode := array[0].(i64)
		if !(opcode_ok && len(opcode) > 0) && !numeric_opcode { return nil, decoded_counter, "MessagePack opcode is not a nonempty string or integer" }
		append(&decoded, value)
	}
	if len(decoded) == 0 { return nil, decoded_counter, "MessagePack body contains no messages" }
	return decoded[:], decoded_counter, ""
}

// Uses the caller's temporary allocator by default. Use the explicit variant
// when decoded values need to outlive the current frame.
krunker_msgpack_decode_packet :: proc(packet: []byte) -> (messages: []Krunker_Msgpack_Value, counter: u8, error: string) {
	return krunker_msgpack_decode_packet_with_allocator(packet, context.temp_allocator)
}
