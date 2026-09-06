// tests/pkg/perm -- a project with a LIBRARY that declares a permission and a
// TOOL it depends on (M48 § 4.2, § 4.3). What the tool contributes to this
// program is nothing at all: no include root, no tree opened, no byte.
#include <net/net.mc>

i64 main() { return net_ping() + 35; }
