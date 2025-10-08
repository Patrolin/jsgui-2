#+private package
package lib
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:sys/linux"

// common
when ODIN_OS == .Windows {
	/* NOTE: Windows ships only on x64 */
	// types
	BOOL :: b32
	BYTE :: u8
	WORD :: u16
	DWORD :: u32
	QWORD :: u64
	LARGE_INTEGER :: i64

	CSTR :: [^]byte
	CWSTR :: [^]u16
	ULONG_PTR :: uintptr

	// flags
	INFINITE :: max(u32)
	CodePage :: enum CUINT {
		CP_UTF8 = 65001,
	}
	WideCharFlags :: bit_set[enum {
		WC_ERR_INVALID_CHARS = 7,
	};DWORD]
	MultiByteFlags :: bit_set[enum {
		MB_ERR_INVALID_CHARS = 3,
	};DWORD]
	OsError :: enum DWORD {
		ERROR_PATH_NOT_FOUND     = 3,
		ERROR_OPERATION_ABORTED  = 995,
		ERROR_IO_INCOMPLETE      = 996,
		ERROR_IO_PENDING         = 997,
		ERROR_CONNECTION_ABORTED = 1236,
	}

	// procs
	foreign import kernel32 "system:Kernel32.lib"
	@(default_calling_convention = "c")
	foreign kernel32 {
		WideCharToMultiByte :: proc(CodePage: CodePage, flags: WideCharFlags, wstr: CWSTR, wlen: CINT, str: CSTR, len: CINT, lpDefaultChar: CSTR, lpUsedDefaultChar: ^BOOL) -> CINT ---
		MultiByteToWideChar :: proc(CodePage: CodePage, flags: MultiByteFlags, str: CSTR, len: CINT, wstr: CWSTR, wlen: CINT) -> CINT ---
		GetLastError :: proc() -> OsError ---
		//CreateEventW :: proc(security: ^SECURITY_ATTRIBUTES, manual_reset: BOOL, initial_state: BOOL, name: CWSTR) -> Handle ---
		//ResetEvent :: proc(handle: Handle) -> BOOL ---
		//WaitForSingleObject :: proc(handle: Handle, milliseconds: DWORD) -> DWORD ---
		CloseHandle :: proc(handle: Handle) -> BOOL ---
	}

	/* TODO: refactor these */
	@(private = "file")
	tprint_cwstr :: proc(cwstr: CWSTR, wlen := -1, allocator := context.temp_allocator) -> string {
		wlen_cint := CINT(wlen)
		assert(int(wlen_cint) == wlen)

		if intrinsics.expect(wlen_cint == 0, false) {return ""}

		cstr_len := WideCharToMultiByte(.CP_UTF8, {.WC_ERR_INVALID_CHARS}, cwstr, wlen_cint, nil, 0, nil, nil)
		/* NOTE: Windows counts the null terminator if wlen == -1 */
		str_len := cstr_len - (wlen == -1 ? 1 : 0)
		if intrinsics.expect(str_len == 0, false) {return ""}

		str_buf, err := make([]byte, cstr_len, allocator = allocator)
		assert(err == nil)
		written_bytes := WideCharToMultiByte(.CP_UTF8, {.WC_ERR_INVALID_CHARS}, cwstr, wlen_cint, &str_buf[0], cstr_len, nil, nil)
		assert(written_bytes == cstr_len)
		return string(str_buf[:str_len])
	}
	@(private = "file")
	tprint_string16 :: proc(wstr: string16, allocator := context.temp_allocator) -> string {
		return tprint_cwstr(raw_data(wstr), len(wstr), allocator = allocator)
	}
	tprint_wstring :: proc {
		tprint_cwstr,
		tprint_string16,
	}
	tprint_string_as_wstring :: proc(str: string, allocator := context.temp_allocator, loc := #caller_location) -> []u16 {
		str_len := len(str)
		str_len_cint := CINT(str_len)
		assert(int(str_len_cint) == str_len, loc = loc)

		wlen := MultiByteToWideChar(.CP_UTF8, {.MB_ERR_INVALID_CHARS}, raw_data(str), str_len_cint, nil, 0)
		assert(wlen != 0, loc = loc)
		cwlen := wlen + 1
		cwstr_buf := make([]u16, cwlen, allocator = allocator)

		written_chars := MultiByteToWideChar(.CP_UTF8, {.MB_ERR_INVALID_CHARS}, raw_data(str), str_len_cint, &cwstr_buf[0], cwlen)
		assert(written_chars == wlen, loc = loc)
		return cwstr_buf[:cwlen]
	}
} else when ODIN_OS == .Linux {
	/* NOTE: linux ships on many architectures, and SYS_XXX probably depends on architecture */

	// flags
	ERR_NONE :: int(0)
	ERR_PERM :: int(-1)
	ERR_NOENT :: int(-2)
	ERR_SRCH :: int(-3)
	ERR_INTR :: int(-4)
	ERR_IO :: int(-5)
	ERR_NXIO :: int(-6)
	ERR_2BIG :: int(-7)
	ERR_NOEXEC :: int(-8)
	ERR_BADF :: int(-9)
	ERR_CHILD :: int(-10)
	ERR_AGAIN :: int(-11)
	ERR_WOULDBLOCK :: ERR_AGAIN
	ERR_NOMEM :: int(-12)
	ERR_ACCES :: int(-13)
	ERR_FAULT :: int(-14)
	ERR_NOTBLK :: int(-15)
	ERR_BUSY :: int(-16)
	ERR_EXIST :: int(-17)
	ERR_XDEV :: int(-18)
	ERR_NODEV :: int(-19)
	ERR_NOTDIR :: int(-20)
	ERR_ISDIR :: int(-21)
	ERR_INVAL :: int(-22)
	ERR_NFILE :: int(-23)
	ERR_MFILE :: int(-24)
	ERR_NOTTY :: int(-25)
	ERR_TXTBSY :: int(-26)
	ERR_FBIG :: int(-27)
	ERR_NOSPC :: int(-28)
	ERR_SPIPE :: int(-29)
	ERR_ROFS :: int(-30)
	ERR_MLINK :: int(-31)
	ERR_PIPE :: int(-32)
	ERR_DOM :: int(-33)
	ERR_RANGE :: int(-34)

	ERR_DEADLOCK :: int(-35)
	ERR_NAMETOOLONG :: int(-36)
	ERR_NOLCK :: int(-37)
	ERR_NOSYS :: int(-38)
	ERR_NOTEMPTY :: int(-39)
	ERR_LOOP :: int(-40)
	ERR_UNKNOWN_41 :: int(-41)
	ERR_NOMSG :: int(-42)
	ERR_IDRM :: int(-43)
	ERR_CHRNG :: int(-44)
	ERR_L2NSYNC :: int(-45)
	ERR_L3HLT :: int(-46)
	ERR_L3RST :: int(-47)
	ERR_LNRNG :: int(-48)
	ERR_UNATCH :: int(-49)
	ERR_NOCSI :: int(-50)
	ERR_L2HLT :: int(-51)
	ERR_BADE :: int(-52)
	ERR_BADR :: int(-53)
	ERR_XFULL :: int(-54)
	ERR_NOANO :: int(-55)
	ERR_BADRQC :: int(-56)
	ERR_BADSLT :: int(-57)
	ERR_UNKNOWN_58 :: int(-58)
	ERR_BFONT :: int(-59)
	ERR_NOSTR :: int(-60)
	ERR_NODATA :: int(-61)
	ERR_TIME :: int(-62)
	ERR_NOSR :: int(-63)
	ERR_NONET :: int(-64)
	ERR_NOPKG :: int(-65)
	ERR_REMOTE :: int(-66)
	ERR_NOLINK :: int(-67)
	ERR_ADV :: int(-68)
	ERR_SRMNT :: int(-69)
	ERR_COMM :: int(-70)
	ERR_PROTO :: int(-71)
	ERR_MULTIHOP :: int(-72)
	ERR_DOTDOT :: int(-73)
	ERR_BADMSG :: int(-74)
	ERR_OVERFLOW :: int(-75)
	ERR_NOTUNIQ :: int(-76)
	ERR_BADFD :: int(-77)
	ERR_REMCHG :: int(-78)
	ERR_LIBACC :: int(-79)
	ERR_LIBBAD :: int(-80)
	ERR_LIBSCN :: int(-81)
	ERR_LIBMAX :: int(-82)
	ERR_LIBEXEC :: int(-83)
	ERR_ILSEQ :: int(-84)
	ERR_RESTART :: int(-85)
	ERR_STRPIPE :: int(-86)
	ERR_USERS :: int(-87)
	ERR_NOTSOCK :: int(-88)
	ERR_DESTADDRREQ :: int(-89)
	ERR_MSGSIZE :: int(-90)
	ERR_PROTOTYPE :: int(-91)
	ERR_NOPROTOOPT :: int(-92)
	ERR_PROTONOSUPPORT :: int(-93)
	ERR_SOCKTNOSUPPORT :: int(-94)
	ERR_OPNOTSUPP :: int(-95)
	ERR_PFNOSUPPORT :: int(-96)
	ERR_AFNOSUPPORT :: int(-97)
	ERR_ADDRINUSE :: int(-98)
	ERR_ADDRNOTAVAIL :: int(-99)
	ERR_NETDOWN :: int(-100)
	ERR_NETUNREACH :: int(-101)
	ERR_NETRESET :: int(-102)
	ERR_CONNABORTED :: int(-103)
	ERR_CONNRESET :: int(-104)
	ERR_NOBUFS :: int(-105)
	ERR_ISCONN :: int(-106)
	ERR_NOTCONN :: int(-107)
	ERR_SHUTDOWN :: int(-108)
	ERR_TOOMANYREFS :: int(-109)
	ERR_TIMEDOUT :: int(-110)
	ERR_CONNREFUSED :: int(-111)
	ERR_HOSTDOWN :: int(-112)
	ERR_HOSTUNREACH :: int(-113)
	ERR_ALREADY :: int(-114)
	ERR_INPROGRESS :: int(-115)
	ERR_STALE :: int(-116)
	ERR_UCLEAN :: int(-117)
	ERR_NOTNAM :: int(-118)
	ERR_NAVAIL :: int(-119)
	ERR_ISNAM :: int(-120)
	ERR_REMOTEIO :: int(-121)
	ERR_DQUOT :: int(-122)
	ERR_NOMEDIUM :: int(-123)
	ERR_MEDIUMTYPE :: int(-124)
	ERR_CANCELED :: int(-125)
	ERR_NOKEY :: int(-126)
	ERR_KEYEXPIRED :: int(-127)
	ERR_KEYREVOKED :: int(-128)
	ERR_KEYREJECTED :: int(-129)
	ERR_OWNERDEAD :: int(-130)
	ERR_NOTRECOVERABLE :: int(-131)
	ERR_RFKILL :: int(-132)
	ERR_HWPOISON :: int(-133)

	// procs
	close_handle :: #force_inline proc "system" (handle: Handle) -> int {
		return int(intrinsics.syscall(linux.SYS_close, uintptr(handle)))
	}
	@(require_results)
	copy_to_cstring :: #force_inline proc(str: string, cbuffer: []byte) -> (cstr: cstring, next_cbuffer: []byte) #no_bounds_check {
		clen := len(str) + 1
		assert(clen < len(cbuffer))
		copy(transmute([]byte)str, cbuffer)
		cbuffer[len(str)] = 0
		cstr = cstring(&cbuffer[0])
		next_cbuffer = cbuffer[clen:]
		return
	}
	string_from_cstring :: #force_inline proc(cstr: [^]byte, len_lower_bound: int) -> string #no_bounds_check {
		len := len_lower_bound
		for cstr[len] != 0 {len += 1}
		return transmute(string)runtime.Raw_String{transmute([^]byte)cstr, len}
	}
} else {
	//#assert(false)
}


