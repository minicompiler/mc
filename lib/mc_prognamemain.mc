// mc_prognamemain.mc -- the SECOND road to a program's own name: a recreated
// compiler that writes its own main() and registers there, before mc_main().
//
// lib/mc_progname.mc is the ordinary road, `#include "../src/core.mc"` plus a
// user_init, and it reaches every message raised from user_init() onward. It
// cannot reach the few raised before: the argument loop's own refusals, the
// entry file that cannot be opened (lex_init must precede user_init -- it opens
// with `nopen = 0`, which would throw away a source a user_init had pushed), and
// every subcommand, which is dispatched before the loop.
//
// This file is src/main.mc with one line added, so those are reached too, and it
// is what proves the twenty-seven diagnostic sites are one set: a compiler that
// registers HERE must print one name everywhere, never `myc:` from one file and
// `mc:` from another. scripts/check-surface.sh asserts exactly that.
#include "../src/host_macos.mc"
#include "../src/core_min.mc"
#include "../src/core_machines.mc"
#include "../src/core_writers.mc"
#include "../src/core_build.mc"
#include "../src/core_bundle.mc"
#include "../src/core_pkg.mc"
#include "../src/core_sandbox.mc"

i64 main(i64 argc, uptr argv, uptr envp) {
    host_init(envp);
    program("myc", "3.1.4");                   // before mc_main: every road sees it
    mc_machines_init();
    mc_writers_init();
    mc_bundle_init();
    mc_build_init();
    mc_pkg_init();
    mc_sandbox_init();
    return mc_main(argc, argv, envp);
}

void user_init() { }
