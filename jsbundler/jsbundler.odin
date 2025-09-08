// odin run jsbundler
// odin build jsbundler -o:speed
// TODO: rewrite this with my own apis, so that it's not a 507 KB executable...
package main
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:text/regex"

write :: proc(fd: os.Handle, text: string) {
	os.write(fd, transmute([]u8)(text))
}
main :: proc() {
	WalkData :: struct {
		css_texts: [dynamic]string,
		js_texts:  [dynamic]string,
	}
	walk_data: WalkData
	walk_proc :: proc(
		info: os.File_Info,
		in_err: os.Error,
		user_data: rawptr,
	) -> (
		err: os.Error,
		skip_dir: bool,
	) {
		if info.is_dir {return nil, false}
		walk_data := (^WalkData)(user_data)
		if strings.ends_with(info.name, ".js") || strings.ends_with(info.name, ".mjs") {
			file_text, ok := os.read_entire_file(info.fullpath)
			fmt.assertf(ok, "Failed to read file '%v'", info.fullpath)
			append(&walk_data.js_texts, string(file_text))
		} else if (strings.ends_with(info.name, ".css")) {
			file_text, ok := os.read_entire_file(info.fullpath)
			fmt.assertf(ok, "Failed to read file '%v'", info.fullpath)
			append(&walk_data.css_texts, string(file_text))
		}
		return
	}
	filepath.walk("src", walk_proc, &walk_data)

	index_file, err := os.open("index.html", os.O_CREATE | os.O_TRUNC | os.O_WRONLY, 0o744)
	assert(err == nil, "Failed to open file 'index.html'")
	write(index_file, "<!DOCTYPE html>\n<head>\n<style>\n")
	for css_text in walk_data.css_texts {
		write(index_file, css_text)
	}
	write(index_file, "</style>\n<script>\n")
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
			if i < j {write(index_file, js_text[i:j])}

			i = match.pos[0][1]
			for i < len(js_text) && (js_text[i] == '\r' || js_text[i] == '\n') {
				i += 1
			}

			match, index, ok = regex.match_iterator(&iterator)
		}
		write(index_file, js_text[i:])
	}
	write(index_file, "</script>")
}
