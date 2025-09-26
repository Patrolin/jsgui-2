package lib
import "base:intrinsics"
import "core:fmt"

// params
WINSOCK_MAJOR_VERSION :: 2
WINSOCK_MINOR_VERSION :: 2

// types
Socket :: SOCKET
Server :: struct {
	socket:   Socket,
	address:  SocketAddress,
	iocp:     HANDLE,
	AcceptEx: ACCEPT_EX,
}
AsyncClient :: struct {
	// windows nonsense, NOTE: must be first field of struct
	overlapped:            OVERLAPPED `fmt:"-"`,
	socket:                Socket,
	address:               SocketAddress,
	state:                 AsyncClientState,
	timeout_timer:         HANDLE,
	async_write_file_path: CWSTR,
	async_write_file:      FileHandle,
	async_write_slice:     TRANSMIT_FILE_BUFFERS `fmt:"-"`,
	async_rw_prev_pos:     int,
	async_rw_pos:          int,
	async_rw_slice:        WSABUF `fmt:"-"`,
	async_rw_buffer:       [2048]byte `fmt:"-"`,
}
AsyncClientState :: enum {
	New,
	Reading,
	SendingResponseAndClosing,
	ClosedByServerResponse,
	ClosedByClient,
	ClosedByTimeout,
	ClosedByServer,
}

