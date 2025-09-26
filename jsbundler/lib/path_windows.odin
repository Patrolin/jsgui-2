package lib
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:time"

// constants
ERROR_IO_INCOMPLETE :: 996
ERROR_IO_PENDING :: 997

// types
WatchedDir :: struct {
	path:         string,
	handle:       DirHandle,
	overlapped:   OVERLAPPED,
	async_buffer: [2048]byte `fmt:"-"`,
}

// path procs
move_path_atomically :: proc(src_path, dest_path: string) {
	result := MoveFileExW(
		&tprint_string_as_wstring(src_path)[0],
		&tprint_string_as_wstring(dest_path)[0],
		MOVEFILE_REPLACE_EXISTING,
	)
	fmt.assertf(bool(result), "Failed to move path: '%v' to '%v'", src_path, dest_path)
}

// dir procs
create_dir_if_not_exists :: proc(dir_path: string) -> (ok: bool) {
	CreateDirectoryW(&tprint_string_as_wstring(dir_path)[0], nil)
	err := GetLastError()
	return err != ERROR_PATH_NOT_FOUND
}
open_dir_for_watching :: proc(dir_path: string) -> (dir: WatchedDir) {
	// open dir
	dir.path = dir_path
	dir.handle = DirHandle(
		CreateFileW(
			&tprint_string_as_wstring(dir_path)[0],
			FILE_LIST_DIRECTORY,
			FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
			nil,
			F_OPEN,
			FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED, // NOTE: FILE_FLAG_BACKUP_SEMANTICS is required for directories
			nil,
		),
	)
	fmt.assertf(dir.handle != nil, "Failed to open directory for watching: '%v'", dir_path)
	// setup async watch
	dir.overlapped = {
		hEvent = CreateEventW(nil, true, false, nil),
	}
	ok := ReadDirectoryChangesW(
		dir.handle,
		&dir.async_buffer[0],
		len(dir.async_buffer),
		true,
		/* NOTE: watch subdirectories */
		FILE_NOTIFY_CHANGE_LAST_WRITE,
		nil,
		&dir.overlapped,
		nil,
	)
	fmt.assertf(ok == true, "Failed to watch directory for changes")
	return
}
/* NOTE: We only support up to `wlen(dir) + 1 + wlen(relative_file_path) < MAX_PATH (259 utf16 chars + null terminator)`. \
	While we *can* give windows paths longer than that as input, it has no way to return those paths back to us. \
	And `ReadDirectoryChangesW()` *does* give us relative paths, so we *could* extend support to `wlen(relative_file_path) < MAX_PATH`, \
	but we can only call it on the root directory.
*/
wait_for_file_changes :: proc(dir: ^WatchedDir) {
	wait_for_writes_to_finish :: proc(dir: ^WatchedDir) {
		/* NOTE: windows will give us the start of each write, not the end... */
		offset: u32 = 0
		for {
			// chess battle advanced
			item := (^FILE_NOTIFY_INFORMATION)(&dir.async_buffer[offset])
			wrelative_file_path := ([^]u16)(&item.file_name)[:item.file_name_length >> 1]
			relative_file_path := tprint_wstring(string16(wrelative_file_path))
			file_path := fmt.tprint(dir.path, relative_file_path, sep = "/")
			wfile_path := tprint_string_as_wstring(file_path)

			// wait for file_size to change..
			file := CreateFileW(
				&wfile_path[0],
				GENERIC_READ,
				FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
				nil,
				F_OPEN,
				FILE_ATTRIBUTE_NORMAL,
				nil,
			)
			fmt.assertf(file != INVALID_HANDLE, "file: %v, file_path: '%v'", file, file_path)
			defer close_file(FileHandle(file))

			prev_file_size: LARGE_INTEGER = -1
			file_size: LARGE_INTEGER = 0
			for file_size != prev_file_size {
				prev_file_size = file_size
				time.sleep(1 * time.Microsecond)
				GetFileSizeEx(FileHandle(file), &file_size)
			}

			// get the next item
			offset = item.next_entry_offset
			if offset == 0 {break}
		}
	}

	// wait for changes
	bytes_written: u32 = ---
	wait := true
	for {
		/* NOTE: windows will give us multiple notifications per file (truncate (or literally nothing) + the start of each write) */
		wait_result := WaitForSingleObject(dir.overlapped.hEvent, wait ? INFINITE : 1)
		if wait_result == WAIT_TIMEOUT {break}
		fmt.assertf(
			wait_result == WAIT_OBJECT_0,
			"Failed to wait for file changes, wait_result: %v",
			wait_result,
		)
		ok := GetOverlappedResult(HANDLE(dir.handle), &dir.overlapped, &bytes_written, true)
		if ok {
			/* NOTE: windows in its infinite wisdom can signal us with 0 bytes written, with no way to know what actually changed... */
			if bytes_written > 0 {wait_for_writes_to_finish(dir)}
			// NOTE: only reset the event after windows has finished writing the changes
			fmt.assertf(ResetEvent(dir.overlapped.hEvent) == true, "Failed to reset event")
			ok = ReadDirectoryChangesW(
				dir.handle,
				&dir.async_buffer[0],
				len(dir.async_buffer),
				true, // NOTE: watch subdirectories
				FILE_NOTIFY_CHANGE_LAST_WRITE,
				nil,
				&dir.overlapped,
				nil,
			)
			fmt.assertf(ok == true, "Failed to watch directory for changes")
			wait = false
		} else {
			err := GetLastError()
			fmt.assertf(
				err == ERROR_IO_INCOMPLETE || err == ERROR_IO_PENDING,
				"Failed to call GetOverlappedResult(), err: %v",
				err,
			)
		}
	}
}

// file procs
/* NOTE: same caveats as wait_for_file_changes() */
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
		sb := strings.builder_make_none()
		buffer: [4096]u8 = ---
		bytes_read: u32
		for {
			ReadFile(FileHandle(file), &buffer[0], len(buffer), &bytes_read, nil)
			if bytes_read == 0 {break}
			fmt.sbprint(&sb, transmute(string)(buffer[:bytes_read]))
		}
		CloseHandle(file)
		text = strings.to_string(sb)
	}
	return
}
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
	flush_file(file)
	CloseHandle(HANDLE(file))
}
