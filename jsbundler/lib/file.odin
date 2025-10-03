package lib
import "core:fmt"

create_dir_if_not_exists :: proc(dir_path: string) -> (ok: bool) {
	when ODIN_OS == .Windows {
		CreateDirectoryW(&tprint_string_as_wstring(dir_path)[0], nil)
		err := GetLastError()
		return err != ERROR_PATH_NOT_FOUND
	} else when ODIN_OS == .Linux {
		cdir_path: [WINDOWS_MAX_PATH]byte = ---
		copy_to_cstring(dir_path, cdir_path[:])

		err := mkdir(cstring(&cdir_path[0]))
		return err == ERR_NONE || err == ERR_EXIST
	} else {
		assert(false)
	}
}
move_path_atomically :: proc(src_path, dest_path: string) {
	when ODIN_OS == .Windows {
		result := MoveFileExW(
			&tprint_string_as_wstring(src_path)[0],
			&tprint_string_as_wstring(dest_path)[0],
			MOVEFILE_REPLACE_EXISTING,
		)
		fmt.assertf(bool(result), "Failed to move path: '%v' to '%v'", src_path, dest_path)
	} else when ODIN_OS == .Linux {
		cbuffer: [2 * WINDOWS_MAX_PATH]byte = ---
		csrc_path := cbuffer[:WINDOWS_MAX_PATH]
		copy_to_cstring(src_path, csrc_path)
		cdest_path := cbuffer[len(src_path) + 1:]
		copy_to_cstring(dest_path, cdest_path)

		err := renameat2(AT_FDCWD, cstring(&csrc_path[0]), AT_FDCWD, cstring(&cdest_path[0]))
		assert(err == ERR_NONE)
	} else {
		assert(false)
	}
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
	} else when ODIN_OS == .Linux {
		cdir_path: [WINDOWS_MAX_PATH]byte = ---
		copy_to_cstring(dir_path, cdir_path[:])

		dir := DirHandle(open(cstring(&cdir_path[0]), O_RDONLY | O_DIRECTORY))
		if int(dir) == ERR_NOTDIR {
			callback(dir_path, data)
		} else {
			assert(int(dir) == ERR_NONE)
			dir_entries_buffer: [4096]byte
			bytes_written := getdents64(dir, &dir_entries_buffer[0], len(dir_entries_buffer))
			assert(bytes_written >= 0)
			if bytes_written == 0 {return}

			offset := 0
			for offset < len(dir_entries_buffer) {
				dirent := (^Dirent64)(&dir_entries_buffer[offset])
				/* TODO: compute len(file_name) directly from dirent.size */
				assert(false)
				cfile_name := transmute(cstring)(&dirent.cfile_name)
				file_name := string(cfile_name)
				fmt.printfln("dirent: %v, '%v'", dirent, file_name)
				offset += int(dirent.size)
			}
		}
	} else {
		assert(false)
	}
}
read_file :: proc(file_path: string) -> (text: string, ok: bool) {
	when ODIN_OS == .Windows {
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
	} else {
		assert(false)
	}
	return
}
open_file_for_writing_and_truncate :: proc(file_path: string) -> (file: FileHandle, ok: bool) {
	when ODIN_OS == .Windows {
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
	} else {
		assert(false)
	}
}
flush_file :: proc(file: FileHandle) {
	when ODIN_OS == .Windows {
		FlushFileBuffers(file)
	} else {
		assert(false)
	}
}
close_file :: proc(file: FileHandle) {
	when ODIN_OS == .Windows {
		CloseHandle(HANDLE(file))
	} else {
		assert(false)
	}
}

// os agnostic
write_file_atomically :: proc(file_path, text: string) {
	// write to temp file
	temp_file_path := fmt.tprintf("%v.tmp", file_path)
	temp_file, ok := open_file_for_writing_and_truncate(temp_file_path)
	assert(ok)
	write_to_file(temp_file, text)
	close_file(temp_file)
	// move temp file to file_path
	move_path_atomically(temp_file_path, file_path)
}
