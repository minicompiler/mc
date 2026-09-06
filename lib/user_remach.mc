// user_remach.mc — the fixture for "a registration no longer steals the current
// machine". It is what a module teaching a type family looks like from the
// registry's point of view: it derives from EVERY bundled machine, under each
// machine's own name, and changes not one slot.
//
// A module that adds a primitive has to do this. `<float>` is the real case:
// lib/machine_arm64_float.mc re-registers `arm64` and
// lib/machine_x86_64_float.mc re-registers `x86_64` and `x86_64-win`, because a
// float depth has to be recognised by whichever machine the target picks. The
// defect this fixture pins down is that `machine()` used to make EVERY
// registration current, so the last of the three -- `x86_64-win` -- became the
// machine in effect on a macOS/aarch64 host, where src/cli.mc had already
// selected `arm64` for the raw single-file road (`mc x.mc --dump-asm`, with no
// [target] and no backend to call machine_use for it).
//
// Since it changes no slot, a compiler carrying it must produce byte for byte
// what the stock compiler produces -- which is the assertion in
// scripts/check-surface.sh.
uptr rm_arm64;
uptr rm_x86;
uptr rm_x86win;

// copy(name): the registered table of `name`, copied into a block this module
// owns. The recipe of docs/reference/hooks.md, minus the machine_slot call --
// there is nothing to patch here, the point is the registration itself.
uptr rm_copy(uptr name) {
    uptr src = machine_tab(name);
    uptr dst = xalloc(MTASK_COUNT * 8);
    i64 t = 0;
    loop {
        if (t >= MTASK_COUNT) break;
        st64(dst + t * 8, ld64(src + t * 8));
        t = t + 1;
    }
    return dst;
}

void user_init() {
    rm_arm64  = rm_copy("arm64");
    rm_x86    = rm_copy("x86_64");
    rm_x86win = rm_copy("x86_64-win");
    machine("arm64", rm_arm64);
    machine("x86_64", rm_x86);
    machine("x86_64-win", rm_x86win);
}
