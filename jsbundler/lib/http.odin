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

		if client.state == .Reading {
			request := transmute(string)(client.async_rw_buffer[:client.async_rw_pos])
			if len(request) < len(GET_START) {continue}
			if !strings.starts_with(request, GET_START) {
				cancel_io_and_close_client(client)
			} else if strings.ends_with(request, HTTP_END) {
				// TODO: handle favicons or whatever?
				file_path := "index.html"
				file, file_size, ok := open_file_for_response(client, file_path)
				fmt.assertf(ok, "Failed to open file: '%v'", file_path)
				// write http headers
				content_type := "text/html"
				header := fmt.tprintf(
					"HTTP/1.1 200 OK\r\nContent-Length: %v\r\nContent-Type: %v\r\nConnection: close\r\n\r\n",
					file_size,
					content_type,
				)
				send_file_response_and_close_client(client, transmute([]byte)(header))
			}
		}
	}
}
