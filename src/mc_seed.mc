// mc_seed.mc — the bootstrap SEED compiler: the smallest compiler that can
// compile the full src/mc.mc to a real Mach-O object.
//
// It exists to decouple the bootstrap from the size of the whole compiler. The
// stage0 C seed (build/mc0) has a FIXED 64 MiB arena it cannot grow without
// editing the frozen stage0/, and compiling src/mc.mc already touches ~57 MiB
// of it — so the compiler cannot keep growing through mc0. This file breaks
// that coupling: mc0 compiles only THIS minimal core, and the resulting seed
// compiler — which carries the same growable, mmap-backed arena every mc1+ has
// (src/arena.mc) — is what compiles the full src/mc.mc to build/mc1.o.
//
// The seed core is <mc/core_min> (the front end, resolver, walker and CLI) plus
// exactly one machine (arm64) and exactly one object writer (macho). It leaves
// out the second machine (x86-64), the exe/elf/coff writers, sha256, the build
// driver, the bundle, the package manager and the sandbox — none of which is
// needed to compile a .mc source to a .o on this host. Only RELATIVE includes,
// because mc0 has no bundle and no `#embed` (same as src/mc.mc).
//
// The correctness proof is byte-neutrality: the seed and the full compiler
// share the SAME codegen source (gen_resolve, gen_walk, machine_arm64,
// objmodel, macho), so the seed compiling src/mc.mc produces exactly the object
// the full compiler produces. scripts/bootstrap.sh proves it by the fixed
// point (mc2.o == mc3.o) and the unchanged golden; on a branch where mc0 can
// still compile src/mc.mc, `cmp mc0(src/mc.mc) mc_seed(src/mc.mc)` proves it
// directly.

#include "host_macos.mc"
#include "core_min.mc"
#include "machine_arm64.mc"
#include "macho.mc"

// backend_macho: a byte-for-byte copy of the one in src/core_writers.mc, which
// the seed does not include. It is defined by the part that registers it (M41),
// and the seed is that part here. `machine_use("arm64")` first, like every
// backend since M17 — the current machine at this point is the host's, which is
// already arm64, but the call is what makes the object's architecture explicit.
void backend_macho(i64 unit, uptr out) {
    machine_use("arm64");
    gen_lower(unit);
    gen_encode_all();
    macho_write(out);
}

i64 main(i64 argc, uptr argv, uptr envp) {
    host_init(envp);
    machine_arm64_init();
    backend("macho", &backend_macho);
    backend_default("macho");
    return mc_main(argc, argv, envp);
}

// the seed teaches the compiler nothing
void user_init() { }
