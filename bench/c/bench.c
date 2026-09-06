// bench.c -- the benchmark workload in C
#include <stdio.h>
#include <stdint.h>

#define N 50000000
#define ITERS 200000000

static uint8_t sieve[N];           // 50 MB in .bss

// (1) tight arithmetic: 64-bit LCG + xorshift mixing, 200M iterations
static uint64_t mix(void) {
    uint64_t x = 88172645463325252ULL;
    uint64_t acc = 0;
    for (int64_t i = 0; i < ITERS; i++) {
        x = x * 6364136223846793005ULL + 1442695040888963407ULL;
        uint64_t y = x;
        y ^= y >> 13;
        y ^= y << 7;
        y ^= y >> 17;
        acc += y;
    }
    return acc;
}

// (2) memory pass: sieve of Eratosthenes over 50M bytes, count primes < N
static int64_t primes(void) {
    for (int64_t i = 2; i * i < N; i++) {
        if (sieve[i] == 0) {
            for (int64_t j = i * i; j < N; j += i) sieve[j] = 1;
        }
    }
    int64_t count = 0;
    for (int64_t i = 2; i < N; i++) {
        if (sieve[i] == 0) count++;
    }
    return count;
}

// (3) function calls: naive recursive fib(38)
static int64_t fib(int64_t n) {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}

int main(void) {
    printf("%llu\n", (unsigned long long) mix());
    printf("%lld\n", (long long) primes());
    printf("%lld\n", (long long) fib(38));
    return 0;
}
