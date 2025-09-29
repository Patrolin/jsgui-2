package lib
import "core:fmt"

// types
WatchedDir :: struct {
	path:         string,
	handle:       DirHandle,
	overlapped:   OVERLAPPED,
	async_buffer: [2048]byte `fmt:"-"`,
}
// dir procs
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
/* NOTE: same caveats as walk_files() */
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
				Sleep(0) // NOTE: let other threads run first
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
