package main
import "core:fmt"
import "lib"

GET_START :: "GET "
HTTP_END :: "\r\n\r\n"

/*
get_http :: proc() {
	server := connect_to_tcp_server()
	send_http_request(server)
	sb: strings.Builder
	buffer: [4096]byte
	for server.open {
		receive_data(buffer)
		response := strings.to_string(sb)
		if is_end_of_http_request(response) {return response}
	}
	return ""
}
*/
serve_http :: proc(server: ^lib.Server, event: ^lib.IoringEvent) {
	client := lib.handle_socket_event(server, event)
	switch client.state {
	case .New:
		// start reading data
		client.state = .Reading
		lib.receive_client_data_async(client)
		// accept another connection
		lib.accept_client_async(server)
	case .Reading:
		request := transmute(string)(client.async_rw_buffer[:client.async_rw_pos])
		// send response if valid request
		if len(request) >= len(GET_START) {
			if !lib.starts_with(request, GET_START) {
				lib.cancel_io_and_close_client(client)
			} else if lib.ends_with(request, HTTP_END) {
				// handle request
				// TODO: handle favicons or whatever?
				file_path := "index.html"
				file_size, ok := lib.open_file_for_response(client, file_path)
				fmt.assertf(ok, "Failed to open file: '%v'", file_path)
				// write http headers
				content_type := "text/html"
				header := fmt.tprintf(
					"HTTP/1.1 200 OK\r\nContent-Length: %v\r\nContent-Type: %v\r\nConnection: close\r\n\r\n",
					file_size,
					content_type,
				)
				lib.send_file_response_and_close_client(client, transmute([]byte)(header))
				return
			}
		}
		// else wait for more data
		lib.receive_client_data_async(client)
	case .SendingFileResponseAndClosing:
	/* NOTE: handled by OS */
	case .ClosedByClient, .ClosedByTimeout, .ClosedByServerResponse, .ClosedByServer:
		lib.close_client(client)
	}

	if client.state == .ClosedByServer {
		if client.async_write_file != nil {lib.close_file(client.async_write_file)}
		free(client)
	}
}
