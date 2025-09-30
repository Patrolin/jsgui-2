package lib
import "core:fmt"

Ioring :: struct {
	handle: IocpHandle,
	timer:  TimerHandle,
}
IoringEvent :: struct {
	bytes:      u32,
	user_data:  rawptr,
	overlapped: ^OVERLAPPED,
	error:      IoringError,
}

ioring_create :: proc() -> (ioring: Ioring) {
	/* NOTE: allow up to `logical_cores` threads */
	ioring.handle = CreateIoCompletionPort(nil, nil, 0, 0)
	assert(ioring.handle != nil)
	ioring.timer = TimerHandle(INVALID_HANDLE)
	return
}
ioring_set_timer_async :: proc(
	ioring: ^Ioring,
	on_timeout: proc "system" (ioring: rawptr, TimerOrWaitFired: b32),
	ms: int,
) {
	ioring_cancel_timer(ioring)
	ms_u32 := u32(ms)
	assert(int(ms_u32) == ms)
	/* NOTE: this will set a timer on a system-created threadpool, but there's no easy way to just send a timer to an IOCP on windows... */
	ok := CreateTimerQueueTimer(
		&ioring.timer,
		nil,
		on_timeout,
		ioring,
		ms_u32,
		0,
		WT_EXECUTEONLYONCE,
	)
	assert(bool(ok))
}
ioring_cancel_timer :: proc(ioring: ^Ioring) {
	DeleteTimerQueueTimer(nil, ioring.timer, nil)
	ioring.timer = TimerHandle(INVALID_HANDLE)
}
ioring_wait_for_next_event :: proc(ioring: Ioring, event: ^IoringEvent) {
	ok := GetQueuedCompletionStatus(
		ioring.handle,
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
