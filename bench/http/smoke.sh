#!/bin/bash
# start each server, curl -i three times, save the output, kill the server
cd "$(dirname "$0")"; . ./servers.sh
port=18000
for s in "$@"; do
  port=$((port+1))
  cmd=$(server_cmd $s)
  $cmd $port > logs/smoke-$s.out 2>&1 &
  pid=$!
  for i in $(seq 1 100); do curl -s -o /dev/null http://127.0.0.1:$port/ && break; sleep 0.05; done
  for i in 1 2 3; do curl -si http://127.0.0.1:$port/ > logs/curl-$s-$i.txt; done
  echo "== $s (pid $pid, port $port)"; cat -A logs/curl-$s-1.txt
  cmp logs/curl-$s-1.txt logs/curl-$s-2.txt && cmp logs/curl-$s-1.txt logs/curl-$s-3.txt && echo "3 curl outputs identical: yes" || echo "3 curl outputs differ (Date header?)"
  # body + status + the two contract headers
  { head -1 logs/curl-$s-1.txt; grep -i '^content-type:\|^content-length:' logs/curl-$s-1.txt | tr 'A-Z' 'a-z'; tail -1 logs/curl-$s-1.txt; } > logs/contract-$s.txt
  kill $pid 2>/dev/null; pkill -P $pid 2>/dev/null; wait $pid 2>/dev/null
done
