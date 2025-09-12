package lib
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:strings"
import win "core:sys/windows"
import "core:time"

// types
DirHandle :: distinct win.HANDLE
WatchedDir :: struct {
	path:         string,
	handle:       DirHandle,
	overlapped:   win.OVERLAPPED,
	async_buffer: [2048]byte `fmt:"-"`,
}
FileHandle :: distinct win.HANDLE

// dir procs
open_dir_for_watching :: proc(dir_path: string) -> (dir: WatchedDir) {
	// open dir
	dir.path = dir_path
	dir.handle = DirHandle(
		win.CreateFileW(
			_string_to_wstring(dir_path),
			win.FILE_LIST_DIRECTORY,
			win.FILE_SHARE_READ | win.FILE_SHARE_WRITE | win.FILE_SHARE_DELETE,
			nil,
			win.OPEN_EXISTING,
			win.FILE_FLAG_BACKUP_SEMANTICS | win.FILE_FLAG_OVERLAPPED, // NOTE: FILE_FLAG_BACKUP_SEMANTICS is required for directories
			nil,
		),
	)
	fmt.assertf(dir.handle != nil, "Failed to open directory for watching: '%v'", dir_path)
	// setup async watch
	dir.overlapped = {
		hEvent = win.CreateEventW(nil, true, false, nil),
	}
	ok := win.ReadDirectoryChangesW(
		win.HANDLE(dir.handle),
		&dir.async_buffer,
		len(dir.async_buffer),
		true, // NOTE: watch subdirectories
		win.FILE_NOTIFY_CHANGE_LAST_WRITE,
		nil,
		&dir.overlapped,
		nil,
	)
	fmt.assertf(ok == true, "Failed to watch directory for changes")
	return
}
wait_for_file_changes :: proc(dir: ^WatchedDir) {
	wait_for_writes_to_finish :: proc(dir: ^WatchedDir) {
		bytes_written: u32 = ---
		ok := win.GetOverlappedResult(
			win.HANDLE(dir.handle),
			&dir.overlapped,
			&bytes_written,
			false,
		)
		fmt.assertf(ok == true, "Failed to wait for file changes, err: %v", win.GetLastError())
		// NOTE: windows will only give us notifications for the start of each write for each file, not the end of all writes for each file
		offset: u32 = 0
		for {
			// chess battle advanced
			item := (^win.FILE_NOTIFY_INFORMATION)(&dir.async_buffer[offset])
			wrelative_file_path_buffer := ([^]u16)(&item.file_name)[:item.file_name_length]
			relative_file_path := _wstring_to_string(wrelative_file_path_buffer)
			file_path := fmt.tprint(dir.path, relative_file_path, sep = "/")
			fmt.printfln("item: %v, file_path: %v", item, file_path)
			wcfile_path := _string_to_wstring(file_path)

			// wait for file_size to change..
			file := win.CreateFileW(
				wcfile_path,
				win.GENERIC_READ,
				win.FILE_SHARE_READ | win.FILE_SHARE_WRITE | win.FILE_SHARE_DELETE,
				nil,
				win.OPEN_EXISTING,
				win.FILE_ATTRIBUTE_NORMAL,
				nil,
			)
			fmt.assertf(file != win.INVALID_HANDLE, "file: %v, file_path: '%v'", file, file_path)
			defer close_file(FileHandle(file))

			prev_file_size: win.LARGE_INTEGER = -1
			file_size: win.LARGE_INTEGER = 0
			for file_size != prev_file_size {
				prev_file_size = file_size
				time.sleep(10)
				win.GetFileSizeEx(file, &file_size)
			}
			// get the next item
			offset = item.next_entry_offset
			if offset == 0 {break}
		}
	}
	// wait for changes
	fmt.printfln("dir: %v", dir)
	fmt.assertf(
		win.WaitForSingleObject(dir.overlapped.hEvent, win.INFINITE) == win.WAIT_OBJECT_0,
		"Failed to wait for file changes",
	)
	wait_for_writes_to_finish(dir)
	// while have_changes() {pop_change()}
	/* TODO: wtf
	for i in 0 ..< 3 {
		win.ResetEvent(dir.overlapped.hEvent)
		fmt.printfln("i: %v", i)
		time.sleep(time.Millisecond)

		ok := win.ReadDirectoryChangesW(
			win.HANDLE(dir.handle),
			&dir.async_buffer,
			len(dir.async_buffer),
			true, // NOTE: watch subdirectories
			win.FILE_NOTIFY_CHANGE_LAST_WRITE,
			nil,
			&dir.overlapped,
			nil,
		)
		fmt.assertf(ok == true, "Failed to watch directory for changes")
		state := win.WaitForSingleObject(dir.overlapped.hEvent, 0)
		ok = state == win.WAIT_OBJECT_0
		fmt.printfln("i: %v, ok: %v, state: %v", i, ok, state)
		if !ok {break}
		wait_for_writes_to_finish(dir)
	}
	*/
}

// file procs
walk_files :: proc(dir_path: string, callback: proc(path: string, data: rawptr), data: rawptr) {
	path_to_search := fmt.tprint(dir_path, "*", sep = "\\")
	wpath_to_search := _string_to_wstring(path_to_search)
	find_result: win.WIN32_FIND_DATAW
	find := win.FindFirstFileW(wpath_to_search, &find_result)
	if find != win.INVALID_HANDLE_VALUE {
		for {
			relative_wpath := win.wstring(&find_result.cFileName[0])
			relative_path := _wstring_to_string(relative_wpath)
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
		win.FILE_SHARE_READ,
		nil,
		win.OPEN_EXISTING,
		0,
		nil,
	)
	ok = file != nil
	if ok {
		sb := strings.builder_make_none()
		buffer: [4096]u8 = ---
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
	file = FileHandle(
		win.CreateFileW(
			_string_to_wstring(file_path),
			win.GENERIC_WRITE,
			win.FILE_SHARE_READ,
			nil,
			win.TRUNCATE_EXISTING,
			win.FILE_ATTRIBUTE_NORMAL,
			nil,
		),
	)
	ok = file != nil
	return
}
write :: proc(file: FileHandle, text: string) {
	assert(len(text) < int(max(u32)))
	win.WriteFile(win.HANDLE(file), raw_data(text), u32(len(text)), nil, nil)
}
flush_file :: proc(file: FileHandle) {
	win.FlushFileBuffers(win.HANDLE(file))
}
close_file :: proc(file: FileHandle) {
	flush_file(file)
	win.CloseHandle(win.HANDLE(file))
}
