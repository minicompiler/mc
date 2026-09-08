// tests/pkg/minver -- a project that declares [package].mc, the minimum mc
// version. The entry compiles to exit 42; the mc.toml variants beside it drive
// the accept path (mc.toml) and the malformed-value error (bad.toml) with the
// dev-build build/mc1, whose 0.0.0-dev sentinel SKIPS the version compare. The
// refusal path needs a compiler baked to a real version and is driven in
// scripts/check-pkg.sh from a temporary project.
i64 main() { return 42; }