// process
when ODIN_OS == .Windows {
	// procs
	foreign kernel32 {
		GetCommandLineW :: proc() -> CWSTR ---
		ExitProcess :: proc(uExitCode: CUINT) ---
	}
} else when ODIN_OS == .Linux {
	// procs
	exit :: #force_inline proc "system" (exit_code: CINT) {
		intrinsics.syscall(linux.SYS_exit, uintptr(exit_code))
	}
} else {
	//#assert(false)
}

// thread
ThreadProc :: proc "system" (param: rawptr) -> u32
when ODIN_OS == .Windows {
	// types
	ThreadId :: distinct DWORD
	ThreadHandle :: distinct Handle

	SECURITY_DESCRIPTOR :: struct {
		/* ... */
	}
	SECURITY_ATTRIBUTES :: struct {
		nLength:              DWORD,
		lpSecurityDescriptor: ^SECURITY_DESCRIPTOR,
		bInheritHandle:       BOOL,
	}
	// procs
	foreign kernel32 {
		Sleep :: proc(ms: DWORD) ---
		/* Return the new `ThreadHandle`, or `0` */
		CreateThread :: proc(attributes: ^SECURITY_ATTRIBUTES, stack_size: Size, thread_proc: ThreadProc, param: rawptr, flags: DWORD, thread_id: ^ThreadId) -> ThreadHandle ---
	}
} else {
	//#assert(false)
}

