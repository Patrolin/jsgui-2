package lib
import "core:fmt"
import "core:path/filepath"

// file procs
create_dir_if_not_exists :: proc(dir_path: string) -> (ok: bool) #no_bounds_check {
	cdir_path: [WINDOWS_MAX_PATH]byte = ---
	copy_to_cstring(dir_path, cdir_path[:])

	err := mkdir(cstring(&cdir_path[0]))
	return err == ERR_NONE || err == ERR_EXIST
}
move_path_atomically :: proc(src_path, dest_path: string) #no_bounds_check {
	cbuffer: [2 * WINDOWS_MAX_PATH]byte = ---
	csrc_path := cbuffer[:WINDOWS_MAX_PATH]
	copy_to_cstring(src_path, csrc_path)
	cdest_path := cbuffer[len(src_path) + 1:]
	copy_to_cstring(dest_path, cdest_path)

	err := renameat2(AT_FDCWD, cstring(&csrc_path[0]), AT_FDCWD, cstring(&cdest_path[0]))
	assert(err == ERR_NONE)
}
walk_files :: proc(
	dir_path: string,
	callback: proc(path: string, data: rawptr),
	data: rawptr = nil,
) {
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
}
read_file :: proc(file_path: string) -> (text: string, ok: bool) {
	assert(false, "TODO")
	return
}
open_file_for_writing_and_truncate :: proc(file_path: string) -> (file: FileHandle, ok: bool) {
	assert(false, "TODO")
	return
}
write_to_file :: proc(file: FileHandle, text: string) {
	assert(false, "TODO")
}
flush_file :: proc(file: FileHandle) {
	assert(false, "TODO")
}
close_file :: proc(file: FileHandle) {
	assert(false, "TODO")
}
