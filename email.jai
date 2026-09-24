
#load "system";

Imap_Message :: struct {
    id: s64;
    body: string;
    subject: string;
    from: string;
    // TODO(c4llv07e): Refactor header fields into separate struct.
}

Imap_Inbox :: struct {
    name: string;
    messages: [..]Imap_Message;
}

Imap_Account :: struct {
    connection: BIO;
    inboxes: [..]string;
}

Ctx :: struct {
}

using ctx: Ctx;

logic_render :: () {
}

logic_init :: () {
    SSL_library_init();
    ssl_ctx = SSL_CTX_new(TLS_client_method());
    sock := scket(AF_INET, SOCK_STREAM, 0);
    assert(sock != null, "Can't create socket");
    connect(sock, .{});
    ssl := SSL_new(ctx);
    SSL_set_fd(ssl, sock);
}

#import "Basic";
