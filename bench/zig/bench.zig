// bench.zig -- the benchmark workload in Zig
const std = @import("std");

const N: usize = 50000000;
const ITERS: i64 = 200000000;


// (1) tight arithmetic: 64-bit LCG + xorshift mixing, 200M iterations
fn mix() u64 {
    var x: u64 = 88172645463325252;
    var acc: u64 = 0;
    var i: i64 = 0;
    while (i < ITERS) : (i += 1) {
        x = x *% 6364136223846793005 +% 1442695040888963407;
        var y = x;
        y ^= y >> 13;
        y ^= y << 7;
        y ^= y >> 17;
        acc +%= y;
    }
    return acc;
}

// (2) memory pass: sieve of Eratosthenes over 50M bytes, count primes < N
fn primes() i64 {
    const sieve = std.heap.page_allocator.alloc(u8, N) catch unreachable; // 50 MB from mmap
    @memset(sieve, 0);
    var i: usize = 2;
    while (i * i < N) : (i += 1) {
        if (sieve[i] == 0) {
            var j: usize = i * i;
            while (j < N) : (j += i) sieve[j] = 1;
        }
    }
    var count: i64 = 0;
    i = 2;
    while (i < N) : (i += 1) {
        if (sieve[i] == 0) count += 1;
    }
    return count;
}

// (3) function calls: naive recursive fib(38)
fn fib(n: i64) i64 {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}

pub fn main(init: std.process.Init) !void {
    var buf: [256]u8 = undefined;
    var w = std.Io.File.stdout().writer(init.io, &buf);
    const out = &w.interface;
    try out.print("{d}\n", .{mix()});
    try out.print("{d}\n", .{primes()});
    try out.print("{d}\n", .{fib(38)});
    try out.flush();
}
