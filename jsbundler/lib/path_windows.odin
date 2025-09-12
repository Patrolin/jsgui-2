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
	handle:      DirHandle,
	_overlapped: win.OVERLAPPED,
}
FileHandle :: distinct win.HANDLE

// dir procs
open_dir_for_watching :: proc(dir_path: string) -> (dir: WatchedDir) {
	// open dir
	dir.handle = DirHandle(
		win.CreateFileW(
			_string_to_wstring(dir_path),
			win.FILE_LIST_DIRECTORY,
			win.FILE_SHARE_READ | win.FILE_SHARE_WRITE | win.FILE_SHARE_DELETE,
			nil,
			win.OPEN_EXISTING,
			win.FILE_FLAG_BACKUP_SEMANTICS, // NOTE: required for directories
			nil,
		),
	)
	fmt.assertf(dir.handle != nil, "Failed to open directory for watching: '%v'", dir_path)
	return
}
wait_for_file_changes :: proc(dir: ^WatchedDir) {
	bytes_written: u32 = ---
	if dir._overlapped.hEvent == nil {
		assert(
			win.ReadDirectoryChangesW(
				win.HANDLE(dir.handle),
				nil,
				0,
				true, // NOTE: watch subdirectories
				win.FILE_NOTIFY_CHANGE_LAST_WRITE,
				&bytes_written,
				&dir._overlapped,
				nil,
			) == true,
		)
	} else {
		win.GetOverlappedResult(win.HANDLE(dir.handle), &dir._overlapped, &bytes_written, true)
		win.ResetEvent(dir._overlapped.hEvent)
	}
	// NOTE: Windows will notify us at least twice for a single write..
	prev_t := time.now()
	for time.diff(prev_t, time.now()) < time.Millisecond {
		win.GetOverlappedResult(win.HANDLE(dir.handle), &dir._overlapped, &bytes_written, false)
		win.ResetEvent(dir._overlapped.hEvent)
		time.sleep(1)
	}
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
