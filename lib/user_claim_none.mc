// user_claim_none.mc — the same two words with a handler that claims NOTHING.
// The honest edge of the rule: a module whose taught words apply in no source
// has taught the compiler nothing any source can reach, so `type answer 40;` is
// `type expected at top level` even in the `.tk` file the dialect was written
// for.
#include "claim_demo.mc"

void user_init() {
    cd_words();
    source_claim(&cd_claim_none);
}
