// bench.rs -- the benchmark workload in Rust
const N: usize = 50_000_000;
const ITERS: i64 = 200_000_000;

// (1) tight arithmetic: 64-bit LCG + xorshift mixing, 200M iterations
fn mix() -> u64 {
    let mut x: u64 = 88172645463325252;
    let mut acc: u64 = 0;
    let mut i: i64 = 0;
    while i < ITERS {
        x = x.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        let mut y = x;
        y ^= y >> 13;
        y ^= y << 7;
        y ^= y >> 17;
        acc = acc.wrapping_add(y);
        i += 1;
    }
    acc
}

// (2) memory pass: sieve of Eratosthenes over 50M bytes, count primes < N
fn primes() -> i64 {
    let mut sieve = vec![0u8; N];
    let mut i: usize = 2;
    while i * i < N {
        if sieve[i] == 0 {
            let mut j = i * i;
            while j < N {
                sieve[j] = 1;
                j += i;
            }
        }
        i += 1;
    }
    let mut count: i64 = 0;
    i = 2;
    while i < N {
        if sieve[i] == 0 {
            count += 1;
        }
        i += 1;
    }
    count
}

// (3) function calls: naive recursive fib(38)
fn fib(n: i64) -> i64 {
    if n < 2 {
        return n;
    }
    fib(n - 1) + fib(n - 2)
}

fn main() {
    println!("{}", mix());
    println!("{}", primes());
    println!("{}", fib(38));
}
