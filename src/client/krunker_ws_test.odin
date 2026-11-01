package main

import "core:strings"
import "core:testing"
import kproto "../krunker"
import shared "../shared"

when ODIN_TEST {
	@(test)
	krunker_server_disconnect_diagnostics :: proc(t: ^testing.T) {
		client: Client
		defer delete(client.join_status)
		defer krunker_ws_disconnect(&client.krunker)
		// A reason can arrive long after the initial packet trace is suppressed.
		client.krunker.connected = true
		client.krunker.rx_logged = 400
		packet, ok := kproto.krunker_msgpack_encode_packet("dc", []kproto.Krunker_Msgpack_Value{"Disconnected due to inactivity", i64(123), "inactivity"}, 0)
		if !testing.expect(t, ok) do return
		defer delete(packet)
		krunker_ws_apply_world(&client, packet)
		testing.expect(t, !client.krunker.connected, "server dc must stop the connection")
		testing.expect(t, strings.contains(client.join_status, "Disconnected due to inactivity"), "server reason must reach the status display")

		client.krunker.connected = true
		error_packet, error_ok := kproto.krunker_msgpack_encode_packet("error", []kproto.Krunker_Msgpack_Value{"Fixture server error"}, 0)
		if !testing.expect(t, error_ok) do return
		defer delete(error_packet)
		krunker_ws_apply_world(&client, error_packet)
		testing.expect(t, client.krunker.connected, "an error message alone does not imply a socket close")
		testing.expect(t, strings.contains(client.join_status, "Fixture server error"), "server errors must remain visible after the initial trace")
		testing.expect(t, client.krunker.server_error == "Fixture server error", "socket close must retain the server's error")
	}

	@(test)
	krunker_outgoing_counter_parity :: proc(t: ^testing.T) {
		// Independent reference: the Rust hoster emits (x,y) before updating
		// y by 5 and x by 2 plus its carry. Exercise multiple complete cycles,
		// interleaving control packets, bootstrap q and the live q encoder.
		x, y: u8 = 2, 5
		counter: u8
		for index in 0 ..< 600 {
			expected := (x << 4) | y
			opcodes := [?]string{"load", "po", "team", "class", "en", "q", "v"}
			opcode := opcodes[index % len(opcodes)]
			packet: []byte
			if index % 2 == 0 {
				counter = kproto.krunker_msgpack_counter_next(counter, "q")
				input := shared.Input{seq = i32(index), move_dir = -1}
				encoded, ok := kproto.krunker_input_encode(&input, 34, counter, false)
				if !testing.expect(t, ok) do return
				packet = encoded
			} else {
				encoded := krunker_ws_message(opcode, &counter, 0)
				packet = encoded[:]
			}
			decoded, _, ok := kproto.krunker_msgpack_decode_trailer(packet)
			testing.expect(t, ok && decoded == expected && counter == expected, "all send paths must follow the reference hoster's counter, including wraps")
			delete(packet)
			testing.expect(t, kproto.krunker_msgpack_counter_next(counter, "cptR") == counter, "CAPTCHA replies preserve the current counter")
			x = (x + (y + 5 >= 16 ? 3 : 2)) & 15
			y = (y + 5) & 15
		}
	}
}
