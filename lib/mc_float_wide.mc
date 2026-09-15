// mc_float_wide.mc — the coexistence compiler: <float> (+ its two machines),
// <f16> and <i128>/<u128> in ONE taught compiler, float registered FIRST.
//
// lib/mc_wide_float.mc is the same set in the other order. Both exist because a
// derived machine that claimed `op >= BASE` with no upper bound encoded a
// FOREIGN module's opcode with its own table, and which module lost depended on
// the registration order (docs/reference/machine.md § 3, the opcode-range
// registry). Two entries, two orders, one behaviour.
//
//   build/mc1 --exe lib/mc_float_wide.mc -o build/mc-float-wide
//   build/mc-float-wide --exe tests/wide/035-coexist.mc -o t && ./t
#include "../src/host_macos.mc"
#include "../src/core.mc"
#include "float.mc"
#include "machine_arm64_float.mc"
#include "machine_x86_64_float.mc"
#include "f16.mc"
#include "i128.mc"

void user_init() {
    float_init();
    machine_arm64_float_init();
    machine_x86_64_float_init();
    f16_init();
    i128_init();
}
