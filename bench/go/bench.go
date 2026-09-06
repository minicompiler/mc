// bench.go -- the benchmark workload in Go
package main

import "fmt"

const N = 50000000
const ITERS = 200000000

// (1) tight arithmetic: 64-bit LCG + xorshift mixing, 200M iterations
func mix() uint64 {
	var x uint64 = 88172645463325252
	var acc uint64 = 0
	for i := int64(0); i < ITERS; i++ {
		x = x*6364136223846793005 + 1442695040888963407
		y := x
		y ^= y >> 13
		y ^= y << 7
		y ^= y >> 17
		acc += y
	}
	return acc
}

// (2) memory pass: sieve of Eratosthenes over 50M bytes, count primes < N
func primes() int64 {
	sieve := make([]byte, N)
	for i := int64(2); i*i < N; i++ {
		if sieve[i] == 0 {
			for j := i * i; j < N; j += i {
				sieve[j] = 1
			}
		}
	}
	var count int64 = 0
	for i := int64(2); i < N; i++ {
		if sieve[i] == 0 {
			count++
		}
	}
	return count
}

// (3) function calls: naive recursive fib(38)
func fib(n int64) int64 {
	if n < 2 {
		return n
	}
	return fib(n-1) + fib(n-2)
}

func main() {
	fmt.Println(mix())
	fmt.Println(primes())
	fmt.Println(fib(38))
}
