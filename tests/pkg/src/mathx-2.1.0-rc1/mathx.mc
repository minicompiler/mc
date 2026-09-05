// mathx.mc -- mathx 2.1.0-rc1: a PRE-RELEASE row (SemVer 2.0 § 9). It is the
// newest row of major 2 by the numeric fields alone, so `mc pkg add mathx` and
// `mc update mathx` landing on 2.1.0 instead is the proof that a candidate is
// never chosen for you -- only asked for by name, `mathx@2.1.0-rc1`.
i64 mathx_sq(i64 x) { return x * x; }
i64 mathx_version() { return 209; }
