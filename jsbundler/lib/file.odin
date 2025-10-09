package lib
import "base:runtime"
import "core:fmt"
import "core:strings"

create_dir_if_not_exists :: proc(dir_path: string) {
	when ODIN_OS == .Windows {
		CreateDirectoryW(&tprint_string_as_wstring(dir_path)[0], nil)
		err := GetLastError()
		ok := err != .ERROR_PATH_NOT_FOUND
	} else when ODIN_OS == .Linux {
		cbuffer: [WINDOWS_MAX_PATH]byte = ---
		cdir_path, _ := copy_to_cstring(dir_path, cbuffer[:])
		err := mkdir(cdir_path)
		fmt.printfln("err: %v", err)
		ok := err == 0 || Errno(err) == .EEXIST
	} else {
		assert(false)
	}
	fmt.assertf(ok, "Failed to create directory: '%v'", dir_path)
}
move_path_atomically :: proc(src_path, dest_path: string) {
	when ODIN_OS == .Windows {
		result := MoveFileExW(&tprint_string_as_wstring(src_path)[0], &tprint_string_as_wstring(dest_path)[0], {.MOVEFILE_REPLACE_EXISTING})
		fmt.assertf(bool(result), "Failed to move path: '%v' to '%v'", src_path, dest_path)
	} else when ODIN_OS == .Linux {
		cbuffer: [2 * WINDOWS_MAX_PATH]byte = ---
		csrc_path, cbuffer2 := copy_to_cstring(src_path, cbuffer[:])
		cdest_path, _ := copy_to_cstring(dest_path, cbuffer2)
		err := renameat2(AT_FDCWD, csrc_path, AT_FDCWD, cdest_path)
		fmt.assertf(err == 0, "Failed to move path: '%v' to '%v'", src_path, dest_path)
	} else {
		assert(false)
	}
}
/* NOTE: We only support up to `wlen(dir) + 1 + wlen(relative_file_path) < MAX_PATH (259 utf16 chars + null terminator)`. \
	While we *can* give windows long paths as input, it has no way to return long paths back to us. \
	Windows gives us (somewhat) relative paths, so we could theoretically extend support to `wlen(relative_file_path) < MAX_PATH`. \
	But that doesn't really change much.
*/
walk_files :: proc(dir_path: string, callback: proc(path: string, data: rawptr), data: rawptr = nil) {
	when ODIN_OS == .Windows {
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
					is_dir := find_result.dwFileAttributes >= {.FILE_ATTRIBUTE_DIRECTORY}
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
	} else when ODIN_OS == .Linux {
		cbuffer: [WINDOWS_MAX_PATH]byte = ---
		cdir_path, _ := copy_to_cstring(dir_path, cbuffer[:])
		dir := DirHandle(open(cdir_path, {.O_DIRECTORY}))
		if Errno(dir) == .ENOTDIR {
			callback(dir_path, data)
		} else {
			assert(dir >= 0)
			dir_entries_buffer: [4096]byte
			bytes_written := get_directory_entries_64b(dir, &dir_entries_buffer[0], len(dir_entries_buffer))
			assert(bytes_written >= 0)
			if bytes_written == 0 {return}

			offset := 0
			for offset < bytes_written {
				dirent := (^Dirent64)(&dir_entries_buffer[offset])
				crelative_path := transmute([^]byte)(&dirent.cfile_name)
				len_lower_bound := max(0, int(dirent.size) - 28)
				relative_path := string_from_cstring(crelative_path, len_lower_bound)

				if relative_path != "." && relative_path != ".." {
					is_dir := dirent.type == .Dir
					next_path := fmt.tprint(dir_path, relative_path, sep = "/")
					if is_dir {
						walk_files(next_path, callback, data)
					} else {
						callback(next_path, data)
					}
				}
				offset += int(dirent.size)
			}
		}
	} else {
		assert(false)
	}
}

