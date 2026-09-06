// Node http.createServer, one process, one event-loop thread: the idiomatic baseline.
// Contract: GET / -> 200, Content-Type: text/plain, Content-Length: 13, body "hello, world\n".
const http = require('http');
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain', 'Content-Length': '13' });
  res.end('hello, world\n');
});
server.listen(Number(process.argv[2]), '127.0.0.1');
