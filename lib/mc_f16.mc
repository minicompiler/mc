// mc_f16.mc — the compiler that carries lib/f16.mc on top of <float> (M24 step 2).
//
// The frozen C seed (build/mc0) has never compiled this file, and never needs
// to: lib/ is not compared against the seed (docs/plan.md, CLAUDE.md § State)
// -- it is taught surface, and mc0 is a differential oracle for src/ and
// tests/ only. It is gated instead by check-wide (built with mc_seed and RUN),
// check-inert (pre/post mc1 byte-identical) and check-standalone. Worth
// knowing anyway: once <mc/core> carried the M42-step-2 PE writer, this whole
// taught compiler -- the tightest full-core fixture -- needed 2062 functions
// against the seed's MAXFUNCS of 2048, the same limit the bootstrap decoupling
// worked around for src/mc.mc (mc0 compiles only src/mc_seed.mc; the
// growable-arena seed compiler compiles the rest).
//
// The order is the point: f16 DERIVES from the machine <float> registered under
// `arm64`, so float_init and machine_arm64_float_init have to come first. A
// module that stacks on another one says which one it needs (risk 4 of
// docs/specs/M24.md: machine registration is last-wins).
#include "../src/host_macos.mc"
#include "../src/core.mc"
#include "float.mc"
#include "machine_arm64_float.mc"
#include "machine_x86_64_float.mc"
#include "f16.mc"

void user_init() {
    float_init();
    machine_arm64_float_init();
    machine_x86_64_float_init();
    f16_init();
}
