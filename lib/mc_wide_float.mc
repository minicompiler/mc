// mc_wide_float.mc — the coexistence compiler, the OTHER order: <i128>/<u128>
// registers its machine first and <float> (+ <f16>) derives on top of it.
//
// See lib/mc_float_wide.mc for why both orders are fixtures.
//
//   build/mc1 --exe lib/mc_wide_float.mc -o build/mc-wide-float
//   build/mc-wide-float --exe tests/wide/035-coexist.mc -o t && ./t
#include "../src/host_macos.mc"
#include "../src/core.mc"
#include "i128.mc"
#include "float.mc"
#include "machine_arm64_float.mc"
#include "machine_x86_64_float.mc"
#include "f16.mc"

void user_init() {
    i128_init();
    float_init();
    machine_arm64_float_init();
    machine_x86_64_float_init();
    f16_init();
}
