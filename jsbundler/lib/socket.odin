package lib
import "base:intrinsics"
import "core:fmt"

Server :: struct {
	socket:    SocketHandle,
	address:   SocketAddress,
	ioring:    Ioring,
	user_data: rawptr,
	using _:   Server_OsFooter,
}
when ODIN_OS == .Windows {
	ClientAsyncBuffer :: struct {
		async_write_slice: TRANSMIT_FILE_BUFFERS,
		async_rw_slice:    WSABUF,
		async_rw_buffer:   [2048]byte `fmt:"-"`,
	}
} else when ODIN_OS == .Linux {
	ClientAsyncBuffer :: struct {
		async_write_slice: struct{},
		async_rw_slice:    struct{},
		async_rw_buffer:   [2048]byte `fmt:"-"`,
	}
} else {
	//#assert(false)
}
Client :: struct {
	using _:           Client_OsHeader `fmt:"-"`,
	ioring:            Ioring, /* NOTE: pointer to server.ioring */
	socket:            SocketHandle,
	address:           SocketAddress,
	state:             ClientState,
	timeout_timer:     TimerHandle,
	/* `FileHandle` or `INVALID_HANDLE` */
	async_write_file:  FileHandle,
	async_rw_prev_pos: int,
	async_rw_pos:      int,
	using _:           ClientAsyncBuffer `fmt:"-"`,
}
ClientState :: enum {
	New,
	Reading,
	SendingFileResponseAndClosing,
	ClosedByServerResponse,
	ClosedByClient,
	ClosedByTimeout,
	ClosedByServer,
}
when ODIN_OS == .Windows {
	Server_OsFooter :: struct {
		AcceptEx: ACCEPT_EX,
	}
	Client_OsHeader :: struct {
		/* NOTE: OVERLAPPED must be at the top, so you can cast it to ^Client, and must not be moved */
		overlapped: OVERLAPPED `fmt:"-"`,
	}
} else when ODIN_OS == .Linux {
	Server_OsFooter :: struct {}
	Client_OsHeader :: struct {}
} else {
	//#assert(false)
}

