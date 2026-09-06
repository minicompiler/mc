// user_claim_rule.mc — a module that teaches `while`, the lexeme <prelude>
// already owns through a `#rule`. In a claimed `.tk` source the module's
// handler runs; in an unclaimed `.mc` source the prelude's rule does, because a
// lexeme a DIRECTIVE introduced is never hidden by source_claim.
#include "claim_rule.mc"

void user_init() {
    syntax_stmt("while", &cr_while);
    source_claim(&cr_claim_tk);
}