// alloc
when ODIN_OS == .Windows {
	// types
	ExceptionCode :: enum DWORD {
		EXCEPTION_ACCESS_VIOLATION = 0xC0000005,
	}
	EXCEPTION_MAXIMUM_PARAMETERS :: 15
	EXCEPTION_RECORD :: struct {
		ExceptionCode:        ExceptionCode,
		ExceptionFlags:       DWORD,
		ExceptionRecord:      ^EXCEPTION_RECORD,
		ExceptionAddress:     rawptr,
		NumberParameters:     DWORD,
		ExceptionInformation: [EXCEPTION_MAXIMUM_PARAMETERS]ULONG_PTR,
	}
	CONTEXT :: struct {
		/* ... */
	}
	_EXCEPTION_POINTERS :: struct {
		ExceptionRecord: ^EXCEPTION_RECORD,
		ContextRecord:   ^CONTEXT,
	}
	TOP_LEVEL_EXCEPTION_FILTER :: proc "system" (exception: ^_EXCEPTION_POINTERS) -> ExceptionResult
	ExceptionResult :: enum CLONG {
		EXCEPTION_EXECUTE_HANDLER    = 1,
		EXCEPTION_CONTINUE_SEARCH    = 0,
		EXCEPTION_CONTINUE_EXECUTION = -1,
	}

	// flags
	AllocTypeFlags :: bit_set[enum {
		MEM_COMMIT   = 12,
		MEM_RESERVE  = 13,
		MEM_DECOMMIT = 14,
		MEM_RELEASE  = 15,
	};DWORD]
	AllocProtectFlags :: bit_set[enum {
		PAGE_READWRITE = 2,
	};DWORD]

	// procs
	foreign kernel32 {
		SetUnhandledExceptionFilter :: proc(filter_callback: TOP_LEVEL_EXCEPTION_FILTER) -> TOP_LEVEL_EXCEPTION_FILTER ---
		VirtualAlloc :: proc(address: rawptr, size: Size, type_flags: AllocTypeFlags, protect_flags: AllocProtectFlags) -> rawptr ---
		VirtualFree :: proc(address: rawptr, size: Size, type_flags: AllocTypeFlags) -> BOOL ---
	}
} else when ODIN_OS == .Linux {
	// flags
	AllocProtectFlags :: bit_set[enum {
		PROT_EXEC  = 0,
		PROT_READ  = 1,
		PROT_WRITE = 2,
	};CINT]
	AllocTypeFlags :: bit_set[enum {
		MAP_PRIVATE   = 1,
		MAP_ANONYMOUS = 5,
	};CINT]

	// procs
	mmap :: #force_inline proc "system" (
		address: rawptr,
		size: Size,
		protect_flags: AllocProtectFlags,
		type_flags: AllocTypeFlags,
		file: FileHandle = max(FileHandle),
		offset: uint = 0,
	) -> uintptr {
		return intrinsics.syscall(
			linux.SYS_mmap,
			uintptr(address),
			uintptr(size),
			uintptr(transmute(CINT)protect_flags),
			uintptr(transmute(CINT)type_flags),
			uintptr(file),
			uintptr(offset),
		)
	}
	munmap :: #force_inline proc(address: rawptr, size: Size) -> uintptr {
		return intrinsics.syscall(linux.SYS_munmap, uintptr(address), uintptr(size))
	}
} else {
	//#assert(false)
}

