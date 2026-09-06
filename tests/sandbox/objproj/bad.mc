// A compile that fails, in a project with no run step: the fix must not make
// every one-step box exit 0.
i64 main() { return nosuch(); }
