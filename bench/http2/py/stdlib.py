# Python stdlib http.server with ThreadingHTTPServer: a thread per connection, HTTP/1.1 keep-alive.
# Zero dependencies. Contract: GET / -> 200, Content-Type: text/plain, Content-Length: 13, "hello, world\n".
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", "13")
        self.end_headers()
        self.wfile.write(b"hello, world\n")
    def log_message(self, *args):
        pass

ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
