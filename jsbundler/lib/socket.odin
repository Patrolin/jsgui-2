package lib

// constants
ADDRESS_TYPE_IPV4 :: 2
ADDRESS_TYPE_IPV6 :: 23

CONNECTION_TYPE_STREAM :: 1
CONNECTION_TYPE_DGRAM :: 2

PROTOCOL_TCP :: 6
PROTOCOL_UDP :: 17

// types
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
