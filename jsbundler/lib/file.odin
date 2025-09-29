package lib
import "core:fmt"

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