// ioring
when ODIN_OS == .Windows {
	// types
	IocpHandle :: distinct Handle
	OVERLAPPED :: struct {
		Internal:     ^CULONG,
		InternalHigh: ^CULONG,
		using _:      struct #raw_union {
			using _: struct {
				Offset:     DWORD,
				OffsetHigh: DWORD,
			},
			Pointer: rawptr,
		},
		hEvent:       Handle,
	}
	OVERLAPPED_COMPLETION_ROUTINE :: proc(error_code, bytes_transferred: DWORD, lpOverlapped: ^OVERLAPPED)
	TimerQueueHandle :: distinct Handle
	TimerHandle :: distinct Handle
	WAITORTIMERCALLBACK :: proc "system" (user_ptr: rawptr, TimerOrWaitFired: BOOL)

	// flags
	TimerFlags :: bit_set[enum {
		WT_EXECUTEONLYONCE = 3,
	};CULONG]

	// procs
	@(default_calling_convention = "c")
	foreign kernel32 {
		/* NOTE: Return the new `IocpHandle`, or `0` */
		CreateIoCompletionPort :: proc(file: Handle, existing_iocp: IocpHandle, completion_key: ULONG_PTR, max_threads: DWORD) -> IocpHandle ---
		PostQueuedCompletionStatus :: proc(iocp: IocpHandle, bytes_transferred: DWORD, completion_key: ULONG_PTR, overlapped: ^OVERLAPPED) -> BOOL ---
		GetQueuedCompletionStatus :: proc(iocp: IocpHandle, bytes_transferred: ^DWORD, completion_key: ^ULONG_PTR, overlapped: ^^OVERLAPPED, millis: DWORD) -> BOOL ---
		CreateTimerQueueTimer :: proc(timer: ^TimerHandle, timer_queue: TimerQueueHandle, timer_callback: WAITORTIMERCALLBACK, user_ptr: rawptr, timeout_ms, period_ms: DWORD, flags: TimerFlags) -> BOOL ---
		DeleteTimerQueueTimer :: proc(timer_queue: TimerQueueHandle, timer: TimerHandle, completion_event: Handle = 0) -> BOOL ---
		CancelIoEx :: proc(handle: Handle, overlapped: ^OVERLAPPED) -> BOOL ---
	}
} else when ODIN_OS == .Linux {
	// types
	EpollHandle :: distinct Handle
	EpollEventFlags :: bit_set[enum {
		EPOLLIN      = 0,
		EPOLLONESHOT = 30,
		EPOLLET      = 31,
	};CINT]
	EpollEvent :: struct {
		events: EpollEventFlags,
		data:   struct #raw_union {
			rawptr: rawptr,
			handle: Handle,
			u32:    u32,
			u64:    u64,
		},
	}
	TimerHandle :: distinct Handle
	TimeSpec64 :: struct {
		tv_sec:  i64,
		tv_nsec: i64,
	}
	TimerOptions64 :: struct {
		it_interval: TimeSpec64,
		it_value:    TimeSpec64,
	}

	// flags
	EpollFlags :: bit_set[enum {};CINT]
	EpollOp :: enum {
		EPOLL_CTL_ADD = 1,
		EPOLL_CTL_DEL = 2,
		EPOLL_CTL_MOD = 3,
	}
	ClockType :: enum {
		CLOCK_REALTIME  = 0,
		CLOCK_MONOTONIC = 1,
	}
	TimerFlags :: bit_set[enum {};CINT]

	// procs
	epoll_create1 :: #force_inline proc "system" (flags: EpollFlags) -> EpollHandle {
		result := intrinsics.syscall(linux.SYS_epoll_create1, uintptr(transmute(CINT)flags))
		return EpollHandle(result)
	}
	epoll_ctl :: #force_inline proc "system" (epoll: EpollHandle, op: CINT, fd: FileHandle, event: ^EpollEvent) -> int {
		return int(intrinsics.syscall(linux.SYS_epoll_ctl, uintptr(epoll), uintptr(op), uintptr(fd), uintptr(event)))
	}
	epoll_wait :: #force_inline proc "system" (epoll: EpollHandle, events: [^]EpollEvent, events_count: CINT, timeout := max(CINT)) -> int {
		return int(intrinsics.syscall(linux.SYS_epoll_wait, uintptr(epoll), uintptr(events), uintptr(events_count), uintptr(timeout)))
	}
	timerfd_create :: #force_inline proc "system" (type: ClockType, flags: TimerFlags) -> TimerHandle {
		return TimerHandle(intrinsics.syscall(linux.SYS_timerfd_create, uintptr(type), uintptr(transmute(CINT)flags)))
	}
	timerfd_settime64 :: #force_inline proc "system" (
		timer: TimerHandle,
		flags: TimerFlags,
		options: ^TimerOptions64,
		prev_options: ^TimerOptions64 = nil,
	) -> int {
		when IS_64BIT {
			syscall_id := linux.SYS_timerfd_settime
		} else {
			syscall_id := linux.SYS_timerfd_settime64
		}
		return int(intrinsics.syscall(syscall_id, uintptr(timer), uintptr(transmute(CINT)flags), uintptr(options), uintptr(prev_options)))
	}
} else {
	//#assert(false)
}

