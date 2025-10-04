package lib
import "core:fmt"

when ODIN_OS == .Windows {
	ThreadInfo :: struct {
		id:     ThreadId,
		handle: ThreadHandle,
	}
} else {
	ThreadInfo :: struct {}
	//#assert(false)
}

start_thread :: proc(
	thread_proc: ThreadProc,
	param: rawptr,
	stack_size: Size = 0,
) -> (
	info: ThreadInfo,
) {
	when ODIN_OS == .Windows {
		info.handle = CreateThread(nil, stack_size, thread_proc, param, 0, &info.id)
		fmt.assertf(info.handle != nil, "Failed to create a thread")
	} else {
		assert(false)
	}
	return
}
