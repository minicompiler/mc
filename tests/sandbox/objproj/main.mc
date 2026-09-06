// A project whose [project].kind is "obj": there is nothing to run, so the box
// has ONE step and `compile: exit 0` is its terminal status. It is the shape
// the registry's validator compiles a package in (mc-registry spec M47 § 22.4),
// and the shape that used to end in `the box ended without a status`, exit 126,
// after a compile that succeeded.
//
// Nothing here is run, so the body only has to compile.
i64 answer() { return 42; }

i64 main() {
    return answer() - 42;
}
