package lib
import "core:fmt"

ThreadProc :: THREAD_START_ROUTINE
ThreadInfo :: struct {
	id:     ThreadId,
	handle: ThreadHandle,
}
start_thread :: proc(
	thread_proc: ThreadProc,
	param: rawptr,
	stack_size: Size = 0,
) -> (
	info: ThreadInfo,
) {
	info.handle = CreateThread(nil, stack_size, thread_proc, param, 0, &info.id)
	fmt.assertf(info.handle != nil, "Failed to create a thread")
	return
}
