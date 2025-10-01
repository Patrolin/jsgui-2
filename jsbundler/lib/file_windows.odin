package lib
import "core:fmt"

// file procs
create_dir_if_not_exists :: proc(dir_path: string) -> (ok: bool) {
	CreateDirectoryW(&tprint_string_as_wstring(dir_path)[0], nil)
	err := GetLastError()
	return err != ERROR_PATH_NOT_FOUND
}
move_path_atomically :: proc(src_path, dest_path: string) {
	result := MoveFileExW(
		&tprint_string_as_wstring(src_path)[0],
		&tprint_string_as_wstring(dest_path)[0],
		MOVEFILE_REPLACE_EXISTING,
	)
	fmt.assertf(bool(result), "Failed to move path: '%v' to '%v'", src_path, dest_path)
}
/* NOTE: We only support up to `wlen(dir) + 1 + wlen(relative_file_path) < MAX_PATH (259 utf16 chars + null terminator)`. \
	While we *can* give windows long paths as input, it has no way to return long paths back to us. \
	Windows gives us (somewhat) relative paths, so we could theoretically extend support to `wlen(relative_file_path) < MAX_PATH`. \
	But that doesn't really change much.
*/
walk_files :: proc(
	dir_path: string,
	callback: proc(path: string, data: rawptr),
	data: rawptr = nil,
) {
	path_to_search := fmt.tprint(dir_path, "*", sep = "\\")
	wpath_to_search := tprint_string_as_wstring(path_to_search)
	find_result: WIN32_FIND_DATAW
	find := FindFirstFileW(&wpath_to_search[0], &find_result)
	if find != FindFile(INVALID_HANDLE) {
		for {
			relative_wpath := &find_result.cFileName[0]
			relative_path := tprint_wstring(relative_wpath)
			assert(relative_path != "")
			if relative_path != "." && relative_path != ".." {
				is_dir :=
					(find_result.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ==
					FILE_ATTRIBUTE_DIRECTORY
				next_path := fmt.tprint(dir_path, relative_path, sep = "/")
				if is_dir {
					walk_files(next_path, callback, data)
				} else {
					callback(next_path, data)
				}
			}
			if FindNextFileW(find, &find_result) == false {break}
		}
		FindClose(find)
	}
}
read_file :: proc(file_path: string) -> (text: string, ok: bool) {
	wfile_path := tprint_string_as_wstring(file_path)
	file := CreateFileW(
		&wfile_path[0],
		GENERIC_READ,
		FILE_SHARE_READ | FILE_SHARE_WRITE,
		nil,
		F_OPEN,
		FILE_ATTRIBUTE_NORMAL,
		nil,
	)
	ok = file != INVALID_HANDLE
	if !ok {
		fmt.printfln("err: (%v)", GetLastError())
	}
	if ok {
		sb: StringBuilder
		buffer: [4096]u8 = ---
		bytes_read: u32
		for {
			ReadFile(FileHandle(file), &buffer[0], len(buffer), &bytes_read, nil)
			if bytes_read == 0 {break}
			fmt.sbprint(&sb, string(buffer[:bytes_read]))
		}
		CloseHandle(file)
		text = to_string(sb)
	}
	return
}
open_file_for_writing_and_truncate :: proc(file_path: string) -> (file: FileHandle, ok: bool) {
	file = FileHandle(
		CreateFileW(
			&tprint_string_as_wstring(file_path)[0],
			GENERIC_WRITE,
			FILE_SHARE_READ,
			nil,
			F_CREATE_OR_OPEN_AND_TRUNCATE,
			FILE_ATTRIBUTE_NORMAL,
			nil,
		),
	)
	ok = file != FileHandle(INVALID_HANDLE)
	return
}
write_to_file :: proc(file: FileHandle, text: string) {
	assert(len(text) < int(max(u32)))
	bytes_written: DWORD
	WriteFile(file, raw_data(text), u32(len(text)), &bytes_written, nil)
	assert(int(bytes_written) == len(text))
}
flush_file :: proc(file: FileHandle) {
	FlushFileBuffers(file)
}
close_file :: proc(file: FileHandle) {
	CloseHandle(HANDLE(file))
}
