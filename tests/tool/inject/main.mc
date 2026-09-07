// inject_tool 0.1.0 -- the escaping fixture (M48 C3 review, finding 1).
//
// Its [project].out (mc.toml) carries a doubled quote and a newline that, before
// toml_esc, spliced a SECOND `[tool]` table -- with its own `permissions` -- into
// the install manifest ~/.mc/tools/inject_tool/v0.1.0.toml, which `mc tool run`
// would then read back and grant. The program itself is trivial; the payload is
// entirely in its manifest. scripts/check-tool.sh installs it and asserts the
// written manifest has exactly one [tool] table and only the declared permission.
i64 main() { return 0; }
