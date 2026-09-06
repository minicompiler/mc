// std.Io.net accept loop (Zig 0.16 Io API, the default Threaded Io from
// std.process.Init), one OS thread per connection, keep-alive: the thread loops
// reading requests until the client closes.
const std = @import("std");
const Io = std.Io;

const RESP = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nhello, world\n";
const RESP_KA = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\nConnection: keep-alive\r\n\r\nhello, world\n";
const RESP_CLOSE = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\nConnection: close\r\n\r\nhello, world\n";

fn hasCi(hay: []const u8, needle: []const u8) bool {
    if (hay.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= hay.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(hay[i .. i + needle.len], needle)) return true;
    }
    return false;
}

// the keep-alive decision as net/http and Kestrel make it: HTTP/1.1 stays open
// unless `Connection: close`; HTTP/1.0 (what ab speaks) closes unless
// `Connection: keep-alive`, which is echoed back.
fn choose(req: []const u8) struct { []const u8, bool } {
    if (hasCi(req, "HTTP/1.0")) {
        if (hasCi(req, "keep-alive")) return .{ RESP_KA, true };
        return .{ RESP_CLOSE, false };
    }
    if (hasCi(req, "connection: close")) return .{ RESP_CLOSE, false };
    return .{ RESP, true };
}

fn handle(io: Io, stream: Io.net.Stream) void {
    defer stream.close(io);
    var buf: [8192]u8 = undefined;
    var r = stream.reader(io, &.{});
    var w = stream.writer(io, &.{});
    while (true) {
        var n: usize = 0;
        const ok = blk: {
            while (true) {
                if (n >= 4 and std.mem.indexOf(u8, buf[0..n], "\r\n\r\n") != null) break :blk true;
                if (n >= buf.len) break :blk false;
                var data: [1][]u8 = .{buf[n..]};
                const k = r.interface.readVec(&data) catch break :blk false;
                if (k == 0) break :blk false;
                n += k;
            }
        };
        if (!ok) return;
        const resp, const keep = choose(buf[0..n]);
        w.interface.writeAll(resp) catch return;
        w.interface.flush() catch return;
        if (!keep) return;
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var args = init.minimal.args.iterate();
    _ = args.next();
    const port_s = args.next() orelse return error.Usage;
    const port = try std.fmt.parseInt(u16, port_s, 10);
    const addr = try Io.net.IpAddress.parseIp4("127.0.0.1", port);
    var server = try addr.listen(io, .{ .reuse_address = true, .kernel_backlog = 128 });
    defer server.deinit(io);
    while (true) {
        const stream = server.accept(io) catch continue;
        const t = std.Thread.spawn(.{}, handle, .{ io, stream }) catch {
            stream.close(io);
            continue;
        };
        t.detach();
    }
}
