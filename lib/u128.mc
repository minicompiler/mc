// u128.mc — `u128` as a separate bundled entry point. The type, its literal and
// the wide machine all live in <i128>; this file exists so a program can write
// `#include <u128>` and reach them. Both `<i128>` and `<u128>` register the same
// pair of types (i128 AND u128) and the same machine, so include ONE of them --
// they are two doors into one module and cannot both be included in one unit.
#include "i128.mc"

void u128_init() { i128_init(); }
