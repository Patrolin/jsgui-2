package lib
import "base:runtime"
import "core:fmt"
import "core:strings"
import win "core:sys/windows"

// types
FileHandle :: win.HANDLE

// helper procs
_wstring_to_string :: proc(wstr: win.wstring, allocator := context.temp_allocator) -> string {
	res, err := win.wstring_to_utf8_alloc(wstr, -1, allocator = allocator)
	assert(err == nil)
	return res
}
_string_to_wstring :: proc(str: string, allocator := context.temp_allocator) -> win.wstring {
	return win.utf8_to_wstring(str, allocator = allocator)
}

// procs
walk_files :: proc(dir_path: string, callback: proc(path: string, data: rawptr), data: rawptr) {
	path_to_search := fmt.tprint(dir_path, "*", sep = "\\")
	wpath_to_search := _string_to_wstring(path_to_search)
	find_result: win.WIN32_FIND_DATAW
	find := win.FindFirstFileW(wpath_to_search, &find_result)
	if find != win.INVALID_HANDLE_VALUE {
		for {
			relative_path := _wstring_to_string(&find_result.cFileName[0])
			if relative_path != "." && relative_path != ".." {
				is_dir :=
					(find_result.dwFileAttributes & win.FILE_ATTRIBUTE_DIRECTORY) ==
					win.FILE_ATTRIBUTE_DIRECTORY
				next_path := fmt.tprint(dir_path, relative_path, sep = "/")
				if is_dir {
					walk_files(next_path, callback, data)
				} else {
					callback(next_path, data)
				}
			}
			if win.FindNextFileW(find, &find_result) == false {break}
		}
		win.FindClose(find)
	}
}
read_entire_file :: proc(file_path: string) -> (text: string, ok: bool) {
	file := win.CreateFileW(
		_string_to_wstring(file_path),
		win.GENERIC_READ,
		0,
		nil,
		win.OPEN_EXISTING,
		0,
		nil,
	)
	ok = file != nil
	if ok {
		sb := strings.builder_make_none()
		buffer: [4096]u8
		bytes_read: u32
		for {
			win.ReadFile(file, &buffer, len(buffer), &bytes_read, nil)
			if bytes_read == 0 {break}
			fmt.sbprint(&sb, transmute(string)(buffer[:bytes_read]))
		}
		win.CloseHandle(file)
		text = strings.to_string(sb)
	}
	return
}
open_file_for_writing_and_truncate :: proc(file_path: string) -> (file: FileHandle, ok: bool) {
	file = win.CreateFileW(
		_string_to_wstring(file_path),
		win.GENERIC_WRITE,
		0,
		nil,
		win.TRUNCATE_EXISTING,
		win.FILE_ATTRIBUTE_NORMAL,
		nil,
	)
	ok = file != nil
	return
}
write :: proc(file: FileHandle, text: string) {
	assert(len(text) < int(max(u32)))
	win.WriteFile(file, raw_data(text), u32(len(text)), nil, nil)
}
