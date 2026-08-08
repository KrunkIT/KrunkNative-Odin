package main

import "core:fmt"
import "core:net"
import shared "../shared"

Net_Client_State :: struct {
	socket:    net.TCP_Socket,
	connected: bool,
	recv_buffer: [4096]byte,
	recv_len: int,
	match_state_received: bool,
	send_queue: shared.Net_Send_Queue,
}

net_client_flush :: proc(nc: ^Net_Client_State) -> bool {
	if !nc.connected {
		return false
	}

	for {
		pending := shared.net_send_queue_pending(&nc.send_queue)
		if len(pending) == 0 {
			return true
		}

		count, err := net.send_tcp(nc.socket, pending)
		shared.net_send_queue_consume(&nc.send_queue, count)

		if err != nil {
			if err == .Would_Block || err == .Timeout {
				return true
			}
			return false
		}
		if count == 0 {
			return false
		}
	}
}

net_client_send :: proc(nc: ^Net_Client_State, data: []byte) -> bool {
	if !nc.connected || len(data) == 0 {
		return false
	}
	if !shared.net_send_queue_push(&nc.send_queue, data) {
		fmt.eprintf("[Net Client] Send queue overflow; disconnecting\n")
		return false
	}
	return net_client_flush(nc)
}

net_client_connect :: proc(host: string, port: int) -> (nc: Net_Client_State, ok: bool) {
	addr4 := net.IP4_Address{127, 0, 0, 1}
	endpoint := net.Endpoint {
		address = addr4,
		port    = port,
	}

	socket, err := net.dial_tcp(endpoint)
	if err != nil {
		fmt.printf("[Net Client] Offline mode (server at %s:%d not reachable)\n", host, port)
		return nc, false
	}

	net.set_blocking(socket, false)
	// Small snapshots must not wait on Nagle + delayed ACK (40 ms on Windows).
	net.set_option(socket, .TCP_Nodelay, true)
	nc.socket = socket
	nc.connected = true
	fmt.printf("[Net Client] Connected to Dedicated Server at %s:%d!\n", host, port)
	return nc, true
}

net_client_send_input :: proc(nc: ^Net_Client_State, input: ^shared.Input) {
	if !nc.connected {
		return
	}

	buf: [32]byte
	n := shared.packet_serialize_input(buf[:], input)
	if n > 0 {
		if !net_client_send(nc, buf[:n]) {
			nc.connected = false
		}
	}
}

net_client_send_spawn :: proc(nc: ^Net_Client_State, class_id: i32) {
	if !nc.connected {
		return
	}
	buf: [16]byte
	size := shared.packet_serialize_connect(buf[:], class_id)
	if size > 0 {
		if !net_client_send(nc, buf[:size]) {
			nc.connected = false
		}
	}
}

net_client_poll :: proc(client: ^Client) {
	nc := &client.net
	if !nc.connected {
		return
	}
	if !net_client_flush(nc) {
		fmt.printf("[Net Client] Send error\n")
		nc.connected = false
		return
	}

	bytes_read, err := net.recv_tcp(nc.socket, nc.recv_buffer[nc.recv_len:])

	if bytes_read > 0 {
		nc.recv_len += bytes_read
		for nc.recv_len >= shared.PACKET_HEADER_SIZE {
			header, h_ok := shared.packet_deserialize_header(nc.recv_buffer[:nc.recv_len])
			if !h_ok {
				nc.connected = false
				return
			}
			packet_size := shared.PACKET_HEADER_SIZE + int(header.payload_len)
			if packet_size > len(nc.recv_buffer) {
				nc.connected = false
				return
			}
			if nc.recv_len < packet_size {
				break
			}
			packet := nc.recv_buffer[:packet_size]
			#partial switch header.packet_type {
			case .GAME_STATE:
				if state, state_ok := shared.packet_deserialize_state(packet); state_ok {
					client_apply_player_state(client, &state)
				}
			case .MATCH_STATE:
				if state, state_ok := shared.packet_deserialize_match_state(packet); state_ok {
					client_apply_match_state(client, &state)
					nc.match_state_received = true
				}
			}
			nc.recv_len -= packet_size
			if nc.recv_len > 0 {
				copy(nc.recv_buffer[:nc.recv_len], nc.recv_buffer[packet_size:packet_size + nc.recv_len])
			}
		}
	} else if err == nil {
		// 0 bytes with no error is a graceful FIN from the server.
		fmt.printf("[Net Client] Server closed the connection\n")
		nc.connected = false
	} else if err != .Would_Block && err != .Timeout {
		fmt.printf("[Net Client] Connection error: %v\n", err)
		nc.connected = false
	}
}

net_client_disconnect :: proc(nc: ^Net_Client_State) {
	if nc.connected {
		buf: [shared.PACKET_HEADER_SIZE]byte
		if size := shared.packet_serialize_disconnect(buf[:]); size > 0 {
			net_client_send(nc, buf[:size])
		}
		net.close(nc.socket)
		nc.connected = false
	}
}
