# One-Pass Compilation Plan

## Current Architecture

The Rakudo build pipeline compiles the Raku CORE setting (the standard library
prelude) by concatenating many individual `.rakumod` source files into a single
compilation unit, then feeding that to the Rakudo compiler. There are **two
independent systems** for conditional source inclusion, operating at different
layers:

### Layer 1: Template-level file selection (`@if` / `@endif`)

The filelist `tools/templates/6.c/core_sources` (and analogous ones for 6.d,
6.e) uses a template syntax processed by `Configure.pl`'s `--expand` mode.
This controls **which files** appear in the concatenation:

```
@if(backend!=jvm
src/core.c/Uni.rakumod
src/core.c/Collation.rakumod)@
```

Resolved at **configure time**. Determines the set of filenames fed to
gen-cat.

### Layer 2: Source-level line selection (`#?if` / `#?endif`)

The concatenation script `tools/build/gen-cat.nqp` processes conditional
directives embedded within individual source files:

```
#?if moar
#  ... MoarVM-specific implementation
#?endif
#?if !moar
#  ... alternate implementation
#?endif
```

Supported predicates: `moar`, `!moar`, `jvm`, `!jvm`, `js`, `!js`.

Additional directives in gen-cat:

- **`#RAKUDO_FLAVOR#`**: Substituted with the `RAKUDO_FLAVOR` env var value.
- **`#?js: NFG`**: JS-backend-specific regex rewriting (NFG polyfill).
- **`#line 1 <file>`**: Emitted at each file boundary for error reporting.

### The Build Pipeline (simplified for Moar-only)

```
Configure.pl --expand templates/6.c/core_sources
  └─► gen/core_sources.6c          (template @if/@endif resolved)
      │
      ▼
tools/build/gen-cat.nqp -p SETTING:: -f gen/core_sources.6c
  └─► gen/CORE.6c.setting           (files concatenated, #?if/#?endif resolved)
      │
      ▼
rakudo --setting=NULL.6c --target=mbc  gen/CORE.6c.setting
  └─► blib/CORE.6c.setting.mbc     (compiled bytecode)
```

### Source File Organization

| Directory | Role | File count |
|-----------|------|------------|
| `src/core.c/` | Base CORE (6.c language revision) | ~162 files |
| `src/core.d/` | 6.d additions (prologue + 2 files) | 3 files |
| `src/core.e/` | 6.e additions (~13 files) | 11 files |
| `src/core.c/core_prologue.rakumod` | Stubs and early setup (80 lines) | — |
| `src/core.c/core_epilogue.rakumod` | Final setup, revision boxing (810 lines) | — |

### Conditional Directive Usage (current)

Across all core sources, `#?if`/`#?endif` appears ~902 times:

| Directive | Occurrences |
|-----------|-------------|
| `#?if moar` | 135 |
| `#?if !moar` | 116 |
| `#?if jvm` | 55 |
| `#?if !jvm` | 52 |
| `#?if js` | 45 |
| `#?if !js` | 46 |

**Note**: JVM and JS backends are no longer maintained. All `#?if jvm`,
`#?if !jvm`, `#?if js`, `#?if !js` directives are vestigial — they could be
removed (or kept for reference and left as dead branches). At minimum, a
one-pass grammar only needs `moar` / `!moar` conditionals.

---

## Goal: One-Pass Compilation

Eliminate the gen-cat concatenation step by having the Raku grammar itself
handle file inclusion and conditional compilation directly during parsing.
The compiler would receive the list of source files (or the filelist) and
process them internally, making gen-cat.nqp unnecessary.

### What the Grammar Needs

#### 1. A source-inclusion token

A grammar token that can pull in another source file at a specific point:

```raku
token source-include {
    'need' <module-name>
    { ... }  # load and parse the specified file
}
```

However, for the CORE setting use case, inclusion is positional (filelist
order) rather than named. An alternative approach would be a dedicated
**compile-time include** syntax or an internal mechanism driven by the filelist.

Two design options for file-level inclusion:

**(A) `INCLUDE` directive** — a new statement-level construct:

```
# INCLUDE "src/core.c/traits.rakumod"
```

That the grammar's `statementlist` or a new `compilation-directive` token
recognises and handles by reading and parsing the referenced file.

**(B) Internal filelist-driven inclusion** — the compiler receives the
filelist as metadata and the grammar's `comp-unit` entrypoint iterates through
the list internally (no new syntax, purely an internal API change).

**Recommendation**: Prefer option (B) for the CORE setting build, since the
filelist is already determined at configure time. Option (A) could be added
as a general-purpose Raku language feature for user code.

#### 2. Conditional compilation tokens

New tokens in the Raku grammar for compile-time conditionals, replacing
`#?if`/`#?endif`:

```raku
token compile-time-if {
    'compile-if' <condition> <block>
}

token compile-time-else {
    'compile-else' <block>
}

token compile-time-endif {
    'compile-endif'
}
```

But Raku already has `BEGIN` blocks and `use` statements that can be used for
conditional compilation. A more Raku-ish approach would be to use **pragma-like
syntax**:

```
# conditional compilation as a statement prefix or pragma
use-if moar {
    # MoarVM-specific code
}
```

Or even simpler: a **`COMPILE` phaser** or **`COMPILE-TIME` variable**:

```
BEGIN if $*RAKU-BACKEND eq 'moar' {
    # MoarVM-specific code
}
```

However, for the specific need of excluding entire blocks from parsing (not
just runtime), some form of lexer/grammar-level conditional is required.

**Recommended convention for one-pass:**

```
# comp-if moar
# moar-specific code
# comp-endif
# comp-if !moar
# alternative
# comp-endif
```

