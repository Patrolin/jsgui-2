package lib
import "core:fmt"

IoringError :: enum {
	None,
	IoCanceled,
	ConnectionClosedByOtherParty,
}
when ODIN_OS == .Windows {
	Ioring :: IocpHandle
	IoringTimer :: TimerHandle
	IoringEvent :: struct {
		bytes:          u32,
		error:          IoringError,
		user_data:      ^OVERLAPPED `fmt:"p"`,
		completion_key: uintptr,
	}
} else when ODIN_OS == .Linux {
	Ioring :: EpollHandle
	IoringTimer :: TimerHandle
	IoringEvent :: struct {
		bytes:     u32,
		error:     IoringError,
		user_data: rawptr,
	}
} else {
	#assert(false)
}

ioring_create :: proc() -> (ioring: Ioring) {
	when ODIN_OS == .Windows {
		/* NOTE: allow up to `logical_cores` threads */
		ioring = CreateIoCompletionPort(INVALID_HANDLE, 0, 0, 0)
		fmt.assertf(ioring != 0, "Failed to create ioring")
	} else when ODIN_OS == .Linux {
		ioring = epoll_create1(0)
		fmt.assertf(ioring >= 0, "Failed to create ioring, err: %v", ioring)
	} else {
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
		fmt.assertf(int(ms_u32) == ms, "Invalid downcast")
		/* NOTE: this will set a timer on a system-created threadpool, but there's no easy way to just send a timer to an IOCP on windows... */
		ok := CreateTimerQueueTimer(timer, 0, on_timeout, user_data, ms_u32, 0, {.WT_EXECUTEONLYONCE})
		fmt.assertf(bool(ok), "Failed to create a timer")
	} else when ODIN_OS == .Linux {
		timer^ = timerfd_create(.CLOCK_MONOTONIC, 0)
		timer_options := TimerOptions64 {
			it_value = {tv_sec = 1},
		}
		timerfd_settime64(timer^, 0, &timer_options)
		fmt.assertf(Handle(timer^) != INVALID_HANDLE, "Failed to create a timer")
	} else {
		assert(false)
	}
}
ioring_cancel_timer :: proc "system" (ioring: Ioring, timer: ^IoringTimer) {
	timer_handle := timer^
	if Handle(timer_handle) == INVALID_HANDLE {
		return /* NOTE: windows crashes your program if you don't do this... */
	}
	when ODIN_OS == .Windows {
		DeleteTimerQueueTimer(0, timer_handle)
	} else when ODIN_OS == .Linux {
		close_handle(Handle(timer_handle))
	} else {
		assert(false)
	}
	timer^ = IoringTimer(INVALID_HANDLE)
}
ioring_wait_for_next_event :: proc(ioring: Ioring, event: ^IoringEvent) {
	when ODIN_OS == .Windows {
		ok := GetQueuedCompletionStatus(ioring, &event.bytes, &event.completion_key, &event.user_data, INFINITE)
		event.error = .None
		if !ok {
			err := GetLastError()
			#partial switch err {
			case .ERROR_OPERATION_ABORTED:
				event.error = .IoCanceled
			case .ERROR_CONNECTION_ABORTED:
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
