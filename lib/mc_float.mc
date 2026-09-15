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
// The frozen C seed (build/mc0) has never compiled this file, and never needs
// to: lib/ is not compared against the seed (docs/plan.md, CLAUDE.md § State)
// -- it is taught surface, and mc0 is a differential oracle for src/ and
// tests/ only. It is gated instead by check-float (built with mc1 and RUN
// on all five targets, with the llvm-mc sweep) and check-inert (pre/post mc1
// byte-identical). Worth knowing anyway: once <mc/core> carried both the
// M42-step-2 PE writer and the M44 version-constraint solver, this whole
// taught compiler needed 2056 functions against the seed's MAXFUNCS of 2048
// (2044 before the solver) -- the same limit the bootstrap decoupling worked
// around for src/mc.mc (mc0 compiles only src/mc_seed.mc).
#include "../src/host_macos.mc"
#include "../src/core.mc"
#include "user_float.mc"
