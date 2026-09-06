// Node cluster: the primary forks one worker per core (os.availableParallelism()),
// every worker runs the same http.createServer on a shared listening socket.
// On SIGTERM the primary stops the workers and exits only after reaping them all, so
// /usr/bin/time -l sees the workers' CPU (the fork servers in bench/http reap theirs too).
const cluster = require('node:cluster');
const http = require('node:http');
const os = require('node:os');
if (cluster.isPrimary) {
  const n = os.availableParallelism();
  for (let i = 0; i < n; i++) cluster.fork();
  let stopping = false;
  cluster.on('exit', () => { if (stopping && Object.keys(cluster.workers).length === 0) process.exit(0); });
  process.on('SIGTERM', () => { stopping = true; for (const id in cluster.workers) cluster.workers[id].process.kill('SIGTERM'); });
} else {
  http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/plain', 'Content-Length': '13' });
    res.end('hello, world\n');
  }).listen(Number(process.argv[2]), '127.0.0.1');
}