// read
@(require_results)
open_file_for_reading :: proc(file_path: string) -> (file: FileHandle) {
	when ODIN_OS == .Windows {
		wfile_path := tprint_string_as_wstring(file_path)
		file = CreateFileW(
			&wfile_path[0],
			{.GENERIC_READ},
			{.FILE_SHARE_READ, .FILE_SHARE_WRITE},
			nil,
			.Open,
			{.FILE_ATTRIBUTE_NORMAL, .FILE_FLAG_SEQUENTIAL_SCAN},
		)
	} else when ODIN_OS == .Linux {
		cbuffer: [WINDOWS_MAX_PATH]byte = ---
		cfile_path, _ := copy_to_cstring(file_path, cbuffer[:])
		file = open(cfile_path)
		if file < 0 {file = FileHandle(INVALID_HANDLE)}
	} else {
		assert(false)
	}
	return
}
/* NOTE: this can fail if the file gets deleted or whatever */
@(require_results)
get_file_size :: proc(file: FileHandle) -> (file_size: int, ok: bool) {
	when ODIN_OS == .Windows {
		win_file_size: LARGE_INTEGER = ---
		ok = GetFileSizeEx(file, &win_file_size) == true
		file_size = int(win_file_size)
	} else when ODIN_OS == .Linux {
		file_info: Statx = ---
		err := get_file_info(file, {.STATX_SIZE}, &file_info)
		ok = err == 0
		file_size = int(file_info.size)
	} else {
		assert(false)
	}
	return
}
@(require_results)
read_file :: proc(file_path: string, allocator := context.temp_allocator) -> (text: string, ok: bool) #no_bounds_check {
	// open file
	file := open_file_for_reading(file_path)
	ok = file != FileHandle(INVALID_HANDLE)
	if ok {
		// read file
		sb := string_builder(allocator = allocator)
		buffer: [4096]u8 = ---
		for {
			when ODIN_OS == .Windows {
				bytes_read: u32 = ---
				ReadFile(file, &buffer[0], len(buffer), &bytes_read, nil)
			} else when ODIN_OS == .Linux {
				bytes_read: int = ---
				bytes_read = read(file, &buffer[0], len(buffer))
			} else {
				assert(false)
			}
			if bytes_read == 0 {break}
			fmt.sbprint(&sb, string(buffer[:bytes_read]))
		}
		text = to_string(sb)
		// close file
		close_file(file)
	}
	return
}

// write
open_file_for_writing_and_truncate :: proc(file_path: string) -> (file: FileHandle, ok: bool) {
	when ODIN_OS == .Windows {
		file = CreateFileW(&tprint_string_as_wstring(file_path)[0], {.GENERIC_WRITE}, {.FILE_SHARE_READ}, nil, .CreateOrOpenAndTruncate, {.FILE_ATTRIBUTE_NORMAL})
		ok = file != FileHandle(INVALID_HANDLE)
	} else when ODIN_OS == .Linux {
		cbuffer: [WINDOWS_MAX_PATH]byte = ---
		cfile_path, _ := copy_to_cstring(file_path, cbuffer[:])
		file = open(cfile_path, {.O_CREAT, .O_WRONLY, .O_TRUNC})
		ok = file != FileHandle(INVALID_HANDLE)
	} else {
		assert(false)
	}
	return
}
write_to_file :: proc(file: FileHandle, text: string) {
	when ODIN_OS == .Windows {
		assert(len(text) < int(max(u32)))
		bytes_written: DWORD
		WriteFile(file, raw_data(text), u32(len(text)), &bytes_written, nil)
		assert(int(bytes_written) == len(text))
	} else when ODIN_OS == .Linux {
		bytes_written := write(file, raw_data(text), len(text))
		assert(bytes_written == len(text))
	} else {
		assert(false)
	}
}
flush_file_data_and_metadata :: proc(file: FileHandle) {
	when ODIN_OS == .Windows {
		assert(bool(FlushFileBuffers(file)))
	} else when ODIN_OS == .Linux {
		assert(fsync(file) == 0)
	} else {
		assert(false)
	}
}
flush_file_data :: proc(file: FileHandle) {
	when ODIN_OS == .Windows {
		assert(bool(FlushFileBuffers(file)))
	} else when ODIN_OS == .Linux {
		assert(fdatasync(file) == 0)
	} else {
		assert(false)
	}
}
close_file :: proc(file: FileHandle) {
	when ODIN_OS == .Windows {
		CloseHandle(Handle(file))
	} else when ODIN_OS == .Linux {
		close(file)
	} else {
		assert(false)
	}
}

// os agnostic
write_file_atomically :: proc(file_path, text: string) {
	// write to temp file
	temp_file_path := fmt.tprintf("%v.tmp", file_path)
	temp_file, ok := open_file_for_writing_and_truncate(temp_file_path)
	fmt.assertf(ok, "Failed to open file: '%v'", file_path)
	write_to_file(temp_file, text)
	close_file(temp_file)
	// move temp file to file_path
	move_path_atomically(temp_file_path, file_path)
}
