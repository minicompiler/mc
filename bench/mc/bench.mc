// bench.mc -- the benchmark workload in mc (core language + <sys> + <prelude>)
#include <sys>
#include <prelude>

#define N 50000000
#define ITERS 200000000

u8 sieve[N];                       // 50 MB in __bss, zero-filled by the loader

// unsigned decimal print: the left operand is u64, so / and % are udiv
void putu64(u64 v) {
    u8 buf[24];
    i64 i = 24;
    loop {
        i = i - 1;
        st8(buf + i, '0' + v % 10);
        v = v / 10;
        if (v == 0) break;
    }
    write(1, buf + i, 24 - i);
}

// (1) tight arithmetic: 64-bit LCG + xorshift mixing, 200M iterations
u64 mix() {
    u64 x = 88172645463325252;
    u64 acc = 0;
    i64 i = 0;
    while (i < ITERS) {
        x = x * 6364136223846793005 + 1442695040888963407;
        u64 y = x;
        y = y ^ (y >> 13);
        y = y ^ (y << 7);
        y = y ^ (y >> 17);
        acc = acc + y;
        i = i + 1;
    }
    return acc;
}

// (2) memory pass: sieve of Eratosthenes over 50M bytes, count primes < N
i64 primes() {
    i64 i = 2;
    while (i * i < N) {
        if (ld8(sieve + i) == 0) {
            i64 j = i * i;
            while (j < N) {
                st8(sieve + j, 1);
                j = j + i;
            }
        }
        i = i + 1;
    }
    i64 count = 0;
    i = 2;
    while (i < N) {
        if (ld8(sieve + i) == 0) count = count + 1;
        i = i + 1;
    }
    return count;
}

// (3) function calls: naive recursive fib(38)
i64 fib(i64 n) {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}

i64 main() {
    putu64(mix());
    puts("\n");
    putnum(primes());
    puts("\n");
    putnum(fib(38));
    puts("\n");
    return 0;
}
