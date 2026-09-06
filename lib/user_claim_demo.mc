// user_claim_demo.mc — the two colliding words, scoped to the sources this
// module claims (lib/claim_demo.mc). This is the consumer's shape: a `.tk`
// program in the module's dialect that includes an ordinary `.mc` file the core
// reads with its own vocabulary.
#include "claim_demo.mc"

void user_init() {
    cd_words();
    source_claim(&cd_claim_tk);
}
