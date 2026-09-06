// main_slim.mc — the entry point of `mc-slim`: src/main.mc without the two
// parts the slim flavour leaves out (M44 § B, step 4).
//
// It is the same list src/main.mc has, minus:
//
//   mc_bundle_init()   <mc/core_bundle> -- the blob. That is the whole point:
//                      the slim binary weighs what it weighs because the ~370
//                      KB of compressed library source is not in it. Every
//                      `#include <name>` therefore misses the bundle and goes
//                      on to the third step of the resolution order, the
//                      installed `mc` package (`mc install`).
//   mc_sandbox_init()  <mc/core_sandbox> -- `mc sandbox`, which is a Linux
//                      supervisor and not part of compiling anything. Leaving
//                      it out is the one difference of this flavour that is not
//                      the blob; a build that wants it adds the include and the
//                      call, and nothing else changes.
//
// The order of what remains is src/main.mc's, unchanged: every *_init runs
// before mc_main and none of them may call tok_add.

i64 main(i64 argc, uptr argv, uptr envp) {
    host_init(envp);
    mc_machines_init();
    mc_writers_init();
    mc_build_init();
    mc_pkg_init();
    return mc_main(argc, argv, envp);
}
