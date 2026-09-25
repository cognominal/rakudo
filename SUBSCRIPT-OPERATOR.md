# SUBSCRIPT-OPERATOR.md — this repo

**Standalone design doc.** Written so a fresh Claude Code session (or human)
can pick this up cold, with no memory of the conversation that produced it.
If you're that fresh session: read this whole file before touching code —
sections 2 and 4 in particular contain corrections to the original design
idea that only came from actually testing things against a real build, and
skipping them will send you down paths already found to be dead ends.

Status: **Phases 1-3 done and passing.** `.1`
(`t/02-rakudo/dot-subscript-numeric.t`, 7/7), `.~expr`/`.#expr`
(`dot-subscript-sigil.t`, 8/8), and `.name`/`->name` gated by a new `.rak`
file extension (`dot-subscript-name.t`, 11/11 — see §5 Phase 3 for the LTM
pitfall hit and fixed along the way, and the "`.new`/`.Str`/... must become
`->new`/`->Str`/... in `.rak` mode" consequence). `.rakumod`/`.raku`/`.pm6`/
`.nqp` files, including all of `src/core.c/`, are completely unaffected —
only files ending in `.rak` get the new dotty semantics. Phase 4 (roast
triage redux) not started yet. Branch `new-sigils`.

## 0. Relationship to this branch's other work

This branch already implemented, tested, and merged two new sigils — `~`
(native `str`) and `#` (native `int`) — documented in `CLAUDE.md` at this
repo's root. That work is **done**: both sigils work end-to-end, are
covered by `t/02-rakudo/new-sigil-str.t` and `new-sigil-int.t` (18/18 each),
and CLAUDE.md records everything learned building them, including several
non-obvious grammar-engine gotchas (hardcoded `sigil eq '$'` checks, a
`$*QSIGIL`-triggered infinite loop, `token variable`'s numeric-capture and
"anonymous state variable" fallback branches needing explicit exclusions)
that are directly relevant background for this document. **Read CLAUDE.md
first if you haven't**, especially §0 (no compatibility policy — it applies
here too), §3.1 (why `~`/`#` are native, not boxed), and §7 (the original,
shorter version of this document's motivation — this file supersedes and
corrects §7's technical claims, per §2 below).

This feature is *why* the sigil work was done, per CLAUDE.md's §7 framing:
`~`/`#` exist specifically to make the subscript sugar in §1 below
resolvable at parse time. With that prerequisite done, this is next.

Target frontend, compatibility policy, and general approach are unchanged
from CLAUDE.md: **`src/Raku/*` (RakuAST) only**, no `src/Perl6/*` legacy
frontend work, **no compatibility gating** — breaking changes are accepted
by design, per CLAUDE.md §0.

## 1. Request

Let `.` work as a generalized subscript operator, inferring positional vs.
associative access (and literal vs. variable-driven) from what follows it:

```raku
@a.1.toto.~str.#int  ≡  @a[1]<toto>{~str}[#int]
```

| after `.`                | desugars to | subscript kind                            |
|---------------------------|-------------|--------------------------------------------|
| bare integer (`1`)        | `[1]`       | positional, literal index                  |
| bare identifier (`toto`)  | `<toto>`    | associative, literal (quoted-word) key     |
| `~expr` (a `~`-sigiled term) | `{~expr}` | associative, key from a `~`-sigiled value |
| `#expr` (a `#`-sigiled term) | `[#expr]` | positional, index from a `#`-sigiled value |

**Why `~`/`#` are the prerequisite, specifically:** Raku already lets a
*variable* drive a subscript today, but only with explicit brackets —
`.{$key}` for associative, `.[$idx]` for positional — because a bare
`$`-sigiled variable carries no static information about which kind of
subscript it should mean; the parser would need a runtime type check, which
isn't how Raku resolves grammar. `~foo`/`#foo` are the first variable forms
whose *sigil alone* guarantees the value's type (str vs. int), which is what
lets `.~foo`/`.#foo` desugar unambiguously to `{}`/`[]` *without* brackets
and without a runtime check. Generic `$foo` can't play this role.

**Scope note:** this spec covers `.~name`/`.#name` for a *bare* `~`/`#`-
sigiled variable reference, not an arbitrary expression starting with `~`/
`#` (e.g. not `.~(foo() ~ bar())`). Keeping the right-hand side to a single
bare term mirrors `.1` (a bare literal) and `.toto` (a bare identifier) —
every piece of the motivating example is a single token, not a sub-
expression. Generalizing to full expressions is a plausible future
extension, explicitly out of scope for the first implementation (§6).

**Parameterless method calls move to `->`:** `@a->toto` instead of
`@a.toto`. This is the piece that makes `.toto` available for `<toto>` at
all — see §2's correction and §4's risk writeup for why this is *not* the
low-friction move the original design assumed, and what it actually costs.

## 2. Grounding: how `.`, subscripts, and `->` work today — WITH A CORRECTION

Key spots in `src/Raku/Grammar.nqp` (line numbers as of this branch's HEAD
after the sigil work; re-check if `Grammar.nqp` has moved on):

- **`token postfixish`** (~2463-2502) is what tries, at each postfix
  position, method calls, postfix operators, and postcircumfixes in turn.
  Line ~2488 is already exactly the rule this feature needs to extend:
  ```
  | '.' <?[ [ { < ]> <OPER=postcircumfix>
  ```
  This is *why* `.[1]`, `.{key}`, and `.<key>` already work today, identical
  to `@a[1]`/`@a{key}`/`@a<key>` without the dot — confirmed directly:
  `@a.1` today gives a clean "Malformed postfix call" (not silently
  something else), and so do `.~s`/`.#n` (tested against this branch's own
  build, with `~`/`#` already real sigils) — **all of `.1`, `.~expr`,
  `.#expr` are unclaimed syntax today.** This is the *low-risk* two-thirds
  of the feature.
- **`token postcircumfix:sym<[ ]>`** (~2528), **`sym<{ }>`** (~2534),
  **`sym<ang>`** (~2540, the `<key>` form) are the actual subscript
  circumfixes `.1`/`.toto`/`.~expr`/`.#expr` need to desugar *into*. Read
  `src/Raku/Actions.nqp`'s corresponding `postcircumfix:sym<...>` action
  methods to see what AST node each one builds — the sugar's job is to
  construct the same AST, not invent new semantics.
- **`token dotty` / `dottyop` / `methodop`** (~2594-2673) is the method-call
  machinery. `dottyop` tries, in order: `methodop`, `colonpair`, then a
  catch-all for non-identifier postfix/postcircumfix forms right after `.`
  (`<!alpha> <postop> ...` — this is *already* how `.[`/`.{`/`.<` reach
  `postcircumfix` when `postfixish`'s own shortcut at line 2488 doesn't
  apply, e.g. after `.^`/`.?`/`.&` variants). `methodop` itself
  (~2650-2673) has three ways to name what's being called:
  - `<longname>` (~2652) — `.foo`, `.Foo::bar`. **This is the branch that
    unconditionally claims any bare identifier after `.`, args or not** —
    the thing that has to change.
  - `<?[$@&]> <variable>` (~2656) — **not** "call the method named by the
    string in this variable." Verified directly: `C.new.$m` where `$m` holds
    the string `"greet"` fails with `No such method 'CALL-ME' for string
    'greet'` — it means "invoke the *callable* held in this variable, with
    the invocant as an argument" (the `$`/`@`/`&` forms of `.&sub`-style
    invocation). Indirect dispatch *by name* is the separate quoted-string
    form below. Don't confuse the two when reading old design notes (CLAUDE.
    md's §7 conflates them slightly).
  - `<?['"]> <quote>` (~2657) — `."$name"()` — call the method whose *name*
    is this (interpolated) string. Verified working: `C.new."$m"()` calls
    the method named by `$m`'s value.
  - After the name, `<?[(]> <args>` (~2666) handles `.foo(args)` — args
    stay unaffected regardless of what happens to the no-args case, since
    `(` immediately after the name is not a subscript shape and nothing
    here needs to change for it.
  - The **no-args case** is line ~2669: `<!{ $*QSIGIL }> <?>` — matches
    zero-width, i.e. "a bare name is itself a complete method call." *This*
    is what has to stop being automatic for `methodop`'s `<longname>`
    branch, so `.toto` (no args) can mean `<toto>` instead.

