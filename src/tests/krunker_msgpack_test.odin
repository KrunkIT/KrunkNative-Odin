package main

import "core:fmt"
import krunker "../krunker"

test_krunker_msgpack :: proc() -> bool {
	packet, ok := krunker.krunker_msgpack_encode_packet("load", nil, 3)
	if !ok { fmt.eprintln("Krunker MessagePack load encoding failed"); return false }
	defer delete(packet)
	expected := []byte{0x91, 0xa4, 'l', 'o', 'a', 'd', 0x00, 0x03}
	if len(packet) != len(expected) {
		fmt.eprintln("Krunker MessagePack load packet length mismatch")
		return false
	}
	for value, i in packet { if value != expected[i] { fmt.eprintln("Krunker MessagePack load packet bytes mismatch"); return false } }
	if krunker.krunker_msgpack_counter_next(0, "load") != 37 || krunker.krunker_msgpack_counter_next(37, "cptR") != 37 {
		fmt.eprintln("Krunker trailer counter rule mismatch")
		return false
	}
	opcode, counter, peek_ok := krunker.krunker_msgpack_peek_opcode(packet)
	if !peek_ok || opcode != "load" || counter != 3 {
		fmt.eprintln("Krunker opcode/trailer peek failed")
		return false
	}
	messages, decoded_counter, error_text := krunker.krunker_msgpack_decode_packet(packet)
	if len(messages) != 1 || decoded_counter != 3 || len(error_text) != 0 {
		fmt.printf("Krunker MessagePack decode failed: %s\n", error_text)
		return false
	}
	fmt.println("Krunker MessagePack tests OK")
	return true
}
