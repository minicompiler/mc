// user_progname.mc -- the registration that lets a taught compiler say its own
// name, in the smallest module that can hold it.
//
// A taught compiler is `mc` plus a module, shipped as its own binary. Before
// program() it could not say so: `mc-php --version` answered `mc 1.1.0`, naming
// the wrong tool and a version that belonged to something else; `mc-php` with no
// argument printed a usage naming mc and subcommands it may not carry; and every
// diagnostic it wrote began `mc: `.
//
//   build/mc1 --exe lib/mc_progname.mc -o build/mc-progname
//   build/mc-progname --version              # mcdemo 7.3.1, then `mc <version>`
//   build/mc-progname                        # usage: mcdemo ...
//   build/mc-progname nosuch.mc -o /dev/null # mcdemo: cannot open: nosuch.mc
//
// The name and the version go in one call on purpose: two separate registrations
// made a half of one expressible, and a half is a plausible lie -- a name with no
// version attributes mc's version to the other tool, a version with no name puts
// two versions under the word `mc`.
//
// This module teaches the compiler nothing else -- no word, no machine, no
// backend -- so what it compiles is byte for byte what the stock compiler
// compiles, and the only difference a user can see is the name on the line.
// scripts/check-surface.sh runs exactly the four commands above.
void user_init() {
    program("mcdemo", "7.3.1");
}
