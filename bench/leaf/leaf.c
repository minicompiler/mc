// leaf.c -- leaf.mc in C, the reference for M49 step E (clang -O2).
#include <stdio.h>
#include <stdint.h>

#define LEN 4096
#define REPS 200000
#define SHORT 16
#define SREPS 40000000

static uint8_t buf[LEN], bm[32], da[LEN], db[LEN], dout[LEN];

__attribute__((noinline)) int64_t leaf(const uint8_t *p, int64_t n) {
    int64_t s = 0;
    for (int64_t i = 0; i < n; i++) s += p[i];
    return s;
}

__attribute__((noinline)) int64_t spn(const uint8_t *p, const uint8_t *m, int64_t len, int64_t want) {
    int64_t i = 0;
    for (; i < len; i++) {
        int64_t c = p[i];
        if (((m[c >> 3] >> (c & 7)) & 1) != want) break;
    }
    return i;
}

__attribute__((noinline)) int64_t dadd(const uint8_t *a, const uint8_t *b, uint8_t *o, int64_t n) {
    int64_t c = 0;
    for (int64_t i = 0; i < n; i++) {
        int64_t d = a[i] + b[i] + c;
        c = 0;
        if (d >= 10) { d -= 10; c = 1; }
        o[i] = (uint8_t) d;
    }
    return c;
}

int main(int argc, char **argv) {
    int ph = 'a';
    if (argc > 1) ph = argv[1][0];
    if (ph != 's' && ph != 'p' && ph != 'd' && ph != 'h') ph = 'a';
    for (int64_t i = 0; i < LEN; i++) { buf[i] = 'a' + i % 26; da[i] = i % 10; db[i] = (i * 7) % 10; }
    for (int i = 'a'; i <= 'z'; i++) bm[i >> 3] |= 1 << (i & 7);
    int64_t t;
    if (ph == 's' || ph == 'a') { t = 0; for (int64_t r = 0; r < REPS; r++) t += leaf(buf, LEN - (r & 1)); printf("%lld\n", (long long) t); }
    if (ph == 'p' || ph == 'a') { t = 0; for (int64_t r = 0; r < REPS; r++) t += spn(buf, bm, LEN - (r & 1), 1); printf("%lld\n", (long long) t); }
    if (ph == 'd' || ph == 'a') { t = 0; for (int64_t r = 0; r < REPS; r++) t += dadd(da, db, dout, LEN - (r & 1)) + dout[r & 1023]; printf("%lld\n", (long long) t); }
    if (ph == 'h' || ph == 'a') { t = 0; for (int64_t r = 0; r < SREPS; r++) { int64_t k = r & 7; t += leaf(buf + k, SHORT) + spn(buf + k, bm, SHORT, 1) + dadd(da + k, db, dout, SHORT); } printf("%lld\n", (long long) t); }
    return 0;
}
