// user_claim_open.mc — the same two words with NO source_claim: every source is
// claimed, which is what every taught compiler did before the hook existed. It
// exists to be the failure: `i64 core_type(i64 type)` in an ordinary `.mc` file
// is `name expected` here, and compiles under lib/user_claim_demo.mc.
#include "claim_demo.mc"

void user_init() {
    cd_words();
}
