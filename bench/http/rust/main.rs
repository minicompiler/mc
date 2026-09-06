// std::net blocking, one OS thread per connection, keep-alive: the thread loops
// reading requests until the client closes. No external crates.
use std::io::{Read, Write};
use std::net::TcpListener;
use std::thread;

const RESP: &[u8] = b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nhello, world\n";
const RESP_KA: &[u8] = b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\nConnection: keep-alive\r\n\r\nhello, world\n";
const RESP_CLOSE: &[u8] = b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\nConnection: close\r\n\r\nhello, world\n";

fn has_ci(hay: &[u8], needle: &[u8]) -> bool {
    hay.windows(needle.len()).any(|w| w.eq_ignore_ascii_case(needle))
}

// the keep-alive decision as net/http and Kestrel make it: HTTP/1.1 stays open
// unless `Connection: close`; HTTP/1.0 (what ab speaks) closes unless
// `Connection: keep-alive`, which is echoed back. Returns (response, keep_open).
fn choose(req: &[u8]) -> (&'static [u8], bool) {
    if has_ci(req, b"HTTP/1.0") {
        if has_ci(req, b"keep-alive") { (RESP_KA, true) } else { (RESP_CLOSE, false) }
    } else if has_ci(req, b"connection: close") { (RESP_CLOSE, false) } else { (RESP, true) }
}

fn find_end(buf: &[u8]) -> bool {
    buf.windows(4).any(|w| w == b"\r\n\r\n")
}

fn main() {
    let port = std::env::args().nth(1).expect("PORT");
    let l = TcpListener::bind(format!("127.0.0.1:{}", port)).unwrap();
    for s in l.incoming() {
        let mut s = match s { Ok(s) => s, Err(_) => continue };
        thread::spawn(move || {
            let mut buf = [0u8; 8192];
            loop {
                let mut n = 0;
                let ok = loop {
                    if n >= 4 && find_end(&buf[..n]) { break true; }
                    if n >= buf.len() { break false; }
                    match s.read(&mut buf[n..]) { Ok(0) | Err(_) => break false, Ok(k) => n += k }
                };
                if !ok { return; }
                let (resp, keep) = choose(&buf[..n]);
                if s.write_all(resp).is_err() || !keep { return; }
            }
        });
    }
}