// file
when ODIN_OS == .Windows {
	// types
	FindFile :: distinct Handle

	// flags
	MoveFileFlags :: bit_set[enum {
		MOVEFILE_REPLACE_EXISTING = 0,
		MOVEFILE_WRITE_THROUGH    = 3,
	};DWORD]
	FileAccessFlags :: bit_set[enum {
		/* subset of `GENERIC_READ` */
		FILE_LIST_DIRECTORY = 0,
		GENERIC_ALL         = 28,
		GENERIC_EXECUTE     = 29,
		GENERIC_WRITE       = 30,
		GENERIC_READ        = 31,
	};DWORD]
	FileShareFlags :: bit_set[enum {
		FILE_SHARE_READ   = 0,
		FILE_SHARE_WRITE  = 1,
		/* delete and rename */
		FILE_SHARE_DELETE = 2,
	};DWORD]
	FileCreationType :: enum DWORD {
		Create                  = 1,
		CreateOrOpen            = 4,
		CreateOrOpenAndTruncate = 2,
		Open                    = 3,
		OpenAndTruncate         = 5,
	}
	FileCreationFlags :: bit_set[enum {
		FILE_ATTRIBUTE_DIRECTORY   = 4,
		FILE_ATTRIBUTE_NORMAL      = 7,
		FILE_FLAG_BACKUP_SEMANTICS = 25,
		FILE_FLAG_SEQUENTIAL_SCAN  = 27,
		FILE_FLAG_RANDOM_ACCESS    = 28,
		FILE_FLAG_NO_BUFFERING     = 29,
		FILE_FLAG_OVERLAPPED       = 30,
		FILE_FLAG_WRITE_THROUGH    = 31,
	};DWORD]

	// procs
	@(default_calling_convention = "c")
	foreign kernel32 {
		CreateDirectoryW :: proc(wdir_path: CWSTR, security: ^SECURITY_ATTRIBUTES) -> BOOL ---
		MoveFileExW :: proc(wsrc, wdest: CWSTR, flags: MoveFileFlags) -> BOOL ---
		FindFirstFileW :: proc(wfile_name: CWSTR, data: ^WIN32_FIND_DATAW) -> FindFile ---
		FindNextFileW :: proc(find: FindFile, data: ^WIN32_FIND_DATAW) -> BOOL ---
		FindClose :: proc(find: FindFile) -> BOOL ---

		/* Return the new `FileHandle`, `DirHandle`, or `INVALID_HANDLE` */
		CreateFileW :: proc(wfile_path: CWSTR, access_flags: FileAccessFlags, share_flags: FileShareFlags, security: ^SECURITY_ATTRIBUTES, creation_type: FileCreationType, creation_flags: FileCreationFlags, hTemplateFile: FileHandle = 0) -> FileHandle ---
		GetFileSizeEx :: proc(file: FileHandle, file_size: ^LARGE_INTEGER) -> BOOL ---
		ReadFile :: proc(file: FileHandle, buffer: [^]byte, bytes_to_read: DWORD, bytes_read: ^DWORD, overlapped: ^OVERLAPPED) -> BOOL ---
		WriteFile :: proc(file: FileHandle, buffer: [^]byte, bytes_to_write: DWORD, bytes_written: ^DWORD, overlapped: ^OVERLAPPED) -> BOOL ---
		FlushFileBuffers :: proc(file: FileHandle) -> BOOL ---
	}
} else when ODIN_OS == .Linux {
	// types
	FileMode :: CUINT
	Dirent64Type :: enum u8 {
		Unknown         = 0,
		Pipe            = 1,
		CharacterDevice = 2,
		Dir             = 4,
		BlockDevice     = 6,
		File            = 8,
		Link            = 10,
		Socket          = 12,
		Whiteout        = 14,
	}
	Dirent64 :: struct {
		inode:      i64,
		_internal:  i64 `fmt:"-"`,
		size:       CUSHORT,
		type:       Dirent64Type,
		cfile_name: [1]byte,
	}

	// flags
	AT_FDCWD :: transmute(DirHandle)(i32(-100))
	FileFlags :: bit_set[enum {
		O_WRONLY    = 0,
		O_RDWR      = 1,
		/* create if not exists */
		O_CREAT     = 6,
		/* don't open */
		O_EXCL      = 7,
		/* truncate */
		O_TRUNC     = 9,
		O_DIRECTORY = 16,
	};CINT]

	// procs
	mkdir :: #force_inline proc(dir_path: cstring, mode: FileMode = 0o755) -> int {
		result := intrinsics.syscall(linux.SYS_mkdir, transmute(uintptr)dir_path, uintptr(mode))
		return int(result)
	}
	renameat2 :: #force_inline proc(src_dir: DirHandle, src_path: cstring, dest_dir: DirHandle, dest_path: cstring, flags: CUINT = 0) -> int {
		result := intrinsics.syscall(
			linux.SYS_renameat2,
			uintptr(src_dir),
			transmute(uintptr)src_path,
			uintptr(dest_dir),
			transmute(uintptr)dest_path,
			uintptr(flags),
		)
		return int(result)
	}
	get_directory_entries_64b :: #force_inline proc "system" (file: DirHandle, buffer: [^]byte, buffer_size: int) -> int {
		result := intrinsics.syscall(linux.SYS_getdents64, uintptr(file), uintptr(buffer), uintptr(buffer_size))
		return int(result)
	}
	/* Return the new `FileHandle`, `DirHandle`, or `INVALID_HANDLE` */
	open :: #force_inline proc "system" (path: cstring, flags: FileFlags = {}, mode: FileMode = 0o755) -> FileHandle {
		result := intrinsics.syscall(linux.SYS_open, transmute(uintptr)path, uintptr(transmute(CINT)flags), uintptr(mode))
		return FileHandle(result)
	}
	read :: #force_inline proc "system" (file: FileHandle, buffer: [^]byte, buffer_size: int) -> int {
		result := intrinsics.syscall(linux.SYS_read, uintptr(file), uintptr(buffer), uintptr(buffer_size))
		return int(result)
	}
	write :: #force_inline proc "system" (file: FileHandle, buffer: [^]byte, buffer_size: int) -> int {
		result := intrinsics.syscall(linux.SYS_write, uintptr(file), uintptr(buffer), uintptr(buffer_size))
		return int(result)
	}
	fsync :: #force_inline proc "system" (file: FileHandle) -> int {
		result := intrinsics.syscall(linux.SYS_fsync, uintptr(file))
		return int(result)
	}
	fdatasync :: #force_inline proc "system" (file: FileHandle) -> int {
		result := intrinsics.syscall(linux.SYS_fdatasync, uintptr(file))
		return int(result)
	}
} else {
	//#assert(false)
}