// NOTE: call this once per process
init_sockets :: proc() {
	when ODIN_OS == .Windows {
		WINSOCK_MAJOR_VERSION :: 2
		WINSOCK_MINOR_VERSION :: 2
		fmt.assertf(
			WSAStartup(WINSOCK_MAJOR_VERSION | (WINSOCK_MINOR_VERSION << 8), &global_winsock) == 0,
			"Failed to initialize Winsock %v.%v",
			WINSOCK_MAJOR_VERSION,
			WINSOCK_MINOR_VERSION,
		)
	} else when ODIN_OS == .Linux {
		/* noop */
	} else {
		assert(false)
	}
}
create_server_socket :: proc(server: ^Server, port: u16) {
	server.address = SocketAddressIpv4 {
		family = .AF_INET,
		ip     = u32be(0), // NOTE: 0.0.0.0
		port   = u16be(port),
	}
	when ODIN_OS == .Windows {
		server.socket = WSASocketW(CINT(SocketAddressFamily.AF_INET), .SOCK_STREAM, .PROTOCOL_TCP, nil, .None, {.WSA_FLAG_OVERLAPPED})
	} else when ODIN_OS == .Linux {
		server.socket = socket(.AF_INET, .SOCK_STREAM, .PROTOCOL_TCP)
	} else {
		assert(false)
	}
	fmt.assertf(server.socket != INVALID_SOCKET, "Failed to create a server socket")
	fmt.assertf(bind(server.socket, &server.address, size_of(SocketAddressIpv4)) == 0, "Failed to bind the server socket")
	fmt.assertf(listen(server.socket, SOMAXCONN) == 0, "Failed to listen to the server socket")
	when ODIN_OS == .Windows {
		fmt.assertf(CreateIoCompletionPort(Handle(server.socket), server.ioring, 0, 0) == server.ioring, "Failed to listen to the server socket via IOCP")
		bytes_written: u32 = 0
		fmt.assertf(
			WSAIoctl(
				server.socket,
				SIO_GET_EXTENSION_FUNCTION_POINTER,
				&WSAID_ACCEPTEX,
				size_of(WSAID_ACCEPTEX),
				&server.AcceptEx,
				size_of(server.AcceptEx),
				&bytes_written,
				nil,
				nil,
			) ==
			0,
			"Failed to setup async accept",
		)
	} else {
		assert(false)
	}
	return
}
accept_client_async :: proc(server: ^Server) {
	client := new(Client) // TODO: how does one allocate a nonzerod struct in Odin?
	client.ioring = server.ioring
	client.async_write_file = FileHandle(INVALID_HANDLE)

	when ODIN_OS == .Windows {
		client.socket = WSASocketW(CINT(SocketAddressFamily.AF_INET), .SOCK_STREAM, .PROTOCOL_TCP, nil, .None, {.WSA_FLAG_OVERLAPPED})
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
		fmt.assertf(ok == true || err == .ERROR_IO_PENDING, "Failed to accept asynchronously, err: %v", err)
	} else {
		assert(false)
	}
}
receive_client_data_async :: proc(client: ^Client) {
	when ODIN_OS == .Windows {
		client.async_rw_slice = {
			buffer = &client.async_rw_buffer[client.async_rw_pos],
			len    = u32(len(client.async_rw_buffer) - client.async_rw_pos),
		}
		flags: u32 = 0

		client.overlapped = {}
		has_error := WSARecv(client.socket, &client.async_rw_slice, 1, nil, &flags, &client.overlapped, nil)
		err := WSAGetLastError()
		fmt.assertf(has_error == 0 || err == .ERROR_IO_PENDING, "Failed to read data asynchronously, %v", err)
	} else {
		assert(false)
	}
}
/*_send_client_data_async :: proc(client: ^AsyncClient) {
	// TODO: send the response with WSASend(), but then we can't receive data (unless you allocate more overlappeds?)
} */
open_file_for_response :: proc(client: ^Client, file_path: string) -> (file_size: int, ok: bool) {
	file := FileHandle(INVALID_HANDLE)
	when ODIN_OS == .Windows {
		wfile_path := &tprint_string_as_wstring(file_path, allocator = context.allocator)[0]
		file = CreateFileW(wfile_path, {.GENERIC_READ}, {.FILE_SHARE_READ, .FILE_SHARE_WRITE}, nil, .Open, {.FILE_ATTRIBUTE_NORMAL, .FILE_FLAG_SEQUENTIAL_SCAN})
		win_file_size: LARGE_INTEGER = ---
		fmt.assertf(GetFileSizeEx(file, &win_file_size) == true, "Failed to get file size")
		file_size = int(win_file_size)
		ok = file != FileHandle(INVALID_HANDLE)
	} else {
		assert(false)
	}
	client.async_write_file = file
	return
}
send_file_response_and_close_client :: proc(client: ^Client, header: []byte) {
	// NOTE: don't overwrite if state == .ClosedXX
	old, _ := intrinsics.atomic_compare_exchange_strong(&client.state, .Reading, .SendingFileResponseAndClosing)
	if old == .ClosedByTimeout {return}
	fmt.assertf(old == .Reading, "Cannot send_response_and_close_client() twice on the same client")

	fmt.assertf(len(header) < len(client.async_rw_buffer), "len(header) must be < len(client.async_rw_buffer), got: %v", len(header))
	copy(header, client.async_rw_buffer[:])

	client.async_rw_prev_pos = 0
	client.async_rw_pos = 0
	client.async_rw_slice = {}
	when ODIN_OS == .Windows {
		client.async_write_slice = {
			head        = &client.async_rw_buffer[0],
			head_length = u32(len(header)),
		}
	} else {
		assert(false)
	}

	when ODIN_OS == .Windows {
		client.overlapped = {}
		ok := TransmitFile(client.socket, client.async_write_file, 0, 0, &client.overlapped, &client.async_write_slice, {.TF_DISCONNECT, .TF_REUSE_SOCKET})
		err := WSAGetLastError()
		fmt.assertf(ok == true || err == .ERROR_IO_PENDING, "Failed to send response, err: %v", err)
	} else {
		assert(false)
	}
}
cancel_timeout :: proc "system" (client: ^Client) {
	ioring_cancel_timer(client.ioring, &client.timeout_timer)
}
cancel_io_and_close_client :: proc "system" (client: ^Client) {
	when ODIN_OS == .Windows {
		CancelIoEx(Handle(client.socket), nil)
		close_client(client)
	} else {
		assert_contextless(false)
	}
}
close_client :: proc "system" (client: ^Client) {
	cancel_timeout(client)
	closesocket(client.socket)
	switch client.state {
	case .New, .Reading, .SendingFileResponseAndClosing:
		client.state = .ClosedByServer
	case .ClosedByClient, .ClosedByTimeout, .ClosedByServerResponse, .ClosedByServer:
	}
}
handle_socket_event :: proc(server: ^Server, event: ^IoringEvent) -> (client: ^Client) {
	client = (^Client)(event.user_data)
	switch event.error {
	case .None:
	case .IoCanceled:
		client.state = .ClosedByTimeout
	case .ConnectionClosedByOtherParty:
		client.state = .ClosedByClient
		close_client(client)
	}

	/* NOTE: iorings are badly designed... */
	TIMEOUT_COMPLETION_KEY :: 1
	TIMEOUT_MS :: 1000
	when ODIN_OS == .Windows {
		if event.completion_key == TIMEOUT_COMPLETION_KEY {
			client.state = .ClosedByTimeout
		}
	} else {
		//assert(false)
	}

	switch client.state {
	case .New:
		// accept a new connection
		when ODIN_OS == .Windows {
			result := CreateIoCompletionPort(Handle(client.socket), server.ioring, 0, 0)
			fmt.assertf(result != 0, "Failed to listen to the client socket with IOCP")
		} else {
			assert(false)
		}
		fmt.assertf(setsockopt(client.socket, SOL_SOCKET, SO_UPDATE_ACCEPT_CONTEXT, &server.socket, size_of(SocketHandle)) == 0, "Failed to set client params")
		/* NOTE: IOCP is badly designed, see ioring_set_timer_async() */
		on_timeout :: proc "system" (user_ptr: rawptr, _TimerOrWaitFired: b32) {
			when ODIN_OS == .Windows {
				client := (^Client)(user_ptr)
				PostQueuedCompletionStatus(client.ioring, 0, TIMEOUT_COMPLETION_KEY, &client.overlapped)
			} else {
				assert_contextless(false, "Shouldn't be necessary on other platforms")
			}
		}
		ioring_set_timer_async(server.ioring, &client.timeout_timer, TIMEOUT_MS, client, on_timeout)
	/* TODO: parse address via GetAcceptExSockaddrs()? */
	case .Reading:
		if event.bytes == 0 {
			// NOTE: presumably this means we're out of memory in the async_read_buffer?
			client.state = .ClosedByClient
			cancel_io_and_close_client(client)
		} else {
			client.async_rw_prev_pos = client.async_rw_pos
			client.async_rw_pos += int(event.bytes)
			break
		}
		fallthrough
	case .SendingFileResponseAndClosing:
		client.state = .ClosedByServerResponse
		close_client(client)
	case .ClosedByClient, .ClosedByTimeout, .ClosedByServerResponse:
	case .ClosedByServer:
		assert(false, "Race condition!")
	}
	return
}
