// sandbox-exit: 0
// sandbox-stdout: env=hello
// sandbox-opts: --env MC_C2_ENV
// sandbox-alt-exit: 0
// sandbox-alt-stdout: env=
// sandbox-alt-opts:
// `--env NAME` (M48 C2): the box's environment gains `NAME=<the host's value>`,
// beside the two entries it has always had (HOME=/src and PATH=/). Nothing
// else of the host's environment ever crosses, which is what makes this a
// primitive: a caller that wants a variable in the box names it.
//
// The two halves are the two answers a program can get, and NEITHER is an
// error: with the flag the value the host had, without it nothing at all. A
// variable that is not set has no value, and `env=` is what a getenv() inside
// the box should then see -- a --env that stopped the box would make every
// optional setting of a tool mandatory.
//
// scripts/test-sandbox.sh exports MC_C2_ENV=hello before it runs this.
#include <sys>
#include <io>

extern uptr getenv(uptr name);

i64 main() {
    puts("env=");
    uptr v = getenv("MC_C2_ENV");
    if (v) puts(v);
    puts("\n");
    return 0;
}
