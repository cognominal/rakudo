use Test;

# Test-first spec for SUBSCRIPT-OPERATOR.md's Phase 2: `.~expr` / `.#expr`
# (a bare `~`/`#`-sigiled variable reference directly after `.`, no space)
# as sugar for `{~expr}` / `[#expr]` respectively.
#
# NOTHING IS IMPLEMENTED YET. `.~key`/`.#idx` are clean "Malformed postfix
# call" errors today (confirmed against this branch's build before writing
# this file) — every "positive" assertion below is expected to fail until
# this lands. This file is the acceptance target for that phase.
#
# Scope, per SUBSCRIPT-OPERATOR.md §1/§3: a bare `~`/`#`-sigiled variable
# reference only (mirrors Phase 1's `.1` being a bare literal, not a
# computed expression) — not a general expression starting with `~`/`#`.
#
# All `.~`/`.#` syntax below is inside EVAL'd strings, never written
# directly in this file: this file itself must keep parsing under the
# *current*, unmodified grammar regardless of whether the feature exists yet.

plan 8;

# `try` keeps a compile-time failure (the expected state today) a normal,
# reported failure for that one test, instead of aborting the whole file.
sub try-eval(str $code) { try EVAL($code) }

# --- .~expr: sugar for {~expr} (associative access) ---

is try-eval('my %h; my ~key = "a"; %h{~key} = "hi"; %h.~key'), 'hi',
    '%h.~key reads the same element as %h{~key}';

is try-eval('my %h; my ~key = "a"; %h.~key = "hi"; %h{~key}'), 'hi',
    '%h.~key = "hi" assigns the same as %h{~key} = "hi"';

is try-eval('my %h; my ~key = "a"; %h{~key} = "v"; %h.~key eq %h{~key}'), True,
    '%h.~key and %h{~key} give the identical value';

# --- .#expr: sugar for [#expr] (positional access) ---

is try-eval('my @a = <a b c>; my #idx = 1; @a[#idx] = "X"; @a.#idx'), 'X',
    '@a.#idx reads the same element as @a[#idx]';

is try-eval('my @a = <a b c>; my #idx = 1; @a.#idx = "X"; @a[#idx]'), 'X',
    '@a.#idx = "X" assigns the same as @a[#idx] = "X"';

is try-eval('my @a = <a b c>; my #idx = 2; @a.#idx eq @a[#idx]'), True,
    '@a.#idx and @a[#idx] give the identical value';

# --- this sugar is ~/#-specific, not a generic "any sigil after dot"
# mechanism: a $-sigiled variable in the same position keeps its existing,
# unrelated meaning (indirect method dispatch: invoke the callable held in
# the variable, with the invocant as an argument) ---

throws-like 'my %h = a => 1; my $key = "a"; %h.$key', Exception,
    '%h.$key is unaffected by this feature: it stays the existing $-sigil
    indirect-dispatch mechanism (tries to invoke the string "a" as a
    callable via CALL-ME), not a new {$key} hash-subscript reading';

# --- chaining with the existing .[ ]/.{ } sugar and Phase 1's .digit sugar ---

is try-eval('my %h; my ~k = "x"; %h{~k} = [10, 20, 30]; my #i = 1; %h.~k.#i'), 20,
    '%h.~k.#i chains: hash-lookup by ~-sigiled key, then positional index by #-sigiled value';

# vim: expandtab shiftwidth=4
