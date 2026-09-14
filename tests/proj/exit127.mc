// exit127.mc — a module whose taught compiler dies the moment it starts, with
// no output at all: `_exit(127)` is what a loader refusing an executable looks
// like from the driver's side (the consumer's windows/x86_64 report, M42 step
// 2), and it is the case that used to end `mc build` mute.
//
// Used by tests/proj/teach-fail.toml (scripts/check-build.sh).
void user_init() {
    _exit(127);
}
