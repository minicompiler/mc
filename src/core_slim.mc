// core_slim.mc — the compiler WITHOUT the bundle: `mc` minus the blob (M44
// § B1-B3, step 4).
//
// src/core.mc is the sum of seven parts; this file is the sum of five of them
// plus the entry point that matches. What it does not include:
//
//   <mc/core_bundle>   the ~370 KB blob and its reader. A name in angle
//                      brackets is answered by the LOCK (a package mc.lock
//                      pins) or by the installed `mc` package, and by nothing
//                      else -- so `mc install` is what makes <prelude>,
//                      <float> and <mc/core> resolve at all.
//   <mc/core_sandbox>  `mc sandbox` (see src/main_slim.mc).
//
// Everything else is byte for byte the same source the full compiler is built
// from: the same machines, the same writers, the same `mc build`, the same
// `mc pkg`. A slim binary compiles a program with no angle-bracket include,
// every --dump-*, `mc --host`, `mc --version`, `mc limits`, `mc sysroot`,
// `mc pkg` and `mc install` itself with nothing installed at all (§ B3).
//
// Exactly one thing is missing, as in src/core.mc: `void user_init()`.
// src/mc_slim.mc is this file plus a host layer and src/user.mc.

#include "core_min.mc"
#include "core_machines.mc"
#include "core_writers.mc"
#include "core_build.mc"
#include "core_pkg.mc"
#include "main_slim.mc"
