// Bench.cs -- the benchmark workload in C#
using System;

static class Bench
{
    const int N = 50000000;
    const long ITERS = 200000000;

    // (1) tight arithmetic: 64-bit LCG + xorshift mixing, 200M iterations
    static ulong Mix()
    {
        ulong x = 88172645463325252UL;
        ulong acc = 0;
        for (long i = 0; i < ITERS; i++)
        {
            x = x * 6364136223846793005UL + 1442695040888963407UL;
            ulong y = x;
            y ^= y >> 13;
            y ^= y << 7;
            y ^= y >> 17;
            acc += y;
        }
        return acc;
    }

    // (2) memory pass: sieve of Eratosthenes over 50M bytes, count primes < N
    static long Primes()
    {
        var sieve = new byte[N];
        for (long i = 2; i * i < N; i++)
        {
            if (sieve[i] == 0)
            {
                for (long j = i * i; j < N; j += i) sieve[j] = 1;
            }
        }
        long count = 0;
        for (long i = 2; i < N; i++)
        {
            if (sieve[i] == 0) count++;
        }
        return count;
    }

    // (3) function calls: naive recursive fib(38)
    static long Fib(long n)
    {
        if (n < 2) return n;
        return Fib(n - 1) + Fib(n - 2);
    }

    static void Main()
    {
        Console.WriteLine(Mix());
        Console.WriteLine(Primes());
        Console.WriteLine(Fib(38));
    }
}
