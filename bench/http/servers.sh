# name -> command (PORT appended). sourced by the harness.
server_cmd() {
  case "$1" in
    mc-serial)    echo "bin/mc-serial" ;;
    mc-fork1)     echo "bin/mc-fork1" ;;
    mc-forkka)    echo "bin/mc-forkka" ;;
    c-serial)     echo "bin/c-serial" ;;
    go-nethttp)   echo "bin/go-nethttp" ;;
    rust-threads) echo "bin/rust-threads" ;;
    zig-threads)  echo "bin/zig-threads" ;;
    cs-jit)       echo "dotnet bin/cs-jit/cs.dll" ;;
    cs-aot)       echo "bin/cs-aot/cs" ;;
  esac
}