// dir
when ODIN_OS == .Windows {
	// types
	FILE_NOTIFY_INFORMATION :: struct {
		next_entry_offset: DWORD,
		action:            DWORD,
		file_name_length:  DWORD,
		file_name:         [1]u16,
	}
	WIN32_FIND_DATAW :: struct {
		dwFileAttributes:   FileCreationFlags,
		ftCreationTime:     FILETIME,
		ftLastAccessTime:   FILETIME,
		ftLastWriteTime:    FILETIME,
		nFileSizeHigh:      DWORD,
		nFileSizeLow:       DWORD,
		dwReserved0:        DWORD,
		dwReserved1:        DWORD,
		/* worst api design ever? */
		cFileName:          [WINDOWS_MAX_PATH]u16,
		cAlternateFileName: [14]u16,
		/* Obsolete. Do not use */
		dwFileType:         DWORD,
		/* Obsolete. Do not use */
		dwCreatorType:      DWORD,
		/* Obsolete. Do not use */
		wFinderFlags:       WORD,
	}
	FILETIME :: struct {
		dwLowDateTime:  DWORD,
		dwHighDateTime: DWORD,
	}

	// flags
	FileNotifyFlags :: bit_set[enum {
		FILE_NOTIFY_CHANGE_FILE_NAME   = 0,
		FILE_NOTIFY_CHANGE_DIR_NAME    = 1,
		FILE_NOTIFY_CHANGE_ATTRIBUTES  = 2,
		FILE_NOTIFY_CHANGE_SIZE        = 3,
		FILE_NOTIFY_CHANGE_LAST_WRITE  = 4,
		FILE_NOTIFY_CHANGE_LAST_ACCESS = 5,
		FILE_NOTIFY_CHANGE_CREATION    = 6,
		FILE_NOTIFY_CHANGE_SECURITY    = 8,
	};DWORD]

	// procs
	@(default_calling_convention = "c")
	foreign kernel32 {
		ReadDirectoryChangesW :: proc(dir: DirHandle, buffer: [^]byte, buffer_len: DWORD, subtree: BOOL, filter: FileNotifyFlags, bytes_returned: ^DWORD, overlapped: ^OVERLAPPED, on_complete: ^OVERLAPPED_COMPLETION_ROUTINE) -> BOOL ---
	}
} else when ODIN_OS == .Linux {
	// types
	FanotifyHandle :: distinct Handle

	// flags
	FanotifyClass :: enum {
		FAN_CLASS_NOTIF = 0x0,
	}
	FanotifyInitFlags :: bit_set[enum {
		FAN_NONBLOCK = 1,
	};CUINT]
	FanotifyInitEventFlags :: bit_set[enum {};CUINT]
	FanotifyMarkFlags :: bit_set[enum {
		FAN_MARK_ADD    = 0,
		FAN_MARK_REMOVE = 1,
		/* include subdirectories */
		FAN_MARK_MOUNT  = 4,
	};CUINT]
	FanotifyMarkMask :: bit_set[enum {
		FAN_CLOSE_WRITE = 3,
	};u64]

	// procs
	fanotify_init :: #force_inline proc "system" (init_flags: FanotifyInitFlags, event_flags: FanotifyInitEventFlags) -> FanotifyHandle {
		result := intrinsics.syscall(linux.SYS_fanotify_init, uintptr(transmute(u32)init_flags), uintptr(transmute(u32)event_flags))
		return FanotifyHandle(result)
	}
	fanotify_mark :: #force_inline proc "system" (
		fanotify: FanotifyHandle,
		flags: FanotifyMarkFlags,
		mask: FanotifyMarkMask,
		dir: DirHandle,
		path: cstring,
	) -> int {
		result := intrinsics.syscall(
			linux.SYS_fanotify_mark,
			uintptr(fanotify),
			uintptr(transmute(CUINT)flags),
			uintptr(transmute(u64)mask),
			uintptr(dir),
			transmute(uintptr)path,
		)
		return int(result)
	}
} else {
	//#assert(false)
}

