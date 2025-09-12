package lib
import "base:intrinsics"
import "core:fmt"
import "core:mem"
import "core:strings"
import win "core:sys/windows"
import "core:time"

// params
WINSOCK_MAJOR_VERSION :: 2
WINSOCK_MINOR_VERSION :: 2

// constants
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

ADDRESS_TYPE_IPV4 :: 2
ADDRESS_TYPE_IPV6 :: 23

CONNECTION_TYPE_STREAM :: 1
CONNECTION_TYPE_DGRAM :: 2

PROTOCOL_TCP :: 6
PROTOCOL_UDP :: 17


// types
WAITORTIMERCALLBACK :: proc "std" (lpParam: win.PVOID, TimerOrWaitFired: win.BOOLEAN)
TRANSMIT_FILE_BUFFERS :: struct {
	head:        rawptr,
	head_length: u32,
	tail:        rawptr,
	tail_length: u32,
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

SocketAddress :: union {
	SocketAddressIpv4,
}
SocketAddressIpv4 :: struct {
	family:    u16,
	port:      u16be,
	ip:        u32be,
	_reserved: [8]byte,
}
#assert(size_of(SocketAddressIpv4) == 16)

Socket :: win.SOCKET
Server :: struct {
	socket:   Socket,
	address:  SocketAddress,
	iocp:     win.HANDLE,
	AcceptEx: win.LPFN_ACCEPTEX,
}
AsyncClient :: struct {
	// windows nonsense, NOTE: must be first field of struct
	overlapped:            win.OVERLAPPED `fmt:"-"`,
	address:               SocketAddress,
	socket:                Socket,
	timeout_timer:         win.HANDLE,
	state:                 AsyncClientState,
	server:                ^Server,
	// nil if we just accepted the connection
	async_rw_prev_pos:     int,
	async_rw_pos:          int,
	async_rw_slice:        win.WSABUF `fmt:"-"`,
	async_rw_buffer:       [4096]byte `fmt:"-"`, // TODO: set a better buffer size?
	async_write_file_path: win.wstring,
	async_write_file:      FileHandle,
	async_write_slice:     TRANSMIT_FILE_BUFFERS,
}
AsyncClientState :: enum {
	New,
	Open,
	SendingResponseAndClosing,
	ClosedByServerResponse,
	ClosedByClient,
	ClosedByTimeout,
	ClosedByServer,
}

// globals
@(private)
_winsock: WinsockData

// kernel32.lib imports
foreign import kernel32 "system:Kernel32.lib"
@(default_calling_convention = "c")
foreign winsock_lib {
	@(private)
	CreateTimerQueueTimer :: proc(timer: ^win.HANDLE, timer_queue: win.HANDLE, callback: WAITORTIMERCALLBACK, parameter: win.PVOID, timeout_ms, period_ms: i32, flags: u32) -> win.BOOL ---
	@(private)
	DeleteTimerQueueTimer :: proc(timer_queue: win.HANDLE, timer: win.HANDLE, event: win.HANDLE) ---
	@(private)
	CancelIoEx :: proc(handle: win.HANDLE, overlapped: win.LPOVERLAPPED) -> win.BOOL ---
}

// socket imports
// NOTE: WSAAPI is ignore on 64-bit windows
foreign import winsock_lib "system:Ws2_32.lib"
@(default_calling_convention = "c")
foreign winsock_lib {
	@(private)
	WSAStartup :: proc(requested_version: u16, winsock: ^WinsockData) -> i32 ---
	@(private)
	WSAIoctl :: proc(s: Socket, dwIoControlCode: u32, lpvInBuffer: rawptr, cbInBuffer: u32, lpvOutBuffer: rawptr, cbOutBuffer: u32, lpcbBytesReturned: ^u32, lpOverlapped: ^win.OVERLAPPED, lpCompletionRoutine: win.LPWSAOVERLAPPED_COMPLETION_ROUTINE) -> i32 ---

	@(private, link_name = "socket")
	winsock_socket :: proc(address_type, connection_type, protocol: i32) -> Socket ---
	@(private, link_name = "bind")
	winsock_bind :: proc(socket: Socket, address: ^SocketAddress, address_size: i32) -> i32 ---
	@(private, link_name = "listen")
	winsock_listen :: proc(socket: Socket, n: i32) -> i32 ---
	@(private, link_name = "closesocket")
	winsock_closesocket :: proc(socket: Socket) -> i32 ---
}

foreign import winsock_ext_lib "system:Mswsock.lib"
@(default_calling_convention = "c")
foreign winsock_ext_lib {
	@(private)
	TransmitFile :: proc(socket: Socket, file: FileHandle, bytes_to_write, bytes_per_send: u32, overlapped: win.LPOVERLAPPED, transmit_buffers: ^TRANSMIT_FILE_BUFFERS, flags: u32) -> win.BOOL ---
}

// socket procs
@(private)
_u32_from_le :: proc(a, b: u16) -> u16 {
	return a | (b << 8)
}
// NOTE: call this once per process
init_sockets :: proc() {
	fmt.assertf(
		WSAStartup(_u32_from_le(WINSOCK_MAJOR_VERSION, WINSOCK_MINOR_VERSION), &_winsock) == 0,
		"Failed to initialize Winsock %v.%v",
		WINSOCK_MAJOR_VERSION,
		WINSOCK_MINOR_VERSION,
	)
}
create_server_socket :: proc(server: ^Server, port: u16, thread_count := 1) {
	server.address = SocketAddressIpv4 {
		family = ADDRESS_TYPE_IPV4,
		ip     = u32be(0), // NOTE: 0.0.0.0
		port   = u16be(port),
	}
	server.socket = winsock_socket(ADDRESS_TYPE_IPV4, CONNECTION_TYPE_STREAM, PROTOCOL_TCP)
	fmt.assertf(server.socket != INVALID_SOCKET, "Failed to create a server socket")

	fmt.assertf(
		winsock_bind(server.socket, &server.address, size_of(SocketAddressIpv4)) == 0,
		"Failed to bind the server socket",
	)

	fmt.assertf(
		winsock_listen(server.socket, SOMAXCONN) == 0,
		"Failed to listen to the server socket",
	)

	server.iocp = win.CreateIoCompletionPort(win.INVALID_HANDLE_VALUE, nil, 0, 0)
	fmt.assertf(server.iocp != nil, "Failed to create an IOCP port")

	fmt.assertf(
		win.CreateIoCompletionPort(win.HANDLE(server.socket), server.iocp, 0, 0) == server.iocp,
		"Failed to listen to the server socket via IOCP",
	)

	accept_ex_guid := win.WSAID_ACCEPTEX
	bytes_written: u32 = 0
	fmt.assertf(
		WSAIoctl(
			server.socket,
			win.SIO_GET_EXTENSION_FUNCTION_POINTER,
			&accept_ex_guid,
			size_of(accept_ex_guid),
			&server.AcceptEx,
			size_of(server.AcceptEx),
			&bytes_written,
			nil,
			nil,
		) ==
		0,
		"Failed to setup async accept",
	)
	//fmt.printfln("bytes_written: %v", bytes_written)
	for i in 0 ..< thread_count {_accept_client_async(server)}
	return
}
@(private)
_accept_client_async :: proc(server: ^Server) {
	client := new(AsyncClient) // TODO: how does one allocate a nonzerod struct in Odin?
	client.socket = win.WSASocketW(
		ADDRESS_TYPE_IPV4,
		CONNECTION_TYPE_STREAM,
		PROTOCOL_TCP,
		nil,
		0,
		win.WSA_FLAG_OVERLAPPED,
	)
	fmt.assertf(client.socket != INVALID_SOCKET, "Failed to create a client socket")
	client.server = server
	bytes_received: u32 = ---
	//client.overlapped = {} // NOTE: AcceptEx() requires this to be zerod
	ok := server.AcceptEx(
		server.socket,
		client.socket,
		&client.async_rw_buffer[0],
		0,
		size_of(SocketAddressIpv4) + 16,
		size_of(SocketAddressIpv4) + 16,
		&bytes_received,
		&client.overlapped,
	)
	err := win.GetLastError()
	fmt.assertf(
		ok == true || err == win.ERROR_IO_PENDING,
		"Failed to accept asynchronously, err: %v",
		err,
	)
}
@(private)
_receive_client_data_async :: proc(client: ^AsyncClient) {
	client.async_rw_slice = {
		buf = &client.async_rw_buffer[client.async_rw_pos],
		len = u32(len(client.async_rw_buffer) - client.async_rw_pos),
	}
	flags: u32 = 0

	client.overlapped = {}
	has_error := win.WSARecv(
		client.socket,
		&client.async_rw_slice,
		1,
		nil,
		&flags,
		win.LPWSAOVERLAPPED(&client.overlapped),
		nil,
	)
	err := win.WSAGetLastError()
	fmt.assertf(
		has_error == 0 || err == win.WSA_IO_PENDING,
		"Failed to read data asynchronously, %v",
		err,
	)
}
@(private)
_send_client_data_async :: proc(client: ^AsyncClient) {
	// TODO: send the response with WSASend(), but then we can't receive data (unless you allocate more overlappeds?)
}
open_file_for_response :: proc(
	client: ^AsyncClient,
	file_path: string,
) -> (
	file: FileHandle,
	file_size: int,
	ok: bool,
) {
	client.async_write_file_path = _string_to_wstring(file_path, allocator = context.allocator)
	file = FileHandle(
		win.CreateFileW(
			client.async_write_file_path,
			win.GENERIC_READ,
			win.FILE_SHARE_READ | win.FILE_SHARE_WRITE,
			nil,
			win.OPEN_EXISTING,
			win.FILE_ATTRIBUTE_NORMAL | win.FILE_FLAG_SEQUENTIAL_SCAN,
			nil,
		),
	)
	client.async_write_file = file
	win_file_size: win.LARGE_INTEGER = ---
	fmt.assertf(
		win.GetFileSizeEx(win.HANDLE(file), &win_file_size) == true,
		"Failed to get file size",
	)
	file_size = int(win_file_size)
	ok = file != FileHandle(win.INVALID_HANDLE_VALUE)
	return
}
send_file_response_and_close_client :: proc(client: ^AsyncClient, header: []byte) {
	// NOTE: don't overwrite if state == .ClosedXX
	old, _ := intrinsics.atomic_compare_exchange_strong(
		&client.state,
		.Open,
		.SendingResponseAndClosing,
	)
	if old == .ClosedByTimeout {return}
	fmt.assertf(old == .Open, "Cannot send_response_and_close_client() twice on the same client")

	fmt.assertf(
		len(header) < len(client.async_rw_buffer),
		"len(header) must be < len(client.async_rw_buffer), got: %v",
		len(header),
	)
	mem.copy(&client.async_rw_buffer, raw_data(header), len(header))

	client.async_rw_prev_pos = 0
	client.async_rw_pos = 0
	client.async_rw_slice = {}
	client.async_write_slice = {
		head        = &client.async_rw_buffer,
		head_length = u32(len(header)),
	}

	client.overlapped = {}
	ok := TransmitFile(
		client.socket,
		client.async_write_file,
		0,
		0,
		&client.overlapped,
		&client.async_write_slice,
		TF_DISCONNECT | TF_REUSE_SOCKET,
	)
	err := win.WSAGetLastError()
	fmt.assertf(ok == true || err == win.WSA_IO_PENDING, "Failed to send response, err: %v", err)
}
cancel_timeout :: proc "std" (client: ^AsyncClient) {
	DeleteTimerQueueTimer(nil, client.timeout_timer, nil)
}
cancel_io_and_close_client :: proc "std" (client: ^AsyncClient) {
	CancelIoEx(win.HANDLE(client.socket), nil)
	close_client(client)
}
close_client :: proc "std" (client: ^AsyncClient) {
	winsock_closesocket(client.socket)
	cancel_timeout(client)
	switch client.state {
	case .New, .Open, .SendingResponseAndClosing:
		client.state = .ClosedByServer
	case .ClosedByClient, .ClosedByTimeout, .ClosedByServerResponse, .ClosedByServer:
	}
}
@(private)
_on_timeout :: proc "std" (lpParam: rawptr, _TimerOrWaitFired: win.BOOLEAN) {
	client := (^AsyncClient)(lpParam)
	if client.state == .Open {
		cancel_io_and_close_client(client) // NOTE: we call CancelIoEx(), which makes windows send a ERROR_OPERATION_ABORTED
	}
}
/* usage:
	for {
		client := wait_for_next_socket_event()
		defer handle_socket_event(client)
		switch client.state {...}
	}
*/
wait_for_next_socket_event :: proc(server: ^Server) -> (client: ^AsyncClient) {
	event_bytes: u32 = ---
	key: uint
	ok := win.GetQueuedCompletionStatus(
		server.iocp,
		&event_bytes,
		&key,
		(^^win.OVERLAPPED)(&client),
		win.INFINITE,
	)
	err := win.GetLastError()
	if !ok {
		switch err {
		case ERROR_CONNECTION_ABORTED:
			client.state = .ClosedByClient
			close_client(client)
		case ERROR_OPERATION_ABORTED:
			client.state = .ClosedByTimeout
		case:
			fmt.assertf(false, "Failed to get next socket event, err: %v", err)
		}
	}
	//fmt.printfln("state.1: %v, client: %v", client.state, client.socket)

	switch client.state {
	case .New:
		// accept a new connection
		fmt.assertf(
			win.CreateIoCompletionPort(win.HANDLE(client.socket), server.iocp, 0, 0) ==
			server.iocp,
			"Failed to listen to the client socket with IOCP",
		)
		fmt.assertf(
			win.setsockopt(
				client.socket,
				win.SOL_SOCKET,
				win.SO_UPDATE_ACCEPT_CONTEXT,
				rawptr(&server.socket),
				size_of(Socket),
			) ==
			0,
			"Failed to set client params",
		)
		fmt.assertf(
			CreateTimerQueueTimer(
				&client.timeout_timer,
				nil,
				_on_timeout,
				client,
				1000,
				0,
				WT_EXECUTEONLYONCE,
			) ==
			true,
			"Failed to set a timeout",
		)
	// TODO: parse address via GetAcceptExSockaddrs()?
	case .Open:
		//fmt.printfln("bytes_received: %v", event_bytes)
		if event_bytes == 0 {
			// NOTE: presumably this means we're out of memory in the async_read_buffer?
			client.state = .ClosedByClient
			cancel_io_and_close_client(client)
		} else {
			client.async_rw_prev_pos = client.async_rw_pos
			client.async_rw_pos += int(event_bytes)
			break
		}
		fallthrough
	case .SendingResponseAndClosing:
		client.state = .ClosedByServerResponse
		close_client(client)
	case .ClosedByClient, .ClosedByTimeout, .ClosedByServerResponse:
	case .ClosedByServer:
		assert(false, "Race condition!")
	}
	//fmt.printfln("state.2: %v", client.state)
	return
}
handle_socket_event :: proc(server: ^Server, client: ^AsyncClient) {
	//fmt.printfln("state.3: %v", client.state)
	switch client.state {
	case .New:
		client.state = .Open
		_receive_client_data_async(client)
		_accept_client_async(server)
	case .Open:
		_receive_client_data_async(client)
	case .SendingResponseAndClosing:
	// NOTE: handled by OS via TransmitFile()
	case .ClosedByClient, .ClosedByTimeout, .ClosedByServerResponse, .ClosedByServer:
		client.state = .ClosedByServer
		if client.async_write_file != nil {
			win.CloseHandle(win.HANDLE(client.async_write_file))
			free(rawptr(client.async_write_file_path))
		}
		free(client)
	}
}
