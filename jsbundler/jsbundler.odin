// odin run jsbundler
// odin build jsbundler -o:speed
/* NOTE: odin adds 250 KiB to exe size, just for RTTI - we need a better language? */
package main
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:text/regex"
import "core:thread" // NOTE: this adds 19 KiB to the exe size
import "lib"

// constants
SRC_PATH :: "src"

// globals
serve_http := true
serve_port: u16 = 3000

print_help_and_exit :: proc() {
	fmt.println("  jsbundler help    - print this")
	fmt.println("  jsbundler version - print the version number")
	fmt.println("  jsbundler init    - copy the bundled jsgui into src/jsgui")
	fmt.printfln(
		"  jsbundler [port]  - serve at [port=%v] and rebuild when files change",
		serve_port,
	)
	fmt.println("  jsbundler build   - build and exit")
	lib.exit_process()
}
main :: proc() {
	args := lib.get_args()
	if len(args) > 1 {
		second_arg := args[1]
		if second_arg == "help" || len(args) > 2 {
			print_help_and_exit()
		} else if second_arg == "version" {
			fmt.printfln("version: 0.1")
			lib.exit_process()
		} else if second_arg == "init" {
			assert(false, "TODO: init jsgui")
			lib.exit_process()
		} else if second_arg == "build" {
			serve_http = false
		} else {
			new_port, ok := strconv.parse_uint(second_arg, 10, nil)
			if !ok || new_port > uint(max(u16)) {
				print_help_and_exit()
			}
			serve_port = u16(new_port)
		}
	}

	dir_for_watching: lib.WatchedDir
	if serve_http {
		fmt.printfln("- Serving on http://localhost:%v/", serve_port)
		thread.create_and_start_with_data(&serve_port, lib.serve_http_proc, nil, nil)
		dir_for_watching = lib.open_dir_for_watching(SRC_PATH)
	}
	for {
		rebuild_index_file()
		if !serve_http {return}
		free_all(context.temp_allocator)
		lib.wait_for_file_changes(&dir_for_watching)
	}
}
rebuild_index_file :: proc() {
	//fmt.print("\r- Rebuilding...")
	WalkData :: struct {
		css_texts: [dynamic]string,
		js_texts:  [dynamic]string,
	}
	walk_data: WalkData
	walk_proc :: proc(next_path: string, user_data: rawptr) {
		walk_data := (^WalkData)(user_data)
		extension_index := strings.last_index_byte(next_path, '.')
		extension := next_path[extension_index:]
		if extension == ".js" || extension == ".mjs" {
			file_text, ok := lib.read_entire_file(next_path)
			fmt.printfln("next_path: %v (%v)", next_path, len(file_text))
			fmt.assertf(ok, "Failed to read file '%v'", next_path)
			append(&walk_data.js_texts, string(file_text))
		} else if extension == ".css" {
			file_text, ok := lib.read_entire_file(next_path)
			fmt.assertf(ok, "Failed to read file '%v'", next_path)
			append(&walk_data.css_texts, string(file_text))
		}
	}
	lib.walk_files(SRC_PATH, walk_proc, &walk_data)

	index_file, ok := lib.open_file_for_writing_and_truncate("index.html")
	assert(ok, "Failed to open file 'index.html'")
	lib.write(index_file, "<!DOCTYPE html>\n<head>\n<style>\n")
	for css_text in walk_data.css_texts {
		lib.write(index_file, css_text)
	}
	lib.write(index_file, "</style>\n<script>\n")
	for js_text in walk_data.js_texts {
		i := 0
		for i < len(js_text) && (js_text[i] == '\r' || js_text[i] == '\n') {
			i += 1
		}
		ignore_regex := "/\\*\\*.*?\\*/|import .*? from .*?[\n$]|export "
		iterator, err := regex.create_iterator(js_text, ignore_regex, {.Multiline})
		assert(err == nil)
		match, index, ok := regex.match_iterator(&iterator)
		for ok {
			j := match.pos[0][0]
			if i < j {lib.write(index_file, js_text[i:j])}

			i = match.pos[0][1]
			for i < len(js_text) && (js_text[i] == '\r' || js_text[i] == '\n') {
				i += 1
			}

			match, index, ok = regex.match_iterator(&iterator)
		}
		lib.write(index_file, js_text[i:])
	}
	lib.write(index_file, "</script>")
	lib.close_file(index_file)
	//fmt.printf("\r- Bundled into index.html")
}