// NOTE: call this once per process
init_sockets :: proc() {
	fmt.assertf(
		WSAStartup(WINSOCK_MAJOR_VERSION | (WINSOCK_MINOR_VERSION << 8), &_winsock) == 0,
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
	server.socket = socket(ADDRESS_TYPE_IPV4, CONNECTION_TYPE_STREAM, PROTOCOL_TCP)
	fmt.assertf(server.socket != INVALID_SOCKET, "Failed to create a server socket")

	fmt.assertf(
		bind(server.socket, &server.address, size_of(SocketAddressIpv4)) == 0,
		"Failed to bind the server socket",
	)

	fmt.assertf(listen(server.socket, SOMAXCONN) == 0, "Failed to listen to the server socket")

	server.iocp = CreateIoCompletionPort(INVALID_HANDLE, nil, 0, 0)
	fmt.assertf(server.iocp != nil, "Failed to create an IOCP port")

	fmt.assertf(
		CreateIoCompletionPort(HANDLE(server.socket), server.iocp, 0, 0) == server.iocp,
		"Failed to listen to the server socket via IOCP",
	)

	accept_ex_guid := WSAID_ACCEPTEX
	bytes_written: u32 = 0
	fmt.assertf(
		WSAIoctl(
			server.socket,
			SIO_GET_EXTENSION_FUNCTION_POINTER,
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
	for i in 0 ..< thread_count {_accept_client_async(server)}
	return
}
@(private)
_accept_client_async :: proc(server: ^Server) {
	client := new(AsyncClient) // TODO: how does one allocate a nonzerod struct in Odin?
	client.socket = WSASocketW(
		ADDRESS_TYPE_IPV4,
		CONNECTION_TYPE_STREAM,
		PROTOCOL_TCP,
		nil,
		0,
		WSA_FLAG_OVERLAPPED,
	)
	fmt.assertf(client.socket != INVALID_SOCKET, "Failed to create a client socket")
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
	err := GetLastError()
	fmt.assertf(
		ok == true || err == ERROR_IO_PENDING,
		"Failed to accept asynchronously, err: %v",
		err,
	)
}
@(private)
_receive_client_data_async :: proc(client: ^AsyncClient) {
	client.async_rw_slice = {
		buffer = &client.async_rw_buffer[client.async_rw_pos],
		len    = u32(len(client.async_rw_buffer) - client.async_rw_pos),
	}
	flags: u32 = 0

	client.overlapped = {}
	has_error := WSARecv(
		client.socket,
		&client.async_rw_slice,
		1,
		nil,
		&flags,
		&client.overlapped,
		nil,
	)
	err := WSAGetLastError()
	fmt.assertf(
		has_error == 0 || err == WSA_IO_PENDING,
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
	client.async_write_file_path = tprint_string_as_wstring(
		file_path,
		allocator = context.allocator,
	)
	file = FileHandle(
		CreateFileW(
			client.async_write_file_path,
			GENERIC_READ,
			FILE_SHARE_READ | FILE_SHARE_WRITE,
			nil,
			F_OPEN,
			FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
			nil,
		),
	)
	client.async_write_file = file
	win_file_size: LARGE_INTEGER = ---
	fmt.assertf(GetFileSizeEx(file, &win_file_size) == true, "Failed to get file size")
	file_size = int(win_file_size)
	ok = file != FileHandle(INVALID_HANDLE)
	return
}
send_file_response_and_close_client :: proc(client: ^AsyncClient, header: []byte) {
	// NOTE: don't overwrite if state == .ClosedXX
	old, _ := intrinsics.atomic_compare_exchange_strong(
		&client.state,
		.Reading,
		.SendingResponseAndClosing,
	)
	if old == .ClosedByTimeout {return}
	fmt.assertf(
		old == .Reading,
		"Cannot send_response_and_close_client() twice on the same client",
	)

	fmt.assertf(
		len(header) < len(client.async_rw_buffer),
		"len(header) must be < len(client.async_rw_buffer), got: %v",
		len(header),
	)
	copy_slow(raw_data(header), len(header), &client.async_rw_buffer)

	client.async_rw_prev_pos = 0
	client.async_rw_pos = 0
	client.async_rw_slice = {}
	client.async_write_slice = {
		head        = &client.async_rw_buffer[0],
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
	err := WSAGetLastError()
	fmt.assertf(ok == true || err == WSA_IO_PENDING, "Failed to send response, err: %v", err)
}
cancel_timeout :: proc "std" (client: ^AsyncClient) {
	DeleteTimerQueueTimer(nil, client.timeout_timer, nil)
}
cancel_io_and_close_client :: proc "std" (client: ^AsyncClient) {
	CancelIoEx(HANDLE(client.socket), nil)
	close_client(client)
}
close_client :: proc "std" (client: ^AsyncClient) {
	closesocket(client.socket)
	cancel_timeout(client)
	switch client.state {
	case .New, .Reading, .SendingResponseAndClosing:
		client.state = .ClosedByServer
	case .ClosedByClient, .ClosedByTimeout, .ClosedByServerResponse, .ClosedByServer:
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
	user_ptr: rawptr
	ok := GetQueuedCompletionStatus(
		server.iocp,
		&event_bytes,
		&user_ptr,
		(^^OVERLAPPED)(&client),
		INFINITE,
	)
	err := GetLastError()
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

	on_timeout :: proc "std" (user_ptr: rawptr, _TimerOrWaitFired: BOOL) {
		client := (^AsyncClient)(user_ptr)
		if client.state == .Reading {
			cancel_io_and_close_client(client) // NOTE: we call CancelIoEx(), which makes windows send an ERROR_OPERATION_ABORTED
		}
	}
	switch client.state {
	case .New:
		// accept a new connection
		fmt.assertf(
			CreateIoCompletionPort(HANDLE(client.socket), server.iocp, 0, 0) == server.iocp,
			"Failed to listen to the client socket with IOCP",
		)
		fmt.assertf(
			setsockopt(
				client.socket,
				SOL_SOCKET,
				SO_UPDATE_ACCEPT_CONTEXT,
				&server.socket,
				size_of(Socket),
			) ==
			0,
			"Failed to set client params",
		)
		fmt.assertf(
			CreateTimerQueueTimer(
				&client.timeout_timer,
				nil,
				on_timeout,
				client,
				1000,
				0,
				WT_EXECUTEONLYONCE,
			) ==
			true,
			"Failed to set a timeout",
		)
	// TODO: parse address via GetAcceptExSockaddrs()?
	case .Reading:
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
	return
}
handle_socket_event :: proc(server: ^Server, client: ^AsyncClient) {
	// TODO: move this to user code?
	switch client.state {
	case .New:
		client.state = .Reading
		_receive_client_data_async(client)
		_accept_client_async(server)
	case .Reading:
		_receive_client_data_async(client)
	case .SendingResponseAndClosing:
	// NOTE: handled by OS via TransmitFile()
	case .ClosedByClient, .ClosedByTimeout, .ClosedByServerResponse, .ClosedByServer:
		client.state = .ClosedByServer
		if client.async_write_file != nil {
			CloseHandle(HANDLE(client.async_write_file))
			free(rawptr(client.async_write_file_path))
		}
		free(client)
	}
}
