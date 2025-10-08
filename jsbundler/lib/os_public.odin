package lib

/* NOTE: linux uses 32 bit handles, so we can't use `nil` in Odin */
when ODIN_OS == .Windows {
	Handle :: distinct uintptr
} else when ODIN_OS == .Linux {
	Handle :: distinct CINT
} else {
	//#assert(false)
}
FileHandle :: distinct Handle
DirHandle :: distinct Handle
SocketHandle :: distinct Handle

INVALID_HANDLE :: max(Handle)

// socket
when ODIN_OS == .Windows {
	SocketAddressFamily :: enum u16 {
		Unknown  = 0,
		/* IPv4 */
		AF_INET  = 2,
		/* IPv6 */
		AF_INET6 = 23,
	}
} else when ODIN_OS == .Linux {
	SocketAddressFamily :: enum u16 {
		Unknown  = 0,
		/* IPv4 */
		AF_INET  = 2,
		/* IPv6 */
		AF_INET6 = 10,
	}
} else {
	//#assert(false)
}
SocketConnectionType :: enum CINT {
	SOCK_STREAM = 1,
	SOCK_DGRAM  = 2,
	SOCK_RAW    = 3,
}
/* www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml \
	IPv4 TCP = AF_INET + SOCK_STREAM + PROTOCOL_TCP \
	IPv4 UDP = AF_INET + SOCK_DGRAM + PROTOCOL_UDP \
	IPv4 ICMP = AF_INET + SOCK_RAW + IPPROTO_ICMP
*/
SocketProtocolType :: enum CINT {
	PROTOCOL_TCP = 6,
	PROTOCOL_UDP = 17,
	SOL_SOCKET   = CINT(max(u16)), /* NOTE: CINT used to be 16b... */
}

SocketAddress :: union {
	SocketAddressIpv4,
}
SocketAddressIpv4 :: struct {
	family:    SocketAddressFamily,
	port:      u16be,
	ip:        u32be `fmt:"#X"`,
	_reserved: [8]byte,
}
#assert(size_of(SocketAddressIpv4) == 16)
