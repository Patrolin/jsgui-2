package lib
import "core:fmt"

IoringError :: enum {
	None,
	IoCanceled,
	ConnectionClosedByOtherParty,
}
IoringEvent :: struct {
	bytes:   u32,
	error:   IoringError,
	using _: IoringEvent_OsFooter,
}
when ODIN_OS == .Windows {
	Ioring :: IocpHandle
	IoringTimer :: TimerHandle
	IoringEvent_OsFooter :: struct {
		user_data:      ^OVERLAPPED,
		completion_key: rawptr,
	}
} else when ODIN_OS == .Linux {
	Ioring :: IoringHandle
	IoringTimer :: TimerHandle
	IoringEvent_OsFooter :: struct {
		user_data: rawptr,
	}
} else {
	#assert(false)
}

ioring_create :: proc() -> (ioring: Ioring) {
	when ODIN_OS == .Windows {
		/* NOTE: allow up to `logical_cores` threads */
		ioring = CreateIoCompletionPort(INVALID_HANDLE, nil, 0, 0)
		fmt.assertf(ioring != nil, "Failed to create ioring")
	} else {
		/* TODO: io_uring + io_uring_prep_accept() on linux */
		assert(false)
	}
	return
}
ioring_set_timer_async :: proc(
	ioring: Ioring,
	timer: ^IoringTimer,
	ms: int,
	user_data: rawptr,
	on_timeout: proc "system" (user_data: rawptr, TimerOrWaitFired: b32) = nil,
) {
	ioring_cancel_timer(ioring, timer)
	when ODIN_OS == .Windows {
		ms_u32 := u32(ms)
		assert(int(ms_u32) == ms)
		/* NOTE: this will set a timer on a system-created threadpool, but there's no easy way to just send a timer to an IOCP on windows... */
		ok := CreateTimerQueueTimer(
			timer,
			nil,
			on_timeout,
			user_data,
			ms_u32,
			0,
			WT_EXECUTEONLYONCE,
		)
	} else {
		assert(false)
	}
	assert(bool(ok))
}
ioring_cancel_timer :: proc "system" (ioring: Ioring, timer: ^IoringTimer) {
	when ODIN_OS == .Windows {
		DeleteTimerQueueTimer(nil, timer^, nil)
		timer^ = IoringTimer(INVALID_HANDLE)
	} else {
		assert(false)
	}
}
ioring_wait_for_next_event :: proc(ioring: Ioring, event: ^IoringEvent) {
	when ODIN_OS == .Windows {
		ok := GetQueuedCompletionStatus(
			ioring,
			&event.bytes,
			&event.completion_key,
			&event.user_data,
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
				fmt.assertf(false, "Failed to get next ioring event, err: %v", err)
			}
		}
	} else {
		assert(false)
	}
	return
}
