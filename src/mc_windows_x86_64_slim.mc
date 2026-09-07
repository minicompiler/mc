// mc_windows_x86_64_slim.mc — the slim compiler: src/mc_windows_x86_64.mc with src/core_slim.mc in
// place of src/core.mc, which is to say the same compiler without the bundled
// standard library (M44 § B, step 4).
//
// The host layer is the ONE line that differs between the five slim entries,
// exactly as it is between the five full ones (docs/guide/90-linux-host.md).

#include "host_windows_x86_64.mc"
#include "core_slim.mc"
#include "user.mc"
