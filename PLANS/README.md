# PLANS — design documents for the `rak` branch

The `rak` branch is a **combined mode** that merges three independent feature
branches. Each branch's design document lives here, named after the branch it
came from:

| Directory | Source branch | Feature |
|-----------|---------------|---------|
| `PLANS/new-sigils/` | `new-sigils` | new fixed-type sigils `~` (native `str`) and `#` (native `int`); dotty subscript sugar (`.1`, `.~expr`, `.#expr`, `.name` → `<name>`, `->name` → parameterless method call) gated to `.rak` files |
| `PLANS/redirection/` | `redirection` | shellish output redirection (`say foo >file.txt`) and naked-string literals for `.rak` files |
| `PLANS/onepass-compile/` | `onepass-compile` | one-pass CORE setting build; `#COMPILER::if/endif/line` directives; removal of vestigial JVM/JS backend conditionals |

Read the three documents in dependency order: `new-sigils/CLAUDE.md` first
(§0 compatibility policy applies branch-wide), then
`new-sigils/SUBSCRIPT-OPERATOR.md`, then `redirection/RAKFILE.md`, then
`onepass-compile/onepass-compile.md`.

## The unified gate: `$*RAK-SEMANTICS`

All rak syntax — new sigils' dotty sugar, redirection, naked strings — is
gated behind a single dynamic variable, `$*RAK-SEMANTICS`, set in
`comp-unit-prologue` (src/Raku/Actions.nqp):

- `.rak` file extension → `1`
- any other real file extension (`.raku`, `.rakumod`, `.pm6`, `.nqp`) → `0`
- no filename at all (`-e`, STDIN, REPL) → `RAKU_RAK_MODE` env var
  (set by the `rak` wrapper) decides; default `0`

The `rak` executable (repo root) is the argumentless equivalent: it sets
`RAKUDO_RAKUAST=1` and `RAKU_RAK_MODE=1` and runs the local `rakudo-m`.

## Semantics of the combined mode (as implemented on this branch)

### New sigils (`new-sigils`)

- `~name` — always a native-`str` scalar (the prefix `~` stringify operator
  is unaffected when a space or `(...)` follows).
- `#name` — always a native-`int` scalar; a bare `#` directly before an
  identifier-start (or twigil) char is a variable, not a comment.
- String interpolation of `~`/`#`-sigiled variables works in `qq ""` (roles
  `t1`/`i1`).
- Dotty sugar in `.rak` mode: `.1` → `[1]`, `.~expr`/`.#expr` →
  `{~expr}`/`[#expr]`, `.identifier` (no args) → `<identifier>`, and
  `->identifier` → a real parameterless **method call**. `.identifier(args)`
  and `.identifier: args` keep their ordinary method-call meaning.

### Naked strings (`redirection`, fixed on this branch)

In rak mode a **bare identifier is a naked string literal unless it is** a
known name. The disambiguation rule implemented (and corrected from the
redirection branch's original attempt, which never matched a known name):

```
bare identifier at term position (not followed by `(`) is a naked string
   ⟺  $*R.is-identifier-known(~name) is false
```

`is-identifier-known` resolves lexicals declared earlier *in the same unit*
and `&name`-lookup (`&say`, `&print`, `&plan`…), so:

- `say foo >out.txt` → `say` is the routine, `foo` is the naked string
- `Foo->new` → `Foo` is the (already declared) type, `->new` the method call
- `foo > bar` (spaces both sides) → comparison of naked strings; **no file**
  is ever created by a spaced `>`
- `status.file` → naked string `status` with the dotty `.file` subscript

The redirection branch's original guard used `is-identifier-known(..., :exact)`,
which cannot see setting routines (`&say` etc.) and therefore turned every
bareword — including `say` itself — into a naked string, making `.rak` files
uncompilable. The combined branch drops `:exact`.

### Redirection (`redirection`)

- `statement-mod-redir` (`'<' .ws '>' <redir-filename>` touching the
  filename, i.e. no whitespace after `>`) is recognized only in rak mode.
- Filenames: naked string, quoted string, or a `$var`; digit-initial filenames
  are rejected (they'd be numbers).
- Desugars `say x >f` to `open('f', :w).say(x)`.
- The `after-ws()` helper and the `infix:sym«>»` disambiguation assert on the
  **current match position** (`$/.pos()`). The original redirection branch
  used `self.pos()`, which returns the start of the whole parse (always 0 in
  practice), so the "is there whitespace after `>`?" check never worked and
  every `>` became ambiguous. The combined branch uses the match position.
- Input redirection (`<file` → read) is **not implemented** — see
  `redirection/RAKFILE.md` for its future design.

### One-pass compilation / `#COMPILER::` (`onepass-compile`)

- `tools/build/gen-cat.nqp` accepts both `#?if` (legacy) and `#COMPILER::if`
  directives and rewrites `#line` → `#COMPILER::line` when concatenating the
  CORE setting.
- Grammar-level `comment:sym<#COMPILER>` supports `#COMPILER::if moar|!moar`,
  `#COMPILER::endif` and `#COMPILER::line N file` in any source file.
- The original branch's `skip-to-compiler-endif` used a greedy
  `[ \N* \n ]*` loop; NQP grammar tokens can't backtrack such a group across
  newlines to re-sync on the `#COMPILER::endif` marker, so skipped blocks were
  still compiled. The combined branch makes the loop lazy (`*?`), fixing the
  skip. The original branch's true-condition branch was a bare `{ }` code
  block (which always matches); it is now a real `<?{ }>` assertion.

## Compatibility & test policy

Per `new-sigils/CLAUDE.md` §0: **no source compatibility with upstream
Rakudo.** Breaking changes are accepted by design; tests that assert old
behavior for deliberately changed syntax are omitted. Only genuinely new
syntax gets freshly written test files:

- `t/02-rakudo/new-sigil-int.t`, `new-sigil-str.t`, `dot-subscript-*.t`
  (new-sigils)
- `t/14-redirection/*.rak` + `gating.raku` (redirection; rewritten on this
  branch to use `->` method calls — the natural consequence of the dotty
  sugar — and to test only the implementable invariants)