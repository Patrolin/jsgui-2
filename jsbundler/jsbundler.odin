// odin run jsbundler
// odin build jsbundler -default-to-nil-allocator -o:speed
/* NOTE: odin adds 250 KiB to exe size, just for RTTI - we need a better language? */
package main
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:strconv"
import "lib"

// globals
serve_enabled := true
serve_port: u16 = 3000
serve_thread_count := 1

// constants
SRC_PATH :: "src" /* NOTE: FILES_TO_INIT needs hardcoded paths.. */
JSGUI_VERSION :: #load("../src/jsgui/jsgui_version.txt", string)
FileToInit :: struct {
	path: string,
	/* if data == "" {Create a directory} else {Create a file} */
	data: string,
}
FILES_TO_INIT :: []FileToInit {
	{"src", ""},
	{"src/jsgui", ""},
	{"src/jsgui/jsgui_version.txt", JSGUI_VERSION},
	{"src/jsgui/jsgui.css", #load("../src/jsgui/jsgui.css")},
	{"src/jsgui/jsgui.mjs", #load("../src/jsgui/jsgui.mjs")},
	{"src/jsgui/types", ""},
	{"src/jsgui/types/jsgui_types.d.js", #load("../src/jsgui/types/jsgui_types.d.js")},
}

print_help_and_exit :: proc() {
	fmt.printfln(
		"  jsbundler [port]  - serve at [port=%v] and rebuild when files change",
		serve_port,
	)
	fmt.println("  jsbundler build   - build and exit")
	fmt.println("  jsbundler help    - print this")
	fmt.println("  jsbundler version - print the version number")
	fmt.println("  jsbundler init    - copy the bundled jsgui version into src/jsgui")
	lib.exit_process()
}
shared_allocator: mem.Allocator
main :: proc() {
	// setup allocators
	when ODIN_DEFAULT_TO_NIL_ALLOCATOR {
		lib.init_page_fault_handler()
		shared_buffer := lib.page_reserve(lib.GibiByte)
		when true {
			half_fit: lib.HalfFitAllocator
			shared_allocator = lib.half_fit_allocator(&half_fit, shared_buffer)
		} else {
			shared_arena: lib.ArenaAllocator
			shared_allocator = lib.arena_allocator(&shared_arena, shared_buffer)
		}
		context.allocator = shared_allocator

		temp_buffer := lib.page_reserve(lib.GibiByte)
		temp_arena_allocator: lib.ArenaAllocator
		context.temp_allocator = lib.arena_allocator(&temp_arena_allocator, temp_buffer)
	}

	args := lib.get_args()
	if len(args) > 1 {
		second_arg := args[1]
		if second_arg == "help" || len(args) > 2 {
			fmt.printfln("v%v:", JSGUI_VERSION[:len(JSGUI_VERSION) - 1])
			print_help_and_exit()
		} else if second_arg == "version" {
			fmt.printfln("v%v", JSGUI_VERSION[:len(JSGUI_VERSION) - 1])
			lib.exit_process()
		} else if second_arg == "init" {
			for file_to_init in FILES_TO_INIT {
				if file_to_init.data == "" {
					lib.create_dir_if_not_exists(file_to_init.path)
				} else {
					fmt.printfln("+ %v", file_to_init.path)
					lib.write_file_atomically(file_to_init.path, file_to_init.data)
				}
			}
			lib.exit_process()
		} else if second_arg == "build" {
			serve_enabled = false
		} else {
			new_port, ok := strconv.parse_uint(second_arg, 10, nil)
			if !ok || new_port > uint(max(u16)) {
				print_help_and_exit()
			}
			serve_port = u16(new_port)
		}
	}

	if serve_enabled {
		ioring := lib.ioring_create()
		watched_dir := lib.WatchedDir {
			path = SRC_PATH,
		}
		lib.ioring_open_dir_for_watching(ioring, &watched_dir)
		lib.ioring_watch_file_changes_async(ioring, &watched_dir)

		server := lib.Server {
			ioring    = ioring,
			user_data = &watched_dir,
		}
		lib.init_sockets()
		lib.create_server_socket(&server, serve_port)
		fmt.printfln("- Serving on http://localhost:%v/", serve_port)
		for i in 0 ..< serve_thread_count - 1 {
			// nocheckin lib.start_thread(serve_http_or_rebuild_proc, &server)
		}
		rebuild_index_file()
		serve_http_or_rebuild(&server)
	} else {
		rebuild_index_file()
	}
}
serve_http_or_rebuild_proc :: proc "system" (server: ^lib.Server) {
	context = runtime.default_context()
	when ODIN_DEFAULT_TO_NIL_ALLOCATOR {
		context.allocator = shared_allocator
		temp_buffer := lib.page_reserve(lib.GibiByte)
		arena_allocator: lib.ArenaAllocator
		context.temp_allocator = lib.arena_allocator(&arena_allocator, temp_buffer)
	}
	serve_http_or_rebuild(server)
}
serve_http_or_rebuild :: proc(server: ^lib.Server) {
	watched_dir := (^lib.WatchedDir)(server.user_data)

	lib.accept_client_async(server)
	for {
		free_all(context.temp_allocator)
		event: lib.IoringEvent = ---
		lib.ioring_wait_for_next_event(server.ioring, &event)

		is_dir_event := rawptr(event.overlapped) == watched_dir
		//fmt.printfln("is_dir_event: %v, event: %v", is_dir_event, event)
		if is_dir_event {
			lib.wait_for_writes_to_finish(watched_dir)
			rebuild_index_file()
		} else {
			serve_http(server, &event)
		}
	}
}
rebuild_index_file :: proc() {
	fmt.print("\r- Rebuilding...")
	WalkData :: struct {
		css_texts: [dynamic]string,
		js_texts:  [dynamic]string,
	}
	walk_data: WalkData
	walk_proc :: proc(next_path: string, user_data: rawptr) {
		walk_data := (^WalkData)(user_data)
		extension_index := lib.last_index_ascii_char(next_path, '.')
		extension := next_path[extension_index:]
		if extension == ".js" || extension == ".mjs" {
			file_text, ok := lib.read_file(next_path)
			fmt.assertf(ok, "Failed to read file '%v'", next_path)
			append(&walk_data.js_texts, string(file_text))
		} else if extension == ".css" {
			file_text, ok := lib.read_file(next_path)
			fmt.assertf(ok, "Failed to read file '%v'", next_path)
			append(&walk_data.css_texts, string(file_text))
		}
	}
	lib.walk_files(SRC_PATH, walk_proc, &walk_data)

	index_file, ok := lib.open_file_for_writing_and_truncate("index.html")
	assert(ok, "Failed to open file 'index.html'")
	lib.write_to_file(index_file, "<!DOCTYPE html>\n<head>\n<style>\n")
	for css_text in walk_data.css_texts {
		lib.write_to_file(index_file, css_text)
	}
	lib.write_to_file(index_file, "</style>\n<script>\n")
	for js_text in walk_data.js_texts {
		// skip starting whitespace
		i := lib.index_ignore_newlines(js_text, 0)
		for i < len(js_text) {
			// find next pattern
			middle, end, k := lib.index_multi_after(js_text, i, "/**", "import ", "export ")
			lib.write_to_file(index_file, js_text[i:middle])
			// handle the pattern
			if middle < len(js_text) {
				switch k {
				case 0:
					end = lib.index_after(js_text, end, "*/")
					end = lib.index_ignore_newlines(js_text, end)
				case 1:
					end = lib.index_after(js_text, end, " from ")
					end = lib.index_ascii(js_text, end, "\r\n")
					end = lib.index_ignore_newlines(js_text, end)
				case 2:
				}
			}
			fmt.assertf(end > i, "end: %v, i: %v", end, i)
			i = end
		}
	}
	lib.write_to_file(index_file, "</script>")
	lib.close_file(index_file)
	fmt.printf("\r- Bundled into index.html")
}
