// user_progname.mc -- the two registrations that let a taught compiler say its
// own name, in the smallest module that can hold them.
//
// A taught compiler is `mc` plus a module, shipped as its own binary. Before
// program_name()/program_version() it could not say so: `mc-php --version`
// answered `mc 1.1.0`, naming the wrong tool and a version that belonged to
// something else, and every diagnostic it wrote began `mc: `.
//
//   build/mc1 --exe lib/mc_progname.mc -o build/mc-progname
//   build/mc-progname --version              # mcdemo 7.3.1, then `mc <version>`
//   build/mc-progname nosuch.mc -o /dev/null # mcdemo: cannot open: nosuch.mc
//
// This module teaches the compiler nothing else -- no word, no machine, no
// backend -- so what it compiles is byte for byte what the stock compiler
// compiles, and the only difference a user can see is the name on the line.
// scripts/check-surface.sh runs exactly the three commands above.
void user_init() {
    program_name("mcdemo");
    program_version("7.3.1");
}
