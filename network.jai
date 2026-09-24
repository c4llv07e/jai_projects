Socket_Family :: enum u16 {
	UNSPEC :: 0;
	LOCAL :: 1;
	UNIX :: 1;
	FILE :: 1;
	INET :: 2;
}

Socket_Type :: enum s32 {
	STREAM :: 1;
	DGRAM :: 2;
	RAW :: 3;
}

Socket_Protocol :: s32;

Socklen :: u32;

Sockaddr :: struct {
	family: Socket_Family;
}

Sockaddr_in :: struct {
#as using sockaddr: Sockaddr;
	family = .INET;
	port: u16;
	addr: u32;
	zero: u64; // I hate UNIX systems.
}

TCP_Connection :: s32;

resolve_address :: (host: string) -> u32, bool {
	addr, ok := parse_ipv4(host);
	if ok {
		return addr, true;
	}
	// 127.0.0.1
	return 0x0100007f, false;
}

host_to_network :: (val: u16) -> u16 {
	return ((val & 0xff) << 8) | ((val & 0xff00) >> 8);
}

host_to_network :: (val: u32) -> u32 {
	return ((val & 0x000000ff) << 24) |
	((val & 0x0000ff00) << 8)  |
	((val & 0x00ff0000) >> 8)  |
	((val & 0xff000000) >> 24);
}

parse_ipv4 :: (addr: string) -> u32, bool {
	octets := split(addr, cast(u8)#char ".");
	res: u32 = 0;
	for octets {
		res <<= 8;
		oct_val, ok, remainder := string_to_int(it, 10, u8);
		if !ok || remainder.count != 0 {
			return 0, false;
		}
		res += xx (oct_val);
	}
	return host_to_network(res), true;
}

connect :: (host: string, port: u16) -> TCP_Connection {
	sock := socket(.INET, .STREAM, 0);
	assert(sock >= 0, "Can't create socket for connection");
	sockaddr := Sockaddr_in.{
		port = host_to_network(port),
		addr = resolve_address(host),
	};
	print("%\n", size_of(Sockaddr_in));
	if sys_connect(sock, sockaddr, size_of(Sockaddr_in)) == -1 {
		log("Can't connect to the %\n", host);
		close(sock);
		return 0;
	}
	return sock;
}

send_string :: (conn: TCP_Connection, msg: $T) {
	write(conn, msg.data, xx msg.count); 
}

recv_string :: (conn: TCP_Connection) -> string { // Allocates in temporary buffer!
	res: string = talloc_string(4096);
	res.count = read(conn, res.data, xx res.count);
	return res;
}

main :: () {
	host := "1.1.1.1";
	port: u16 = 80;
	connection := connect(host, port);
	send_string(connection, tprint("GET / HTTP/1.0 \r\nHost: %:%\r\n\r\n", host, port));
	while true {
		msg := recv_string(connection);
		if msg.count == 0 break;
		print("Get msg: \"%\"\n", msg);
	}
}

#scope_file

socket :: (family: Socket_Family = .INET, type: Socket_Type = .STREAM, protocol: Socket_Protocol = 0) -> s32 {
	return xx syscall(41, xx family, xx type, xx protocol);
}

syscall :: (num: u64, args: ..u64) -> u64 #expand {
	result: u64;
	args_ptr := args.data;
#asm SYSCALL_SYSRET {
		mov.q rcx: gpr === c, 0;
		mov.q r11: gpr === 11, 0;
		mov.q rax: gpr === a, num;
		mov.q rdi: gpr === di, [args_ptr];
		mov.q rsi: gpr === si, [args_ptr + 8];
		mov.q rdx: gpr === d, [args_ptr + 16];
		mov.q r10: gpr === 10, [args_ptr + 24];
		mov.q r8: gpr === 8, [args_ptr + 32];
		mov.q r9: gpr === 9, [args_ptr + 36];
		syscall rcx, r11, rax, rdi, rsi, rdx, r10, r8, r9;
		mov.q result, rax;
	}
	return result;
}

read :: (fd: s32, buffer: *u8, size: u64) -> s64 {
	return xx syscall(0, xx fd, xx buffer, xx size);
}

write :: (fd: s32, buffer: *u8, size: u64) -> s64 {
	return xx syscall(1, xx fd, xx buffer, xx size);
}

close :: (fd: s32) -> s32 {
	return xx syscall(3, xx fd);
}

sys_connect :: (fd: s32, addr: *Sockaddr, addrlen: Socklen) -> s32 {
	return xx syscall(42, xx fd, xx addr, xx addrlen);
}

#import "String";
#import "File";
#import "Basic";