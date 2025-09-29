package lib
import "core:fmt"

// process procs
get_args :: proc(allocator := context.temp_allocator) -> (args: [dynamic]string) {
	// TODO: get_args() in linux
	return
}
exit_process :: proc(exit_code: u32 = 0) {
	exit(i32(exit_code))
}
