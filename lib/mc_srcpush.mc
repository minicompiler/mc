// mc_srcpush.mc — the compiler that carries lib/user_srcpush.mc, whose only
// purpose is to fire the guard in lex_push_mem. Same three lines as
// lib/mc_source_nop.mc.
#include "../src/host_macos.mc"
#include "../src/core.mc"
#include "user_srcpush.mc"
