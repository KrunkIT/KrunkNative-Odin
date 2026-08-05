package main

import "core:fmt"
import "core:net"
import shared "../shared"

Net_Client_State :: struct {
	socket:    net.TCP_Socket,
	connected: bool,
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
		net.send_tcp(nc.socket, buf[:n])
	}
}

net_client_poll :: proc(nc: ^Net_Client_State) {
	if !nc.connected {
		return
	}

	buf: [1024]byte
	bytes_read, err := net.recv_tcp(nc.socket, buf[:])
	if err != nil && bytes_read == 0 {
		return
	}

	if bytes_read > 0 {
		header, h_ok := shared.packet_deserialize_header(buf[:bytes_read])
		if h_ok {
			#partial switch header.packet_type {
			case .GAME_STATE:
				// Process server state tick
			}
		}
	}
}

net_client_disconnect :: proc(nc: ^Net_Client_State) {
	if nc.connected {
		net.close(nc.socket)
		nc.connected = false
	}
}