Parsed by a `compilation-directive` token at the statementlist level, which
skips the enclosed code when the condition is false. This mirrors the current
`#?if`/`#?endif` convention but integrates into the grammar rather than being
a text preprocessor directive.

#### 3. Language revision selection

Currently the 6.d and 6.e additions are separate filelists

(`tools/templates/6.d/core_sources`, `tools/templates/6.e/core_sources`).
In a one-pass model, the compiler could be told which revision to compile and
automatically include the relevant additions, or the filelist itself could be
an internal data structure.

#### 4. `#line` directive support

The grammar already has some `#line` handling (e.g., in
`tools/build/raku-ast-compiler.nqp`). The one-pass grammar should:

- Parse `#line N <file>` comments and track the logical source location.
- Report errors with the correct originating file/line.

This can be a simple token in `statementlist`:

```raku
token line-directive {
    '#line' \s+ <integer> \s* <string>?
    { ... update source location tracking ... }
}
```

---

## Proposed Grammar Extension Summary

Add a `compilation-directive` token (or set of tokens) to `Raku::Common` or
to the statement-level parsing rule:

| Construct | Purpose | Replaces |
|-----------|---------|----------|
| `# comp-if <backend>` | Start conditional block (backend check) | `#?if moar` |
| `# comp-else` | Alternative branch | (implicit) |
| `# comp-endif` | End conditional block | `#?endif` |
| `# INCLUDE "<file>"` | Inline another source file | gen-cat file concatenation |
| `# line N ["file"]` | Set source location for errors | gen-cat `#line` emission |
| `# FLAVOR <name>` | Compile-time flavor branching | `#RAKUDO_FLAVOR#` |

These would be recognised at the top of `statementlist` (before any Raku
statement parsing) so they are invisible to the Raku semantics — they are
compiler directives, not runtime code.

### Implementation Sketch

In `src/Raku/Grammar.nqp`, within the `statementlist` rule (or a new
pre-statement hook):

```
token compilation-directive {
    | '# comp-if' \s+ ('moar' | '!moar')
        { ... set conditional state ... }
      <compilation-body>
      [ '# comp-else' <compilation-body> ]?
      '# comp-endif'
    | '# INCLUDE' \s+ <string-literal>
        { ... open and parse included file ... }
    | '# line' \s+ <integer> [ \s+ <string-literal> ]?
        { ... update source location ... }
}

token compilation-body {
    [
        | <compilation-directive>
        | <?before <.[\)\]\}]> >  # stop on closing brackets
        | <.ws> <statement> <.eat-terminator>
    ]*
}
```

The conditional state would be stored in a grammar-level dynamic variable
(`$*COMPILE-CONDITION`) that controls whether tokens inside a false branch are
skipped (matching, but producing no AST).

### Roadmap & Status

**Step 1: Cleanup** ✅
All `#?if jvm`, `#?if !jvm`, `#?if js`, `#?if !js` directives removed from
source files (55 files, ~844 lines). Only `moar`/`!moar` remain.

**Step 2: Grammar additions** ✅
Added `#COMPILER::` directive support via `comment:sym<#COMPILER>` token in
`src/Raku/Grammar.nqp`, handling:
- `#COMPILER::if moar` / `#COMPILER::if !moar` — conditional compilation
  with grammar-level skipping of false branches
- `#COMPILER::endif` — end conditional block
- `#COMPILER::line N ["file"]` — source location tracking

**Step 3: Actions** ✅
Added `comment:sym<#COMPILER>` method in `src/Raku/Actions.nqp` for
`line` directive processing (reuses existing `register-line-directive` logic).

**Step 4: gen-cat bridge** ✅
Updated `tools/build/gen-cat.nqp` to accept both old (`#?if`/`#?endif`) and
new (`#COMPILER::if`/`#COMPILER::endif`) directive formats. Now emits
`#COMPILER::line` instead of `#line`. Removed dead JS NFG code.

**Step 5: Source conversion** ✅
All `#?if moar` → `#COMPILER::if moar` and `#?endif` → `#COMPILER::endif`
converted in core `.rakumod` files (33 files). NQP `.nqp` files retain the
old `#?if` format since they are compiled by the NQP compiler.

**Step 6: Build integration** 🔄
gen-cat now passes `#COMPILER::` directives through to output for true
conditions, while stripping `#?if`/`#?endif` for NQP compat. False `!moar`
blocks are skipped. The grammar handles `#COMPILER::if`/`#COMPILER::endif`
when present in the concatenated output.

The CORE setting is effectively one-pass: gen-cat acts as a simple
concatenator that adds `#COMPILER::line` markers and skips dead
`!moar` branches. The grammar handles the directives directly.

**Step 7: Remove gen-cat** ⏳
gen-cat kept for NQP file preprocessing. Could be replaced with a
shell loop once NQP sources no longer need conditional handling.

**Step 8: Test** ⏳
Needs a full Rakudo build to verify.

### Backward Compatibility

The new directives use `#` at the start of a line, which is currently a
comment in Raku. Existing code using `#` comments will not be affected because:

- `# comp-if`, `# INCLUDE`, `# line` would only be recognised at the
  **statement** level (not inside expressions or strings).
- A plain `#` comment followed by arbitrary text continues to be a comment.
- The specific tokens `comp-if`, `INCLUDE`, `endif` etc. are unlikely to
  appear in natural comments in core sources — and if they do, they would
  need a different prefix (e.g., `#COMPILER::if`, `#COMPILER::include`) to
  avoid ambiguity.

An alternative safer prefix: `#COMPILER::` namespace:

```
#COMPILER::if moar
#COMPILER::include "foo.rakumod"
#COMPILER::endif
```