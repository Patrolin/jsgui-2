package lib
// io_uring + io_uring_prep_accept()

/*
IORing :: struct {}
Socket :: struct {}
make_io_ring :: proc() -> IORing {
	// ...
}
queue_socket_accept :: proc(ioring: ^IORing) -> Socket {
	// ...
}
queue_socket_read :: proc(ioring: ^IORing, buffer: []byte) {
	// ...
}
queue_socket_write :: proc(ioring: ^IORing, buffer: []byte) {
	// ...
}
queue_socket_close :: proc(ioring: ^IORing, socket: Socket) {
	// ...
}
*/
