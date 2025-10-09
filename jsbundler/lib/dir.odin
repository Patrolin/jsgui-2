package lib
import "core:fmt"

when ODIN_OS == .Windows {
	WatchedDir :: struct {
		/* NOTE: OVERLAPPED must be at the top, so you can cast it to ^WatchedDir, and must not be moved */
		overlapped:   OVERLAPPED,
		path:         string,
		handle:       DirHandle,
		async_buffer: [4096 - size_of(OVERLAPPED) - size_of(string) - size_of(DirHandle)]byte `fmt:"-"`,
	}
} else when ODIN_OS == .Linux {
	WatchedDir :: struct {
		path:         string,
		handle:       DirHandle,
		async_buffer: [4096 - size_of(string) - size_of(DirHandle)]byte `fmt:"-"`,
	}
} else {
	//#assert(false)
}
/* TODO: put a minimum size for the buffer and let it be sized by the allocator */
#assert(size_of(WatchedDir) <= 4096)

ioring_open_dir_for_watching :: proc(ioring: Ioring, dir: ^WatchedDir) {
	when ODIN_OS == .Windows {
		// open directory
		dir.handle = DirHandle(
			CreateFileW(
			&copy_string_to_cwstr(dir.path)[0],
			{.FILE_LIST_DIRECTORY},
			{.FILE_SHARE_READ, .FILE_SHARE_WRITE, .FILE_SHARE_DELETE},
			nil,
			.Open,
			/* NOTE: FILE_FLAG_BACKUP_SEMANTICS is required for directories */
			{.FILE_FLAG_BACKUP_SEMANTICS, .FILE_FLAG_OVERLAPPED},
			),
		)
		fmt.assertf(dir.handle != DirHandle(INVALID_HANDLE), "Failed to open directory for watching: '%v'", dir.path)
		// associate with ioring
		assert(CreateIoCompletionPort(Handle(dir.handle), ioring, 0, 0) != 0)
	} else {
		cbuffer: [WINDOWS_MAX_PATH]byte
		cdir_path, _ := copy_to_cstring(dir.path, cbuffer[:])
		dir.handle = DirHandle(open(cdir_path))
		fmt.assertf(dir.handle >= 0, "Failed to open directory for watching: '%v'", dir.path)
	}
	return
}
/* NOTE: same caveats as walk_files() */
ioring_watch_file_changes_async :: proc(ioring: Ioring, dir: ^WatchedDir) {
	when ODIN_OS == .Windows {
		ok := ReadDirectoryChangesW(dir.handle, &dir.async_buffer[0], len(dir.async_buffer), true, {.FILE_NOTIFY_CHANGE_LAST_WRITE}, nil, &dir.overlapped, nil)
		fmt.assertf(ok == true, "Failed to watch directory for changes")
	} else when ODIN_OS == .Linux {
		/* noop */
	} else {
		assert(false)
	}
}
wait_for_writes_to_finish :: proc(dir: ^WatchedDir) {
	when ODIN_OS == .Windows {
		/* NOTE: windows will give us the start of each write, not the end... */
		offset: u32 = 0
		for {
			// chess battle advanced
			item := (^FILE_NOTIFY_INFORMATION)(&dir.async_buffer[offset])
			relative_file_path := copy_cwstr_to_string(&item.file_name[0], int(item.file_name_length >> 1))
			file_path := fmt.tprint(dir.path, relative_file_path, sep = "/")
			wfile_path := copy_string_to_cwstr(file_path)

			// wait for file_size to change..
			file := CreateFileW(&wfile_path[0], {.GENERIC_READ}, {.FILE_SHARE_READ, .FILE_SHARE_WRITE, .FILE_SHARE_DELETE}, nil, .Open, {.FILE_ATTRIBUTE_NORMAL})
			fmt.assertf(file != FileHandle(INVALID_HANDLE), "file: %v, file_path: '%v'", file, file_path)
			defer close_file(file)

			prev_file_size: LARGE_INTEGER = -1
			file_size: LARGE_INTEGER = 0
			for file_size != prev_file_size {
				prev_file_size = file_size
				Sleep(0) /* NOTE: let other threads run first */
				/* TODO: put open_file_for_reading() and get_file_size() in file.odin */
				GetFileSizeEx(file, &file_size)
			}

			// get the next item
			offset = item.next_entry_offset
			if offset == 0 {break}
		}
	} else {
		assert(false)
	}
}
