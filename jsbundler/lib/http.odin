package lib
import "core:fmt"
import "core:strings"

// constants
GET_START :: "GET "
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

		if client.state == .Open {
			request := transmute(string)(client.async_read_buffer[:client.async_read_pos])
			if len(request) < len(GET_START) {continue}
			if !strings.starts_with(request, GET_START) {
				cancel_io_and_close_client(client)
			} else if strings.ends_with(request, HTTP_END) {
				response := "HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\nHello, world!"
				send_response_and_close_client(client, transmute([]byte)(response))
			}
		}
	}
}
