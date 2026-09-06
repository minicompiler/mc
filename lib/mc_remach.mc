// mc_remach.mc — the compiler that carries lib/user_remach.mc.
//
//   build/mc1 --exe lib/mc_remach.mc -o build/mc-remach
//   build/mc-remach --dump-machine x.mc | grep '(current)'   ->  machine arm64 (current)
#include "../src/host_macos.mc"
#include "../src/core.mc"
#include "user_remach.mc"
