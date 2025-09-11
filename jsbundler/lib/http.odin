package lib
import "core:fmt"
import "core:strings"

// constants
HTTP_END :: "\r\n\r\n"

// procs
read_http_block :: proc(client: BoundSocket, sb: ^strings.Builder) -> (ok: bool) {
	i := 0
	for wait_for_client_socket_data(client, sb) {
		full_message := strings.to_string(sb^)
		new_part := full_message[i:]
		i = len(full_message)
		end_of_message := full_message[max(0, len(full_message) - 4):]
		if strings.ends_with(full_message, HTTP_END) {break}
	}
	return true
}
serve_http_proc :: proc(data: rawptr) {
	port := (^u16)(data)^
	init_sockets()
	server := create_server_socket(port)
	for {
		free_all(context.temp_allocator)
		client := wait_for_next_client_socket(server)

		sb := strings.builder_make_none(allocator = context.temp_allocator)
		read_http_block(client, &sb)
		headers_string := strings.to_string(sb)

		fmt.printfln("\nheaders_string: '%v'", headers_string)
		response := "HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\nHello, world!"
		send_to_client_socket(client, transmute([]byte)(response))
		close_client_socket(client)
	}
}
