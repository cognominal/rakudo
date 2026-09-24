use Test;

# Test-first spec for SUBSCRIPT-OPERATOR.md's Phase 1: `.1` (a bare,
# unsigned digit run directly after `.`, no space) as sugar for `[1]`.
#
# NOTHING IS IMPLEMENTED YET. `.1` is a clean "Malformed postfix call"
# error today (confirmed against this branch's build before writing this
# file) — every "positive" assertion below is expected to fail until this
# lands. This file is the acceptance target for that phase.
#
# Scope, per SUBSCRIPT-OPERATOR.md §3/§6: plain unsigned digit runs only.
# No negative numbers, no `1_000`-style separators, no computed indices —
# those stay `.[$idx]`'s job. `.1e5`/`.1_000` are included below not as
# assertions of a specific "correct" behavior, but to record and pin down
# whatever this implementation actually does with them, since the spec
# explicitly leaves that undefined rather than guaranteeing a particular
# error shape.
#
# All `.digit` syntax below is inside EVAL'd strings, never written
# directly in this file: this file itself must keep parsing under the
# *current*, unmodified grammar regardless of whether the feature exists yet.

plan 7;

# `try` keeps a compile-time failure (the expected state today) a normal,
# reported failure for that one test, instead of aborting the whole file.
sub try-eval(str $code) { try EVAL($code) }

# --- core behavior: .1 reads the same as [1] ---

is try-eval('my @a = <a b c>; @a.1'), 'b',
    '@a.1 reads the same element as @a[1]';

is try-eval('my @a = <a b c>; @a.0'), 'a',
    '@a.0 works too (digit "0" is still a digit run)';

# --- l-value: .1 is the same AST node as [1], so assignment should just work ---

is try-eval('my @a = <a b c>; @a.1 = "X"; @a.join(",")'), 'a,X,c',
    '@a.1 = "X" assigns the same element as @a[1] = "X"';

# --- chaining: dotty postfixes compose, so .1.1 should nest like [1][1] ---

is try-eval('my @a = [<a b>, <c d>]; @a.1.1'), 'd',
    '@a.1.1 nests the same as @a[1][1]';

# --- equivalence with the existing, explicit forms ---

is try-eval('my @a = <a b c>; @a.1 eq @a[1]'), True,
    '@a.1 and @a[1] give the identical value';

is try-eval('my @a = <a b c>; @a.[1] eq @a.1'), True,
    '@a.[1] (already-existing sugar) and the new @a.1 agree';

# --- must not disturb the existing, unrelated use of a bare `.` inside a
# number literal (1.5 is one NUM token, parsed at term level, never
# reaching postfix-`.` handling at all) ---

is try-eval('1.5'), 1.5,
    'a decimal number literal (1.5) is completely unaffected — this is a
    term-level NUM token, not a postfix `.` on a preceding term';

# --- edge cases the spec deliberately leaves unspecified (§6): recorded
# via `diag` (not counted in the plan) rather than asserted, since there's
# no "correct" answer specified — just don't want them silently doing the
# wrong thing (== index 1e5 treated as index 1, or 1_0 as index 10)
# without anyone noticing.

diag ".1e5 on @a = <a b c d e f> gives: "
    ~ try-eval('my @a = <a b c d e f>; @a.1e5').raku;

diag ".1_0 on @a = <a b c d e f> gives: "
    ~ try-eval('my @a = <a b c d e f>; @a.1_0').raku;

# vim: expandtab shiftwidth=4
