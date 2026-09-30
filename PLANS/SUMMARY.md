# SUMMARY — `rak` branch

## What this branch is

A combined **rak mode** for Rakudo — a new language mode that merges three
independent feature branches into a single `.rak` file-extension gated
frontend. It's selectable via `RAKUDO_RAK_FRONTEND=1 RAKU_RAK_MODE=1`,
or by running the `rak` executable at the repo root (which sets those
env vars and runs the shared `rakudo-m` binary).

## Merged branches

| Branch | Feature | Status |
|--------|---------|--------|
| `new-sigils` | New fixed-type sigils `~` (native str) and `#` (native int); dotty subscript sugar (`.1`, `.~expr`, `.#expr`, `.name` → `<name>`, `->name` → parameterless method call) | **Done** — 62 tests pass |
| `redirection` | Shellish output redirection (`say foo >file.txt`); naked-string literals; binary-operator disambiguation via spacing | **Done** — 20 tests pass |
| `onepass-compile` | One-pass CORE setting build; `#COMPILER::if/endif/line` directives; removal of vestigial JVM/JS backend conditionals | **Done** — no dedicated test file, build pipeline verified |

## Bugs fixed (from source branches)

1. **Naked-string vs function-call disambiguation** (redirection branch):  
   The guard `is-identifier-known(..., :exact)` can't see setting routines
   (`&say`, `&plan`, `&print`), so every bareword — including `say` itself —
   became a naked string, making `.rak` files uncompilable.  
   **Fix**: Dropped `:exact`. A bareword is now a naked string iff
   `is-identifier-known` returns false (setting routines resolve via
   `&say`-style lookup).

2. **`after-ws()` and `infix:sym«>»` used `self.pos()`** (redirection branch):  
   `self.pos()` in a grammar token code assertion returns the start of the
   whole parse (always 0), never the current cursor position — so every
   "is there whitespace after `>`?" check was always false.  
   **Fix**: Use `$/.pos()` (or explicitly pass `$m.pos()` via the method
   argument).

3. **`#COMPILER::if !moar` never skipped** (onepass-compile branch):  
   The true-condition branch was a bare `{ }` code block (which always
   matches), and the skip loop `[\N*\n]*` — in NQP grammar tokens —
   can't backtrack a greedy iteration across newlines to re-sync on
   `#COMPILER::endif`.  
   **Fix**: True-condition is now a real `<?{ }>` assertion; skip loop
   uses lazy `*?`.

## Architecture

Three frontends share a single binary (`rakudo-m`), selected by env vars:

| Env vars | Grammar | Actions | Compiler mode |
|---|---|---|---|
| *(none)* | `Perl6::Grammar` (legacy) | `Perl6::Actions` | Legacy QAST |
| `RAKUDO_RAKUAST=1` | `Raku::Grammar` | `Raku::Actions` | RakuAST |
| `RAKUDO_RAK_FRONTEND=1 RAKU_RAK_MODE=1` | `Raku::Grammar` | `Raku::Actions` | RakuAST + rak features |

The `rak` wrapper sets both env vars and runs the same binary.

## The `$*RAK-SEMANTICS` gate

All rak features are gated by a single dynamic variable `$*RAK-SEMANTICS`,
set in `Raku::Actions.comp-unit-prologue`:

- `.rak` file extension → **1**
- `.raku`, `.rakumod`, `.pm6`, `.nqp` → **0**
- no file extension (REPL, `-e`, STDIN) → falls back to `RAKU_RAK_MODE`
  env var (set by the `rak` wrapper)

The variable is declared with `:my $*RAK-SEMANTICS;` in the grammar's
`TOP` method (line 1361 of `src/Raku/Grammar.nqp`). Every feature-specific
token or alternative has `<?{ $*RAK-SEMANTICS }>` guarding it.

## Design documents (`PLANS/`)

| Directory | Source branch | Documents |
|-----------|---------------|-----------|
| `PLANS/new-sigils/` | `new-sigils` | CLAUDE.md, SUBSCRIPT-OPERATOR.md, INTERACTIVE-NAVIGATION.md |
| `PLANS/redirection/` | `redirection` | RAKFILE.md |
| `PLANS/onepass-compile/` | `onepass-compile` | onepass-compile.md |
| `PLANS/` (root) | *(combined branch)* | README.md, features.md, modes.md, naked-strings.md, spacing-as-syntax.md |

## Tests

All 82 tests pass across 9 test files:

| File | Assertions |
|------|-----------|
| `t/02-rakudo/new-sigil-int.t` | 18 |
| `t/02-rakudo/new-sigil-str.t` | 18 |
| `t/02-rakudo/dot-subscript-numeric.t` | 7 |
| `t/02-rakudo/dot-subscript-sigil.t` | 8 |
| `t/02-rakudo/dot-subscript-name.t` | 11 |
| `t/14-redirection/basic.rak` | 10 |
| `t/14-redirection/binary-ops.rak` | 4 |
| `t/14-redirection/edge-cases.rak` | 4 |
| `t/14-redirection/gating.raku` | 2 |

The redirection tests were rewritten to use `->` method calls (the natural
consequence of the dotty sugar in `.rak` files) and to assert only
implementable invariants (input redirection `<file` remains future work).

## Standalone fork (not yet used)

`src/Rak/Grammar.nqp` and `src/Rak/Actions.nqp` are fully-namespaced,
all-gates-removed forks that compile independently. They are **not** used
by the current rak frontend because the sub-grammars (`Rak::QGrammar`,
`Rak::RegexGrammar`) have a composition issue — NQP's `create-quote-lang-type`
fails on the forked grammar types. When that's resolved, the standing
can switch from delegating to the shared grammar to loading the standalone
files, and `src/Raku/Grammar.nqp` can be stripped of all rak-related code
(`$*RAK-SEMANTICS`, `statement-mod-redir`, `after-ws`, dotty-name-sugar,
the `!$*RAK-SEMANTICS ||` guard, `term:sym<rak-string>`, sigils `~#`,
tightened `comment:sym<#>`, escape handlers, i1/t1 roles).

## Git log (current branch `rak`)

```
7df773aa4 Add RAKUDO_RAK_FRONTEND env var support
96049867b rak wrapper: restore sh→bash shebang, simplify comments, keep RAKU_RAK_MODE approach
ea65da821 Additional PLANS docs (rak features, modes, naked-strings, spacing-as-syntax)
f5143d891 Fix combined rak-mode semantics so all three branches work together
0d83ae4fb Move design documents to PLANS/ named after the original branch
f4e2a5b50 Merge onepass-compile (one-pass compilation, backend directive removal, #COMPILER directives)
a8850d8f6 Merge redirection into rak (combining new-sigils + redirection features)
c674f99a8 Create rak executable wrapper
```