#+private package
package lib

import "base:intrinsics"
import "base:runtime"
// constants
HANDLE :: distinct rawptr

CP_UTF8 :: 65001
WC_ERR_INVALID_CHARS :: 0x80

WT_EXECUTEONLYONCE :: 0x8
TF_DISCONNECT :: 0x1
TF_REUSE_SOCKET :: 0x2

WSADESCRIPTION_LEN :: 256
WSASYS_STATUS_LEN :: 128
SOMAXCONN :: max(i32)
INVALID_SOCKET :: max(Socket)
SOCKET_ERROR :: -1
ERROR_CONNECTION_ABORTED :: 1236
ERROR_OPERATION_ABORTED :: 995

// types
PVOID :: rawptr
PSTR :: [^]byte
PCSTR :: cstring
PCWSTR :: cstring16
BOOL :: b32
BYTE :: u8
WORD :: u16
DWORD :: u32
QWORD :: u64
/* c types */
SHORT :: i16
USHORT :: u16
INT :: i32
UINT :: u32
LONG :: i32
ULONG :: u32
LONGLONG :: i64
ULONGLONG :: u64
/* -c types */
SECURITY_ATTRIBUTES :: struct {
	nLength:              DWORD,
	lpSecurityDescriptor: PVOID,
	bInheritHandle:       BOOL,
}
OVERLAPPED :: struct {
	Internal:     ^ULONG,
	InternalHigh: ^ULONG,
	using _:      struct #raw_union {
		using _: struct {
			Offset:     DWORD,
			OffsetHigh: DWORD,
		},
		Pointer: rawptr,
	},
	hEvent:       HANDLE,
}
LPWSAOVERLAPPED_COMPLETION_ROUTINE :: proc(
	dwError, cbTransferred: DWORD,
	lpOverlapped: ^OVERLAPPED,
	dwFlags: DWORD,
)

// Kernel32.lib procs
foreign import kernel32 "system:Kernel32.lib"
@(default_calling_convention = "c")
foreign kernel32 {
	// helper procs
	WideCharToMultiByte :: proc(CodePage: UINT, dwFlags: DWORD, lpWideCharStr: PCWSTR, cchWideChar: INT, lpMultiByteStr: PSTR, cbMultiByte: INT, lpDefaultChar: PCSTR, lpUsedDefaultChar: ^BOOL) -> INT ---
	// process procs
	GetCommandLineW :: proc() -> PCWSTR ---
	ExitProcess :: proc(uExitCode: UINT) ---
	// file procs
	CreateFileW :: proc(lpFileName: PCWSTR, dwDesiredAccess: DWORD, dwShareMode: DWORD, lpSecurityAttributes: ^SECURITY_ATTRIBUTES, dwCreationDisposition: DWORD, dwFlagsAndAttributes: DWORD, hTemplateFile: HANDLE) -> HANDLE ---
	// IOCP procs
	CreateTimerQueueTimer :: proc(timer: ^HANDLE, timer_queue: HANDLE, callback: WAITORTIMERCALLBACK, parameter: PVOID, timeout_ms, period_ms: DWORD, flags: ULONG) -> BOOL ---
	DeleteTimerQueueTimer :: proc(timer_queue: HANDLE, timer: HANDLE, event: HANDLE) ---
	CancelIoEx :: proc(handle: HANDLE, overlapped: ^OVERLAPPED) -> BOOL ---
}

// socket imports
// NOTE: WSAAPI is ignored on 64-bit windows
foreign import winsock_lib "system:Ws2_32.lib"
@(default_calling_convention = "c")
foreign winsock_lib {
	@(private)
	WSAStartup :: proc(requested_version: WORD, winsock: ^WinsockData) -> INT ---
	@(private)
	WSAIoctl :: proc(s: Socket, dwIoControlCode: DWORD, lpvInBuffer: rawptr, cbInBuffer: DWORD, lpvOutBuffer: PVOID, cbOutBuffer: DWORD, lpcbBytesReturned: ^DWORD, lpOverlapped: ^OVERLAPPED, lpCompletionRoutine: LPWSAOVERLAPPED_COMPLETION_ROUTINE) -> INT ---

	@(private, link_name = "socket")
	winsock_socket :: proc(address_type, connection_type, protocol: INT) -> Socket ---
	@(private, link_name = "bind")
	winsock_bind :: proc(socket: Socket, address: ^SocketAddress, address_size: INT) -> INT ---
	@(private, link_name = "listen")
	winsock_listen :: proc(socket: Socket, max_connections: INT) -> INT ---
	@(private, link_name = "closesocket")
	winsock_closesocket :: proc(socket: Socket) -> INT ---
}

foreign import winsock_ext_lib "system:Mswsock.lib"
@(default_calling_convention = "c")
foreign winsock_ext_lib {
	@(private)
	TransmitFile :: proc(socket: Socket, file: FileHandle, bytes_to_write, bytes_per_send: u32, overlapped: ^OVERLAPPED, transmit_buffers: ^TRANSMIT_FILE_BUFFERS, flags: u32) -> BOOL ---
}

// helper procs
_tprint_cstring16 :: proc(
	wcstr: cstring16,
	wstr_len: i32 = -1,
	allocator := context.temp_allocator,
) -> string {
	if intrinsics.expect(wstr_len == 0, false) {return ""}

	str_len := WideCharToMultiByte(
		CP_UTF8,
		WC_ERR_INVALID_CHARS,
		wcstr,
		wstr_len,
		nil,
		0,
		nil,
		nil,
	)
	assert(str_len != 0) // NOTE: Windows can return 0 if wstr_len == 0, otherwise it counts the null terminator and thus returns >0
	if wstr_len == -1 {str_len -= 1}
	if intrinsics.expect(str_len == 0, false) {return ""}

	str_buf, err := make([^]byte, str_len, allocator = allocator)
	assert(err == nil)
	written_bytes := WideCharToMultiByte(
		CP_UTF8,
		WC_ERR_INVALID_CHARS,
		wcstr,
		wstr_len,
		str_buf,
		str_len,
		nil,
		nil,
	)
	assert(written_bytes == str_len)

	return transmute(string)(str_buf[:str_len])
}
_tprint_string16 :: proc(wstr: string16, allocator := context.temp_allocator) -> string {
	wcstr := transmute(cstring16)(raw_data(wstr))
	wlen := len(wstr)
	wlen_i32 := i32(wlen)
	assert(int(wlen_i32) == wlen)
	return _tprint_cstring16(wcstr, wlen_i32, allocator = allocator)
}
_tprint_wstring :: proc {
	_tprint_cstring16,
	_tprint_string16,
}
_tprint_string_as_wstring :: proc(str: string, allocator := context.temp_allocator) -> cstring16 {
	/* TODO: print null terminated wstring and return a slice to it
	MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, cstr, i32(len(s)), nil, 0)
	MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, cstr, i32(len(s)), raw_data(text), n)
	*/

	return win.utf8_to_wstring(str, allocator = allocator)
}
