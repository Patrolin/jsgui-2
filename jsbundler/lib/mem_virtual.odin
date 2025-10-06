package lib
import "core:fmt"

@(private)
DEBUG_VIRTUAL :: false

// procs
init_page_fault_handler :: proc "contextless" () {
	when ODIN_OS == .Windows {
		_page_fault_exception_handler :: proc "system" (exception: ^_EXCEPTION_POINTERS) -> ExceptionResult {
			when DEBUG_VIRTUAL {
				context = runtime.default_context()
				fmt.printfln(
					"exception %v: %v",
					exception.ExceptionRecord.ExceptionCode,
					exception.ExceptionRecord.ExceptionInformation[:exception.ExceptionRecord.NumberParameters],
				)
			}
			if exception.ExceptionRecord.ExceptionCode == .EXCEPTION_ACCESS_VIOLATION {
				ptr := exception.ExceptionRecord.ExceptionInformation[1]
				page_ptr := rawptr(uintptr(ptr) & ~uintptr(PAGE_SIZE - 1))
				commited_ptr := VirtualAlloc(page_ptr, 4096, {.MEM_COMMIT}, {.PAGE_READWRITE})
				return page_ptr != nil && commited_ptr != nil ? .EXCEPTION_CONTINUE_EXECUTION : .EXCEPTION_EXECUTE_HANDLER
			}
			return .EXCEPTION_EXECUTE_HANDLER
		}
		SetUnhandledExceptionFilter(_page_fault_exception_handler)
	} else when ODIN_OS == .Linux {
		/* NOTE: linux has a default page fault handler */
	} else {
		assert_contextless(false)
	}
}
page_reserve :: proc(size: Size) -> []byte {
	when ODIN_OS == .Windows {
		ptr := VirtualAlloc(nil, size, {.MEM_RESERVE}, {.PAGE_READWRITE})
		assert(ptr != nil)
	} else when ODIN_OS == .Linux {
		ptr := mmap(nil, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS)
		assert(ptr != max(uintptr))
	} else {
		assert(false)
	}
	return ([^]byte)(ptr)[:size]
}
page_free :: proc(ptr: rawptr) {
	when ODIN_OS == .Windows {
		assert(bool(VirtualFree(ptr, 0, {.MEM_RELEASE})))
	} else when ODIN_OS == .Linux {
		assert(munmap(ptr, 0) == 0)
	} else {
		assert(false)
	}
}
