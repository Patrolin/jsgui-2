package main
import "base:runtime"
import "core:fmt"
import "lib"

// constants
GET_START :: "GET "
HTTP_END :: "\r\n\r\n"

// procs
serve_http_proc :: proc "system" (data: rawptr) -> u32 {
	context = runtime.default_context()
	when ODIN_DEFAULT_TO_NIL_ALLOCATOR {
		context.allocator = shared_allocator
		temp_buffer := lib.page_reserve(lib.GibiByte)
		arena_allocator: lib.ArenaAllocator
		context.temp_allocator = lib.arena_allocator(&arena_allocator, temp_buffer)
	}

	server := (^lib.Server)(data)
	for {
		free_all(context.temp_allocator)
		client := lib.wait_for_next_socket_event(server)
		defer lib.handle_socket_event(server, client)

		if client.state == .Reading {
			request := transmute(string)(client.async_rw_buffer[:client.async_rw_pos])
			if len(request) < len(GET_START) {continue}
			if !lib.starts_with(request, GET_START) {
				lib.cancel_io_and_close_client(client)
			} else if lib.ends_with(request, HTTP_END) {
				// TODO: handle favicons or whatever?
				file_path := "index.html"
				file, file_size, ok := lib.open_file_for_response(client, file_path)
				fmt.assertf(ok, "Failed to open file: '%v'", file_path)
				// write http headers
				content_type := "text/html"
				header := fmt.tprintf(
					"HTTP/1.1 200 OK\r\nContent-Length: %v\r\nContent-Type: %v\r\nConnection: close\r\n\r\n",
					file_size,
					content_type,
				)
				lib.send_file_response_and_close_client(client, transmute([]byte)(header))
			}
		}
	}
}