// socket
SOMAXCONN :: max(CINT) /* NOTE: for some reason it's not max(CUINT)... */
SOL_SOCKET :: CINT(max(u16)) /* NOTE: CINT used to be 16b... */
SO_UPDATE_ACCEPT_CONTEXT: CINT : 0x700B
INVALID_SOCKET :: max(SocketHandle)

when ODIN_OS == .Windows {
	// globals
	global_winsock: WinsockData

	// types
	GUID :: struct {
		Data1: DWORD,
		Data2: WORD,
		Data3: WORD,
		Data4: [8]BYTE,
	}
	WSABUF :: struct {
		len:    CULONG,
		buffer: [^]byte,
	}
	WinsockData :: struct {
		wVersion:       u16,
		wHighVersion:   u16,
		iMaxSockets:    u16,
		iMaxUdpDg:      u16,
		lpVendorInfo:   ^u8,
		szDescription:  [WSADESCRIPTION_LEN + 1]byte,
		szSystemStatus: [WSASYS_STATUS_LEN + 1]byte,
	}
	ACCEPT_EX :: proc(
		sListenSocket: SocketHandle,
		sAcceptSocket: SocketHandle,
		lpOutputBuffer: rawptr,
		dwReceiveDataLength: DWORD,
		dwLocalAddressLength: DWORD,
		dwRemoteAddressLength: DWORD,
		lpdwBytesReceived: ^DWORD,
		lpOverlapped: ^OVERLAPPED,
	) -> BOOL

	WSAOVERLAPPED_COMPLETION_ROUTINE :: proc(dwError, cbTransferred: DWORD, lpOverlapped: ^OVERLAPPED, dwFlags: DWORD)
	WSAPROTOCOL_INFOW :: struct {
		/* ... */
	}

	// flags
	WSADESCRIPTION_LEN :: 256
	WSASYS_STATUS_LEN :: 128

	IOC_WS2 :: 0x08000000
	IOC_OUT :: 0x40000000
	IOC_IN :: 0x80000000
	IOC_INOUT :: IOC_IN | IOC_OUT
	SIO_GET_EXTENSION_FUNCTION_POINTER :: IOC_INOUT | IOC_WS2 | 6

	WSASocketFlags :: bit_set[enum {
		WSA_FLAG_OVERLAPPED = 0,
	};DWORD]

	@(rodata)
	WSAID_ACCEPTEX := GUID{0xb5367df1, 0xcbac, 0x11cf, {0x95, 0xca, 0x00, 0x80, 0x5f, 0x48, 0xa1, 0x92}}
	@(rodata)
	WSAID_GETACCEPTEXSOCKADDRS := GUID{0xb5367df2, 0xcbac, 0x11cf, {0x95, 0xca, 0x00, 0x80, 0x5f, 0x48, 0xa1, 0x92}}
	@(rodata)
	WSAID_CONNECTX := GUID{0x25a207b9, 0xddf3, 0x4660, {0x8e, 0xe9, 0x76, 0xe5, 0x8c, 0x74, 0x06, 0x3e}}

	WinsockGroup :: enum CUINT {
		None                   = 0x0,
		SG_UNCONSTRAINED_GROUP = 0x1,
		SG_CONSTRAINED_GROUP   = 0x2,
	}

	// procs
	/* NOTE: WSAAPI is ignored on 64-bit windows */
	foreign import winsock_lib "system:Ws2_32.lib"
	@(default_calling_convention = "c")
	foreign winsock_lib {
		WSAStartup :: proc(requested_version: WORD, winsock: ^WinsockData) -> CINT ---
		WSAIoctl :: proc(socket: SocketHandle, control_code: DWORD, in_buf: rawptr, in_len: DWORD, out_buf: rawptr, out_len: DWORD, bytes_written: ^DWORD, overlapped: ^OVERLAPPED, on_complete: WSAOVERLAPPED_COMPLETION_ROUTINE) -> CINT ---

		/* TODO: only use WSASocketW() */
		/* Returns a new `SocketHandle`, or `INVALID_HANDLE` */
		WSASocketW :: proc(address_type: CINT, connection_type: SocketConnectionType, protocol: SocketProtocolType, protocol_info: ^WSAPROTOCOL_INFOW, group: WinsockGroup, flags: WSASocketFlags) -> SocketHandle ---
		bind :: proc(socket: SocketHandle, address: ^SocketAddress, address_size: CINT) -> CINT ---
		listen :: proc(socket: SocketHandle, max_connections: CINT) -> CINT ---

		setsockopt :: proc(socket: SocketHandle, level: CINT, optname: CINT, optval: rawptr, optlen: CINT) -> CINT ---
		WSARecv :: proc(socket: SocketHandle, buffers: ^WSABUF, buffer_count: DWORD, bytes_received: ^DWORD, flags: ^DWORD, overlapped: ^OVERLAPPED, on_complete: WSAOVERLAPPED_COMPLETION_ROUTINE) -> CINT ---
		closesocket :: proc(socket: SocketHandle) -> CINT ---

		WSAGetLastError :: proc() -> OsError ---
	}

	// types
	TRANSMIT_FILE_BUFFERS :: struct {
		head:        [^]byte,
		head_length: DWORD,
		tail:        [^]byte,
		tail_length: DWORD,
	}

	// flags
	TransmitFileFlags :: bit_set[enum {
		TF_DISCONNECT   = 0,
		TF_REUSE_SOCKET = 1,
	};DWORD]

	// procs
	foreign import winsock_ext_lib "system:Mswsock.lib"
	@(default_calling_convention = "c")
	foreign winsock_ext_lib {
		TransmitFile :: proc(socket: SocketHandle, file: FileHandle, bytes_to_write, bytes_per_send: DWORD, overlapped: ^OVERLAPPED, transmit_buffers: ^TRANSMIT_FILE_BUFFERS, flags: TransmitFileFlags) -> BOOL ---
	}
} else when ODIN_OS == .Linux {
	// procs
	socket :: #force_inline proc "system" (
		address_type: SocketAddressFamily,
		connection_type: SocketConnectionType,
		protocol: SocketProtocolType,
	) -> SocketHandle {
		result := intrinsics.syscall(linux.SYS_socket, uintptr(address_type), uintptr(connection_type))
		return SocketHandle(result)
	}
	bind :: #force_inline proc "system" (socket: SocketHandle, address: ^SocketAddress, address_size: CINT) -> CINT {
		assert_contextless(false)
		return 0
	}
	listen :: #force_inline proc "system" (socket: SocketHandle, max_connections: CINT) -> CINT {
		assert_contextless(false)
		return 0
	}
	closesocket :: #force_inline proc "system" (socket: SocketHandle) -> CINT {
		assert_contextless(false)
		return 0
	}
	setsockopt :: #force_inline proc "system" (socket: SocketHandle, level: CINT, optname: CINT, optval: rawptr, optlen: CINT) -> CINT {
		assert_contextless(false)
		return 0
	}
} else {
	//#assert(false)
}
