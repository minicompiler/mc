#!/bin/bash
# static facts: binary size, source lines, linked libraries / runtime
cd "$(dirname "$0")"
for s in mc-serial:mc/serial.mc+mc/httpmin.mc mc-fork1:mc/fork1.mc+mc/httpmin.mc mc-forkka:mc/forkka.mc+mc/httpmin.mc c-serial:c/serial.c go-nethttp:go/main.go rust-threads:rust/main.rs zig-threads:zig/main.zig cs-jit:cs/Program.cs+cs/cs.csproj cs-aot:cs/Program.cs+cs/cs.csproj; do
  n=${s%%:*}; src=${s#*:}
  case $n in cs-jit) bin=bin/cs-jit/cs.dll ;; cs-aot) bin=bin/cs-aot/cs ;; *) bin=bin/$n ;; esac
  lines=0; for f in ${src//+/ }; do lines=$((lines + $(wc -l < $f))); done
  size=$(stat -f %z $bin)
  libs=$(otool -L $bin 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ')
  echo "$n|$src|$lines|$size|$libs"
done
echo "cs-jit publish dir total: $(du -sk bin/cs-jit | cut -f1) KiB; runtime = shared Microsoft.NETCore.App 10.0.9 + Microsoft.AspNetCore.App at $(brew --prefix dotnet)/libexec/shared ($(du -sk $(brew --prefix dotnet)/libexec/shared | cut -f1) KiB)"
