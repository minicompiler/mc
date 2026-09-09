// mc_float.mc — the compiler that carries `<float>`, in three lines of #include.
//
//   build/mc1 --exe lib/mc_float.mc -o build/mc-float
//   build/mc-float --exe prog.mc -o prog
//
// Or, from a project, `[compiler] modules = ["user_float.mc"]` (docs/build.md).
// The stock `mc` has no floats: <float> is deliberately NOT in
// lib/user_default.mc, which is what makes "an untaught object is identical to
// the frozen seed's" a structural fact and not a coincidence.
//
// seed-skip: the frozen C seed (build/mc0) cannot compile this WHOLE taught
// compiler once <mc/core> carries both the M42-step-2 PE writer and the M44
// version-constraint solver in deps/pkg -- it now needs 2056 functions and the
// seed's MAXFUNCS is 2048 (it fit at 2044 before the solver). Same limit the
// bootstrap decoupling worked around for src/mc.mc (mc0 compiles only
// src/mc_seed.mc). It is gated instead by check-float (built with mc1 and RUN
// on all five targets, with the llvm-mc sweep) and check-inert (pre/post mc1
// byte-identical). mc_i128/mc_u128 stay in the corpus: they still fit the seed.
#include "../src/host_macos.mc"
#include "../src/core.mc"
#include "user_float.mc"
