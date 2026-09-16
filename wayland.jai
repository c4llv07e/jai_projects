#import "POSIX";
#import "Linux";
#import "Socket";

sockaddr_un :: struct {
    sun_family: sa_family_t;
    sun_path: [108] u8;
};

Wayland_Connection :: struct {
    free_id : u32 = 2;
    fd : Socket;
};

wayland_connect :: () -> Wayland_Connection {
    conn : Wayland_Connection;
    using conn;
    // TODO(c4llv07e): Make proper socket path.
    sock_path := "/var/run/runtime-0/wayland-1";
    fd = socket(AF_UNIX, SOCK.STREAM, 0);
    if fd < 0 {
        print("Can't create socket!\n");
        return .{};
    }
    addr := sockaddr_un.{
        sun_family = AF_UNIX,
    };
    memcpy(*addr.sun_path, sock_path.data, sock_path.count);
    if connect(fd, cast(*sockaddr) *addr, size_of(type_of(addr))) < 0 {
        print("Can't connect to the wayland socket!\n");
        return .{};
    }
    return conn;
};
