// odin run jsbundler
// odin build jsbundler -o:speed
/* TODO: parse args
	- jsbundler version // print version
	- jsbundler help    // print this
	- jsbundler init    // overwrite src/jsgui folder with bundled version
	- jsbundler build   // build
	- jsbundler [port]  // build and watch for file changes
*/
package main
import "core:fmt"
import "core:strings"
import "core:text/regex" // NOTE: this adds 19 KiB to the exe size
import "path"
// NOTE: odin adds 250 KiB to exe size, just for RTTI - we need a better language?

main :: proc() {
	WalkData :: struct {
		css_texts: [dynamic]string,
		js_texts:  [dynamic]string,
	}
	walk_data: WalkData
	walk_proc :: proc(next_path: string, user_data: rawptr) {
		walk_data := (^WalkData)(user_data)
		if strings.ends_with(next_path, ".js") || strings.ends_with(next_path, ".mjs") {
			file_text, ok := path.read_entire_file(next_path)
			fmt.assertf(ok, "Failed to read file '%v'", next_path)
			append(&walk_data.js_texts, string(file_text))
		} else if (strings.ends_with(next_path, ".css")) {
			file_text, ok := path.read_entire_file(next_path)
			fmt.assertf(ok, "Failed to read file '%v'", next_path)
			append(&walk_data.css_texts, string(file_text))
		}
	}
	path.walk_files("src", walk_proc, &walk_data)

	index_file, ok := path.open_file_for_writing_and_truncate("index.html")
	assert(ok, "Failed to open file 'index.html'")
	path.write(index_file, "<!DOCTYPE html>\n<head>\n<style>\n")
	for css_text in walk_data.css_texts {
		path.write(index_file, css_text)
	}
	path.write(index_file, "</style>\n<script>\n")
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
			if i < j {path.write(index_file, js_text[i:j])}

			i = match.pos[0][1]
			for i < len(js_text) && (js_text[i] == '\r' || js_text[i] == '\n') {
				i += 1
			}

			match, index, ok = regex.match_iterator(&iterator)
		}
		path.write(index_file, js_text[i:])
	}
	path.write(index_file, "</script>")
}
