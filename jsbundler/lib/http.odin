package lib
import "core:fmt"
import "core:strings"

// constants
HTTP_END :: "\r\n\r\n"

// procs
serve_http_proc :: proc(data: rawptr) {
	// once per process
	init_sockets()
	server: Server
	// once per thread
	port := (^u16)(data)^
	create_server_socket(&server, port)
	for {
		free_all(context.temp_allocator)
		client := wait_for_next_socket_event(&server)
		defer handle_socket_event(&server, client)

		buf := transmute(string)(client.async_read_buffer[:min(client.async_read_pos, 8)])
		fmt.printfln("client: %v", client)
		fmt.printfln("received: '%v'", buf)

		// TODO: async writes?

		/*
		sb := strings.builder_make_none(allocator = context.temp_allocator)
		read_http_block(client, &sb)
		headers_string := strings.to_string(sb)

		fmt.printfln("\nheaders_string: '%v'", headers_string)
		response := "HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\nHello, world!"
		send_to_client_socket(client, transmute([]byte)(response))
		close_client_socket(client)
		*/
	}
}