**The correction — `->` is not free.** The original design note (CLAUDE.md
§7) claimed `->` "only appears in pointy-block signatures... repurposing it
as a postfix operator doesn't collide with anything existing." **This is
wrong**, found by actually grepping for `->` in the grammar instead of
assuming: `src/Raku/Grammar.nqp` already has
```
token postfix:sym«->» {
    <sym>
    [
      | $<bracket>=['[' | '{' | '(' ]
        { ... $/.obs('->' ~ $pair ~ ' as postfix dereferencer', '.' ~ $pair ~ ' to deref', ...) }
      | <.obs: '-> as postfix', 'either . to call a method, or whitespace to delimit a pointy block'>
    ]
}
```
(~2709-2729). This is a **deliberate, existing hard compile error** —
confirmed directly: `my $x = 5; $x->foo` today gives `===SORRY!=== Unsupported
use of -> as postfix. In Raku please use: either . to call a method, or
whitespace to delimit a pointy block.` It exists specifically to catch Perl
5 migrants writing `->` for method calls/dereferencing (Perl 5's spelling)
instead of Raku's `.`, and tell them the right spelling.

So `@a->toto` as "call method toto with no args" is not writing on a blank
page — it's **removing a helpful, deliberate Perl-5-migration error
message** and replacing that token's behavior entirely. That's an
acceptable trade under CLAUDE.md §0's no-compatibility policy — this repo
already accepts bigger breaks than "Perl 5 users get a worse first error
message" — but it is a real cost the original note didn't account for, and
worth flagging in whatever commit/PR description lands this, not just here.
It also means: this isn't "add a new token," it's "replace the body of an
existing token," a smaller diff than it sounds but a different kind of
change (you're deleting the `.obs` calls and the reserved bracket-forms
handling, not just adding an alternative).

## 3. Proposed semantics

- `.1` (postfix, one or more digits, no space after the dot) desugars to
  `[1]` — same AST as the corresponding `postcircumfix:sym<[ ]>` would
  build for a single-integer semilist. Only plain unsigned digit runs in
  the first pass (§6) — no negative numbers, no underscores-in-digits, no
  arbitrary expressions.
- `.toto` (postfix, bare identifier, **no** immediately-following `(` and
  no `:`-adverb-args) desugars to `<toto>` — same AST as
  `postcircumfix:sym<ang>` would build for a single bareword. `.toto(args)`
  and `.toto: args` are unaffected — still real method calls.
- `.~expr` / `.#expr`, where `expr` is a bare `~`/`#`-sigiled variable
  reference (§1's scope note — not a general expression), desugar to
  `{~expr}` / `[#expr]` respectively — same AST as the corresponding
  `postcircumfix:sym<{ }>` / `sym<[ ]>` would build with that variable
  reference as the (sole) semilist element.
- Parameterless method calls move to `->name` (`@a->toto`), replacing
  `token postfix:sym«->»`'s current obsolete-syntax-error body. `.name`
  (bare, no args) *always* means `<name>` after this change — no runtime
  fallback, no per-object dispatch decision, matching CLAUDE.md §0's
  general preference for compile-time-resolved behavior over clever
  runtime tricks.
- Whether `->name(args)` / `->name: args` (with arguments) should *also*
  work as an alternate spelling of `.name(args)`, for symmetry, is an open
  question for whoever implements this — recommended default: yes, make
  `->` a full alias of `.`'s existing method-call machinery (reuse
  `dottyop`/`methodop` wholesale for `->`, just gated so the *no-args* case
  is only reachable through `->`, never through `.`). This keeps the "two
  spellings, cleanly divided by whether there's an arg list" story simple,
  rather than leaving `->name(args)` as a dead end that only works one way.

## 4. Risks, ordered by severity

### 4.1 `.name` → `->name`: RESOLVED — gate it by file extension, not language-wide

The problem, restated precisely: `.name` bare is the *only* existing
spelling for a parameterless method call, used **constantly** — a rough
regex sweep of `src/core.c/` alone (the standard library, 162 files) found
on the order of 8,700 candidate bare-dot-identifier spots. A whole-language
change to what `.name` means is therefore not "big," it's **infeasible to
do correctly by hand in one pass**: text search can't reliably distinguish
a genuine bare call from `.name` followed by `:adverb(args)`, from a
multi-line arg list, from an indirect `."$name"()` call, from meta-
programming that builds method names as strings — the only fully reliable
way to know is to have a parser walk the code, which is circular (you'd
want the *new* grammar to tell you what it flags, which requires the change
to already exist). And a missed site doesn't fail to compile — it silently
becomes a subscript attempt at runtime, usually erroring somewhere far from
the actual mistake. Since `src/core.c/` is the compiler's own standard
library (self-hosted), a mistake here risks breaking the ability to build
at all, or producing a build that "succeeds" but is broken pervasively.

**The resolution: don't change what `.name` means language-wide at all.**
Gate the new behavior by the **source file's extension** — a new `.rak`
extension gets the new semantics (`.name` bare → `<name>`, `->name` for a
real parameterless call); the existing `.raku`/`.rakumod`/`.pm6`/`.nqp`
files keep today's behavior untouched, permanently. This means:
- **Zero rewriting of `src/core.c/` or anything else existing.** Those
  files keep their current extension, so the flag is simply off for them —
  no risk to the standard library or the self-hosting build.
- A `.rak` file can still call everything in the standard library fine — it
  just spells a parameterless call `->foo` instead of `.foo`. The *method*
  being called, defined in an unaffected `.rakumod` file, doesn't know or
  care how its caller spelled the call; only the caller's own file's
  grammar interpretation changes.
- This is **not** the "no compatibility gating" policy from CLAUDE.md §0
  being violated — that policy is about not preserving *old meanings of the
  same file's syntax* for compatibility's sake. This is different: a new
  extension is a new, separate opt-in surface, not two meanings coexisting
  for one spelling in one file. `.rak` files fully embrace the breaking
  change (§0's spirit); `.rakumod` files are simply a different, unrelated
  file type that this feature doesn't touch.

**How, concretely — confirmed against this codebase, not just asserted:**
- `%*COMPILING<%?OPTIONS><source-name>` already holds the path of the file
  currently being compiled (confirmed: read elsewhere in `Actions.nqp`, e.g.
  around line 929).
- `method comp-unit-prologue` in `Actions.nqp` (~line 420) is the existing
  per-compilation-unit setup hook — it's *already* where `$*LANGUAGE-
  REVISION` gets established (~line 450), the same "one dynamic variable,
  set once per file, checked at specific grammar decision points" pattern
  this needs, just keyed off the filename's extension instead of a `use
  v6.x` pragma.
- Add a new dynamic variable (e.g. `$*NEW-DOTTY-SEMANTICS`) set in
  `comp-unit-prologue` based on whether `source-name` ends in `.rak`.
  `methodop`'s no-args branch (§2, ~line 2669 as of this branch's HEAD)
  checks it to decide whether a bare `.name` (no args, no `:`-adverb-args)
  stays a method call or becomes `<name>` sugar instead.
- This is comparable in scope to Phases 1-2 (§5) — one new dynamic
  variable, one new check at one existing decision point — not a new
  category of risk. The `->` postfix-token conflict (§2's correction, the
  existing Perl-5-migration obsolete-error) still needs resolving
  separately and is unaffected by this — it still needs its body replaced,
  just now only reachable/meaningful when compiling a `.rak` file.

### 4.2 `.name` grammar change touches the single most common postfix form

Separate from the rewrite-scale problem above: `methodop`'s `<longname>`
branch (§2) is reached by *every* method call in the language, args or not.
The change needs to distinguish "no args, no `:`-adverb-args, not a
`->`-originated call" precisely — get the boundary wrong and either real
method calls with args stop working (very loud, caught immediately) or
`.name(args)` stops being recognized as "has args" correctly (subtler).
Write tests for the boundary cases specifically: `.name()` (explicit empty
parens — should this still be a method call, since parens are present?
recommend yes, `()` is an explicit arg-list shape even when empty, so
`.name()` calling a method stays intuitive and matches how `.name(args)`
behaves — only bareword `.name` with *nothing* after it becomes `<name>`),
`.name:`  (colon-adverb form with no actual adverbs), `.name.othername`
(chained — does the first `.name` still parse as a subscript when followed
by more dotty stuff?).

### 4.3 `->` repurposing costs a real, if narrow, diagnostic (§2's correction)

Covered in full in §2. Restated here for the risk list: this is not "free,"
it's "replace an existing Perl-5-migration hint with new functionality,"
acceptable under §0 but worth stating plainly rather than assuming away.

### 4.4 `.1` and `.~expr`/`.#expr` — low risk, confirmed unclaimed

Both directly verified against this branch's own build (§2): `@a.1`,
`.~s`, `.#n` are all clean "Malformed postfix call" errors today, meaning
there is no existing meaning to preserve or break. This is genuinely the
easy two-thirds of the feature. Implement these first (§5) — they exercise
the desugar-into-existing-postcircumfix-AST mechanism with zero of §4.1's
compatibility fallout, and prove the mechanism works before attempting the
one part of this feature that's actually dangerous.

### 4.5 Interaction with the sigil work's own lessons

CLAUDE.md's Phase 1/2 postmortems (§5 there) found real, non-obvious
grammar-engine gotchas — hardcoded sigil-character-set checks in several
files, a `$*QSIGIL`-triggered infinite loop, `token variable`'s fallback
branches needing explicit sigil exclusions. There is no specific reason to
expect an *identical* class of bug here, but the general lesson —
**grammar changes at a widely-shared choke point (here, `methodop`, used by
every method call in the language, the way `token variable` is used by
every variable reference) tend to have unexpected reach; grep broadly for
every existing user of the exact mechanism being changed, not just the
one call site the feature is imagined as adding to** — applies directly,
since `methodop`/`dottyop` is exactly this kind of choke point.

## 5. Implementation plan

Ordered by risk, per §4.4's recommendation — do the confirmed-safe parts
first, and don't start §5.3 until §4.1's open question (mechanical rewrite
vs. runtime fallback) has an actual decision behind it.

**Phase 1 — `.1` (literal positional index) — DONE.**
`t/02-rakudo/dot-subscript-numeric.t` is 7/7, verified against a rebuild of
this branch (`RAKUDO_RAKUAST=1`), with a full regression sweep (both sigil
test files still 18/18, `use Test` still loads, `@a[1]`/`@a.[1]`/`%h<a>`/
`%h.<a>`/`$x++`/plain method calls all unaffected).

What actually shipped, kept deliberately minimal relative to the original
bullet list:
- **Not a new `postcircumfix:sym<...>` candidate.** Every existing
  postcircumfix has a distinctive leading delimiter (`(`, `[`, `{`, `<`,
  `«`); `postfixish`'s bare `<OPER=postcircumfix>` alternative (§2, no dot
  required) tries all of them at *every* postfix position. A candidate
  matching bare digits, with no such delimiter, would make that same
  alternative fire on a bare number after any term — dot or not. So this is
  a **standalone token** (`token dotty-numeric-index`, next to the
  postcircumfix definitions for locality but not part of that proto),
  reachable only through a new, explicit `'.' <?before \d> <OPER=dotty-
  numeric-index>` alternative in `postfixish`, right next to the existing
  `'.' <?[ [ { < ]> <OPER=postcircumfix>` line.
- Actions.nqp builds `RakuAST::Postcircumfix::ArrayIndex` (same node
  `postcircumfix:sym<[ ]>` builds) with a `RakuAST::SemiList` wrapping one
  `RakuAST::Statement::Expression` wrapping one `RakuAST::IntLiteral` — same
  shape as the `my %h{Any}` shape-declaration example already commented in
  `variable-declaration.rakumod:1742` for exactly this "build a SemiList by
  hand" situation, worth finding and reading before writing this by hand
  from scratch. One non-obvious step: `$*LITERALS.intern-Int-by-base(...)`
  (the same call `token decint`'s own action uses to parse a digit string)
  returns a **raw `Int` value, not an AST node** — feeding it directly into
  `expression =>` fails with `Type check failed in binding to parameter
  '$expression'; expected RakuAST::Expression but got Int` (hit this on the
  first attempt). It needs one more wrap: `RakuAST::IntLiteral.new(...)`
  around the raw value.
- L-value assignment (`@a.1 = "X"`) and chaining (`@a.1.1`) work with zero
  extra code, confirming the "same AST node → same behavior for free"
  premise the plan predicted.
- The two "record, don't assert" edge cases (§6 — `.1e5`, `.1_0`) both
  fail to parse cleanly (`\d+` matches just the leading digit run, then the
  dangling `e5`/`_0` has nothing to attach to) rather than silently
  behaving as index `1`/`10` — a safe, if not especially friendly, outcome.
  Not pursued further; still explicitly out of scope (§6).
- Negative indices (`@a.-1`) confirmed to still cleanly fall through to the
  original "Malformed postfix call" error, unaffected by this change (`-`
  isn't consumed by the `<?before \d>` lookahead, so the new alternative
  never even attempts to match) — still explicitly out of scope (§6).

**Phase 2 — `.~expr` / `.#expr` (variable-driven subscripts) — DONE.**
`t/02-rakudo/dot-subscript-sigil.t` is 8/8 on the first working attempt (no
false starts this time — Phase 1's IntLiteral-wrapping lesson generalized
cleanly), verified against a rebuild with a full regression sweep (both
sigil test files 18/18, Phase 1's own test 7/7, `use Test` loads, existing
`%h<a>`/`%h.<a>`/`%h{$key}`/`@a.1`/method calls all unaffected).

What shipped, matching the plan closely:
- A second standalone token, `token dotty-sigil-index { <variable> }`,
  reached via a new `'.' <?[~#]> <OPER=dotty-sigil-index>` alternative in
  `postfixish`, right after Phase 1's numeric one. Unlike Phase 1's literal,
  no manual `\d+`-parsing was needed — `<variable>` already fully handles
  `~`/`#`'s sigil/twigil/desigilname parsing, so this token is a one-liner.
- The action reads `~$<variable><sigil>` to decide `Postcircumfix::
  HashIndex` (for `~`) vs. `::ArrayIndex` (for `#`), each wrapping
  `$<variable>.ast` in the same `SemiList`/`Statement::Expression` shell
  Phase 1 used. **One difference from Phase 1 worth remembering**:
  `$<variable>.ast` (via `compile-variable-access`) is *already* a proper
  `RakuAST::Expression` — no `IntLiteral`-style extra wrap needed, since a
  variable reference isn't a raw value the way `intern-Int-by-base`'s
  return was.
- L-value assignment for both `.~key = val` and `.#idx = val`, and chaining
  (`%h.~k.#i`, mixing this sugar with itself) all worked immediately, same
  "same AST node → same behavior for free" story as Phase 1.
- Confirmed `.{$key}`/`$`-sigil dotty behavior (the pre-existing "invoke
  the callable held in this variable" mechanism, `methodop`'s `<?[$@&]>
  <variable>` branch) is untouched — `$` was never added to the new
  alternative's lookahead, so `%h.$key` still means what it meant before.

**Phase 3 — `.name` → `<name>`, `->name` for method calls, gated by `.rak` — DONE.**
`t/02-rakudo/dot-subscript-name.t` is 11/11, verified against a rebuild of
this branch (`RAKUDO_RAKUAST=1`), with a full regression sweep (all four
prior test files still green — 18/18, 18/18, 7/7, 8/8 — `use Test` still
loads and its `# SKIP` TAP-comment output is unaffected, both frontends'
general sanity checks pass).

What actually shipped, per §4.1's file-extension-gated resolution
(`.rakumod`/`.raku`/`.pm6`/`.nqp`, including all of `src/core.c/`, are
completely unaffected — only a new `.rak` extension gets the new behavior):
- **Plumbing (two files outside `src/Raku/`):** `src/Perl6/Compiler.nqp`'s
  `command_eval` (the *shared* compiler-driver class, used by both
  frontends) now captures `@args[0]` into `%options<source-name>` when
  running a plain file (not `-e`) and `source-name` isn't already set — NQP
  itself computes an equivalent value in `HLL::Compiler.evalfiles` but never
  threads it into `%adverbs`, so Rakudo has to capture it independently.
  `comp-unit-prologue` in `src/Raku/Actions.nqp` then reads
  `%*COMPILING<%?OPTIONS><source-name>` and sets a new dynamic variable,
  `$*NEW-DOTTY-SEMANTICS`, to `1` iff the name ends in `.rak`, else `0`.
  `-e`/STDIN-piped code has no filename, so it always gets `0` (traditional
  semantics) — confirmed via diagnostic. `token comp-unit` in
  `src/Raku/Grammar.nqp` declares `:my $*NEW-DOTTY-SEMANTICS;` right next to
  `$*LANGUAGE-REVISION`, giving it the same "fresh per-compilation-unit
  value, doesn't leak across `use`/`EVAL` boundaries" scoping for free —
  confirmed empirically (a `.rak` file `use`-ing a `.rakumod` module keeps
  the module's own `.` semantics unaffected, and vice versa).
- **`.name` → `<name>` sugar:** a new standalone token,
  `token dotty-name-sugar { <identifier> <!before <.unspace>? '('> <!before
  <.unspace>? ':' \s> }`, matches a bare identifier only when nothing
  args-shaped follows it. Its action builds the exact node
  `postcircumfix:sym<ang>` builds for a single bareword key —
  `RakuAST::Postcircumfix::LiteralHashIndex` wrapping a hand-built
  `RakuAST::QuotedString`/`RakuAST::StrLiteral` pair (the same pattern
  already used elsewhere in Actions.nqp for `colonpair-variable`'s
  synthesized key, found by grep rather than reasoned out from scratch).
- **A genuine LTM pitfall, not present in Phases 1-2:** the natural way to
  wire this in — add `| <?{ $*NEW-DOTTY-SEMANTICS }> '.' <OPER=dotty-name-
  sugar>` as one more `|`-alternative in `postfixish`, next to the existing
  ones — compiles, and even *passes* for plain reads (`%h.toto`) and
  chaining (`%h.toto.1`). But it silently loses to `<OPER=dotty>` (the real
  method-call path) whenever a *subsequent* infix-shaped token follows —
  `%h.toto = 42` and `%h.toto != 5` both fell through to a real (and
  failing) method-call dispatch on `Hash`, even though the plain-read case
  worked. Root cause: Phase 1/2's sugars are never actually ambiguous with
  `<OPER=dotty>` at the grammar level — their leading character (a digit,
  `~`, `#`) can never start `methodop`'s `<longname>`/`<variable>`/`<quote>`
  branches, so NQP's LTM has no real tie to break. `.name` **is** a genuine
  textual overlap with `<OPER=dotty>`'s longname branch (same literal
  characters could go either way), and empirically, LTM's tie-break between
  two `|`-alternatives of equal matched length, one of them gated by a
  runtime `<?{ ... }>` assertion, is not reliably won by declaration order —
  it appears to depend on what character follows the shared prefix, which
  is exactly backwards from what the feature needs (only the trailing
  syntax, not the sugar itself, should decide the winner). **Fix:** stopped
  relying on LTM to arbitrate. Restructured `postfixish`'s postfix
  alternation as `[ || <?{ $*NEW-DOTTY-SEMANTICS }> '.' <OPER=dotty-name-
  sugar> || [ existing `|`-alternatives unchanged ] ]` — `||` is
  first-match/procedural, not LTM, so the sugar is tried deterministically
  first whenever the flag is set, and its own two negative lookaheads (not
  LTM) are what make it correctly decline for `.name(args)`/`.name: args`,
  falling through to the second `||` branch (the original LTM group,
  `<OPER=dotty>` included) unaffected. This is the one piece of this phase
  that needed an actual build-and-observe iteration to find; the fix is
  small but the *symptom* (works for reads, breaks specifically when
  followed by an operator) is a trap worth flagging for anyone touching
  this again.
- **`->name` real method call:** `token postfix:sym«->»` gained a new
  first-tried alternative, `<?{ $*NEW-DOTTY-SEMANTICS }> <.unspace>?
  <methodop(Mu)>` — deliberately `<methodop(Mu)>` directly, not the broader
  `<dottyop>`, because `dottyop`'s non-`methodop` branches would also let
  `->[`/`->{` through as aliases for `.[`/`.{` postcircumfix access, which
  stays erroring under the flag per the original plan (confirmed:
  `@a->[0]` still hits the pre-existing "Unsupported use of ->[] as postfix
  dereferencer" obsolete-syntax panic in `.rak` mode, unchanged). `Mu` is
  passed as `$*DOTTY` to match plain `.`'s (falsy) dispatcher behavior, not
  `.^`/`.?`/etc.'s. The corresponding action,
  `method postfix:sym«->»($/) { self.attach: $/, $<methodop>.ast; }`,
  forwards whatever AST `methodop` already built — mirroring exactly how
  `dottyop`'s own action forwards `$<methodop>.ast` for plain `.name(...)`
  calls, so `->name`, `->name(args)`, and `->name: args` all work via the
  *existing* method-call machinery, not a duplicate of it. When the flag is
  unset, this new alternative is never attempted (the `<?{ ... }>` guard
  fails first), so `.rakumod`/`.raku` files keep today's obsolete-syntax
  panics byte-for-byte, confirmed via regression test.
- **A design consequence worth flagging explicitly, not a bug:** because
  `.name` (no parens) now *always* means `<name>` in `.rak` mode, this
  includes every idiomatic parameterless call written that way —
  `Foo.new`, `$x.Str`, `$x.chars`, `$x.gist`, etc. — not just
  user-defined methods. `.rak`-mode code must write `Foo->new`, `$x->Str`,
  and so on for all of these; `.name` is unconditionally the subscript
  sugar there, with no special-casing for "well-known" method names. This
  surprised the first draft of the test fixtures (`Foo.new` and `->Str`
  both had to be fixed to `Foo->new`/`$x->Str` before the test suite
  passed) and is worth remembering as the single biggest ergonomic cost of
  opting a file into `.rak` mode — everything written the traditional way
  needs `.new`/`.Str`/`.chars`/... changed to `->new`/`->Str`/`->chars`/...
  wherever it's a bare, parameterless call.
- Tests: `t/02-rakudo/dot-subscript-name.t` writes real `.rak`/`.raku`
  fixture files to a per-run temp directory and runs each one in a
  subprocess with `RAKUDO_RAKUAST=1` explicitly set in the child's
  environment (mirroring the existing subprocess pattern in
  `t/02-rakudo/compiler-frontend-id.t`), since this phase's behavior is
  keyed off the compilation unit's own file extension — something `EVAL`
  has no notion of and every earlier test file in this project could
  therefore avoid. Covers: bare-read and assignment sugar, sugar/`<name>`
  value identity, `->name` real calls, `.name(args)`/`.name: args` staying
  real calls, `->[0]` staying an obsolete-syntax error, chaining with
  Phase 2's `.#`/`.~` sugar, and two `.raku`-extension regression cases
  (`.new`/`.bar` and `->bar`) confirming the unflagged path is untouched.

**Phase 4 — test-suite triage, redux**
Same shape as CLAUDE.md's Phase 4 (§5 there): once Phase 3 lands, re-run
the roast syntax-check sweep (methodology fully documented in CLAUDE.md's
Phase 4 writeup — clone roast to `t/spec`, syntax-check every file listed
in `t/spectest.data.6.c` against the new build, cross-reference failures)
and remove whatever newly breaks. Expect this to be a *larger* removal than
Phase 4 there — `.method` (parameterless) is an extremely common pattern,
far more common than unspaced `#comment`s were — so budget for that rather
than being surprised by it.

## 6. Explicitly out of scope for this pass

- `.~expr`/`.#expr` for anything other than a bare sigiled-variable
  reference (§1, §3) — no sub-expressions, no method chains on the right
  of the sigil.
- `.1` for anything other than a plain unsigned digit run — no negative
  numbers, no `1_000`-style separators, no computed indices (that's still
  `.[$idx]`'s job).
- Deciding `->[`/`->{`/`->(`'s fate beyond "leave them erroring" (§5 Phase
  3) unless a concrete need surfaces.
- Extending this sugar to any sigil beyond `~`/`#` — no generic "any fixed-
  type sigil after a dot" mechanism, just these two, matching CLAUDE.md's
  own out-of-scope stance on not generalizing the sigils themselves (its
  §6) beyond what was actually requested.
