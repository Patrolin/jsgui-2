package lib
import "core:fmt"

Ioring :: IocpHandle
IoringTimer :: TimerHandle
IoringEvent :: struct {
	bytes:      u32,
	user_data:  rawptr,
	overlapped: ^OVERLAPPED,
	error:      IoringError,
}

ioring_create :: proc() -> (ioring: Ioring) {
	/* NOTE: allow up to `logical_cores` threads */
	ioring = CreateIoCompletionPort(INVALID_HANDLE, nil, 0, 0)
	fmt.assertf(ioring != nil, "Failed to create ioring")
	return
}
ioring_set_timer_async :: proc(
	ioring: Ioring,
	timer: ^IoringTimer,
	ms: int,
	on_timeout: proc "system" (user_data: rawptr, TimerOrWaitFired: b32) = nil,
) {
	ioring_cancel_timer(ioring, timer)
	ms_u32 := u32(ms)
	assert(int(ms_u32) == ms)
	/* NOTE: this will set a timer on a system-created threadpool, but there's no easy way to just send a timer to an IOCP on windows... */
	ok := CreateTimerQueueTimer(timer, nil, on_timeout, ioring, ms_u32, 0, WT_EXECUTEONLYONCE)
	assert(bool(ok))
}
ioring_cancel_timer :: proc(ioring: Ioring, timer: ^IoringTimer) {
	DeleteTimerQueueTimer(nil, timer^, nil)
	timer^ = IoringTimer(INVALID_HANDLE)
}
ioring_wait_for_next_event :: proc(ioring: Ioring, event: ^IoringEvent) {
	ok := GetQueuedCompletionStatus(
		ioring,
		&event.bytes,
		&event.user_data,
		&event.overlapped,
		INFINITE,
	)
	event.error = .None
	if !ok {
		err := GetLastError()
		switch err {
		case ERROR_OPERATION_ABORTED:
			event.error = .IoCanceled
		case ERROR_CONNECTION_ABORTED:
			event.error = .ConnectionClosedByOtherParty
		case:
			fmt.assertf(false, "Failed to get next socket event, err: %v", err)
		}
	}
	return
}
