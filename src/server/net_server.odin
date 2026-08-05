package server_main

import "core:fmt"
import "core:net"
import shared "../shared"

Net_Client :: struct {
	id:         u32,
	socket:     net.TCP_Socket,
	active:     bool,
	last_input: shared.Packet_Player_Input,
}

Net_Server :: struct {
	listener: net.TCP_Socket,
	clients:  [dynamic]^Net_Client,
	next_id:  u32,
}

net_server_init :: proc(port: int) -> (ns: Net_Server, ok: bool) {
	endpoint := net.Endpoint {
		address = net.IP4_Any,
		port    = port,
	}

	listener, err := net.listen_tcp(endpoint)
	if err != nil {
		fmt.eprintf("Failed to listen on port %d: %v\n", port, err)
		return ns, false
	}

	ns.listener = listener
	ns.next_id = 1
	fmt.printf("Odin TCP Socket Server listening on 0.0.0.0:%d\n", port)
	return ns, true
}

net_server_poll :: proc(ns: ^Net_Server) {
	// Poll for new client connections (non-blocking accept check)
	net.set_blocking(ns.listener, false)
	client_socket, _, err := net.accept_tcp(ns.listener)
	if err == nil {
		net.set_blocking(client_socket, false)

		client := new(Net_Client)
		client.id = ns.next_id
		ns.next_id += 1
		client.socket = client_socket
		client.active = true

		append(&ns.clients, client)
		fmt.printf("[Net Server] Client #%d connected!\n", client.id)
	}

	// Poll incoming data for each client
	buf: [1024]byte
	for client in ns.clients {
		if !client.active {
			continue
		}

		bytes_read, read_err := net.recv_tcp(client.socket, buf[:])
		if read_err == nil && bytes_read > 0 {
			header, h_ok := shared.packet_deserialize_header(buf[:bytes_read])
			if h_ok {
				#partial switch header.packet_type {
				case .PLAYER_INPUT:
					// Input packet received
				case .DISCONNECT:
					client.active = false
					fmt.printf("[Net Server] Client #%d requested disconnect\n", client.id)
				}
			}
		}
	}
}

net_server_close :: proc(ns: ^Net_Server) {
	for client in ns.clients {
		if client.active {
			net.close(client.socket)
		}
		free(client)
	}
	delete(ns.clients)
	net.close(ns.listener)
}
