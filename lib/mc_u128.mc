// mc_u128.mc — the compiler that carries <u128> (= <i128>).
//
//   build/mc1 --exe lib/mc_u128.mc -o build/mc-u128
//   build/mc-u128 --exe tests/wide/032-u128.mc -o t && ./t
#include "../src/host_macos.mc"
#include "../src/core.mc"
#include "u128.mc"

void user_init() { u128_init(); }
