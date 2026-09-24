# CLAUDE.md — this repo

This file carries design notes for in-progress language changes on this branch,
for Claude's (and future contributors') use. Sections 0-7 are not user
documentation. §8 is the exception: a user-facing draft, written the way this
would eventually read as Raku docs/release notes — see it for "what does this
do for me," and the rest of the file for "how/why is it built this way."

## Feature: new fixed-type sigils `~` (Str) and `#` (int)

Status: **Phases 1-2 implemented and passing (§5)** — both sigils work
end-to-end (`t/02-rakudo/new-sigil-int.t`, `new-sigil-str.t`, 18/18 each),
verified against a from-scratch build of this branch run with
`RAKUDO_RAKUAST=1`. Phases 3-4 (attributes/introspection audit,
test-suite triage) not started. Branch `new-sigils`.

Target: **Rakudo's RakuAST frontend (`src/Raku/*`) only.** The legacy
QAST-generating frontend (`src/Perl6/*` — a naming holdover from before the
Perl6→Raku rename) is explicitly **not** a target for this feature; see §4.4.

### 0. Compatibility & test policy

**This project does not maintain source compatibility with upstream Rakudo.**
Breaking changes to existing syntax/semantics are acceptable and expected —
don't design around preserving old meanings, don't gate new syntax behind a
language-revision bump or an `experimental` pragma for compatibility's sake,
and don't spend effort trying to make an old and a new meaning of the same
spelling coexist. Where §4 below discusses compatibility risk, read it as
"here's what breaks" (useful to know), not "here's what we must prevent."

Test-suite consequence: this repo's tests for existing behavior are **symlinks
to upstream Rakudo's existing test files**, kept as long as they still pass.
A test that would now fail because the behavior it checks was deliberately
changed is **omitted** (the symlink is simply not added / is removed), not
rewritten to assert the new behavior and not fixed to preserve the old one.
Only genuinely new syntax/semantics get freshly written test files — see the
two under `t/02-rakudo/` for the sigils themselves (`new-sigil-str.t`,
`new-sigil-int.t`). There is no separate "regression guard" test file for
old `~`/`#` operator or comment behavior; that's exactly the kind of thing
this policy says to let break and drop, not defend.

### 1. Request

Add two new sigils:

- `~name` — always a native-`str`-typed scalar variable (not boxed `Str`).
- `#name` — always a native-`int`-typed scalar variable (not boxed `Int`).

Both are native, symmetrically — `~name` is a plain string, `#name` is a
plain integer, neither wrapped in a `Scalar` container. Earlier drafts of
this spec had `~` map to boxed `Str` and framed the `~`/boxed-`Str` vs.
`#`/native-`int` split as a deliberate asymmetry; that's superseded — `~` now
matches `#` in being native. See §3.1 for why dropping the
`Scalar`-container/reference machinery is fine for both sigils, not just `#`.

**Mnemonics** (worth repeating in user docs and when explaining the choice):
- `~` → string: Raku already uses `~` for everything string-flavored — infix
  `~` is string concatenation (join), prefix `~` is string coercion, `~~`/`~=`
  follow suit. A `~`-sigiled variable is "the string one."
- `#` → integer: `#` conventionally denotes a number/count ("item #3",
  "#items"), i.e. an integer. A `#`-sigiled variable is "the number one."

Because the sigil *is* the type, an explicit type in the declaration is
redundant at best and contradictory at worst, so it's a compile-time error to
write one (`my Str ~name`, `my int #name`, and `my Int #name` are all
illegal, not just the redundant-match cases). A `where` constraint is still
allowed, since it doesn't change the nominal type.

Consequence: since `#name` (no space) becomes a term, plain end-of-line
comments must require a space after `#` (`# like this`) so `#name` isn't
swallowed as a comment. `#|...`, `#=...`, `` #`(...)` `` stay comment forms
regardless (see §4.2).

This work is also a **prerequisite for a follow-on feature**: `.` as a
generalized subscript operator (see §7). Keep that dependency in mind when
choosing implementation details here — in particular, §4.1's `~`-vs-operator
ambiguity and the postfix-dot grammar interact (§7), so the resolution
chosen there constrains what `.~expr` can mean later.

### 2. Grounding: how sigils work today

Two parser frontends define the grammar, but only one is this feature's target:

- `src/Raku/Grammar.nqp` / `src/Raku/Actions.nqp` / `src/Raku/ast/*.rakumod` —
  **the RakuAST frontend — this is Rakudo, and it's the target.** Active
  development (RakuAST lowering, etc.) is happening here per recent commit
  history.
- `src/Perl6/Grammar.nqp` / `src/Perl6/Actions.nqp` — legacy QAST-generating
  frontend, near-duplicate of the above, named for the pre-rename "Perl6"
  compiler. `token comment` and `token sigil` exist in both files, but
  **this feature does not target it** (see §4.4).

The rest of this doc cites `src/Raku/*` line numbers exclusively.

Key spots:

- `token sigil { <[$@%&]> }` — `src/Raku/Grammar.nqp:5455`. One-char class;
  adding `~`/`#` here is the entry point.
- `token variable { ... <sigil> <twigil>? <desigilname> ... }` —
  `src/Raku/Grammar.nqp:3839`. Already generic over sigil, needs no structural
  change once `sigil` accepts the new chars.
- **`~` is already a twigil**: `token twigil:sym<~> { <sym> <?before <alpha>> }`
  at `src/Raku/Grammar.nqp:5463`, used for sublanguage/slang variables like
  `$~MAIN`. Grammatically a twigil only appears *after* a sigil match
  (`$`,`@`,`%`,`&`), so `$~foo` (sigil `$`, twigil `~`, name `foo`) and a new
  bare `~foo` (sigil `~`, name `foo`) don't parse-collide — but they are
  visually confusable and worth a second opinion from someone who knows the
  slang-variable feature's actual usage before shipping.
- Comment tokens, `src/Raku/Grammar.nqp:5839-5866`:
  ```
  token comment:sym<#>       { '#' {} \N* }
  token comment:sym<#`(...)> { '#`' <?opener> <.quibble(...)> }
  token comment:sym<#`>      { '#`' <!after \s> <!opener> <.typed-panic(...)> }
  token comment:sym<#|>      { '#|' \h $<attachment>=[\N*] }
  token comment:sym<#|(...)> { '#|' <?opener> ... }
  token comment:sym<#=>      { '#=' \h $<attachment>=[\N*] }
  token comment:sym<#=(...)> { '#=' <?opener> ... }
  ```
  Only `comment:sym<#>` (plain line comment) is ambiguous with a `#`-sigil
  term — the `` #` ``/`#|`/`#=` forms are followed by punctuation that can
  never start a `desigilname`, so they stay unambiguous no matter what we do
  to plain `#`.
  Comments are pulled in via `token horizontal-whitespace` at
  `src/Raku/Grammar.nqp:5820-5827` (`\h* <.comment>`), i.e. anywhere
  whitespace is legal, not just at statement/term boundaries.
- String interpolation is sigil-keyed via paired roles, e.g.
  `src/Raku/Grammar.nqp:6278-6340` (`s1`/`s0` for `$`, `a1`/`a0` for `@`,
  `h1`/`h0` for `%`, `f1`/`f0` for `&`), composed for `qq` at
  `src/Raku/Grammar.nqp:6388`:
  `role qq does b1 does s1 does a1 does h1 does f1 does c1 { ... }`.
  New sigils need the same treatment (`t1`/`t0` for `~`, `i1`/`i0` for `#`)
  or they simply won't interpolate in double-quoted strings.
- Per-sigil default type/container logic lives in
  `src/Raku/ast/variable-declaration.rakumod`:
  - `IMPL-SIGIL-LOOKUP` (line 180-190) maps `@`→`Positional`, `%`→`Associative`,
    `&`→`Callable` (used as the bind-constraint role); `$` isn't in the map
    and falls through to unconstrained.
  - `IMPL-CALCULATE-TYPES` (line 196-316) is the real per-sigil branch: `@`
    (208), `%` (229), `&` (256), else (265, today only `$`) sets
    `container-base-type`/`container-type`/`bind-constraint`/`default`. Both
    `~` and `#` are **not** new branches here — see next bullet.
  - `~` and `#` are both "`$` with `$of` forced to a native type object"
    (`str` for `~`, `int` for `#`), not new boxed-Scalar branches. The
    relevant code already exists for this, in `IMPL-CONTAINER` (line
    336-361):
    ```
    if $sigil ne '@' && $sigil ne '%' {
        if nqp::objprimspec($of) {
            nqp::die("Natively typed state variables not yet implemented") if self.scope eq 'state';
            return nqp::null unless $attribute;
        }
        $container-type := Scalar;
    }
    ```
    i.e. when `$of` has a primitive spec (native `int`/`num`/`str`), no
    `Scalar` container object is created at all — the variable lives as a
    raw native local, exactly like today's explicit `my int $x` / `my str $x`.
    Making `~name`/`#name` mean native `str`/`int` is a matter of feeding
    `str`/`int` in as `$of` for `~`/`#`-sigiled declarations respectively,
    not writing new container logic — but it also means both **inherit
    existing native-scalar limitations**, notably the `state` NYI death
    above (confirmed live for both `state str $x` and `state int $x` today,
    so `state ~x`/`state #x` won't work until that's fixed, independent of
    this feature), no `Mu`/undefined state (natives default to `""`/`0`,
    can't hold `Nil`), and attribute (`has ~x`/`has #x`) vs. non-attribute
    behavior already forking at `return nqp::null unless $attribute` above.
    Verified against a stock Rakudo build: `my str $x;` defaults to `""`,
    reassignment works, and `has str $.x`/`has int $.x` (public native
    attributes) already work today — see §3.1 for why native (no container)
    is the right choice for both sigils, not a compromise specific to `#`.
  - The explicit-type/`is Type` path (line 271-292,
    `IMPL-HAS-EXPLICIT-CONTAINER-BASE-TYPE`) is exactly the mechanism to
    **reject** for `~`/`#`: if a sigil is `~` or `#`, any explicit type
    (`Str`, `int`, `Int`, ...) or `is Type` must be a compile error, not
    silently accepted.
- Actions-level plumbing (`compile-variable-access`, `sigil-to-context`,
  `contextualizer-for-sigil` in `src/Raku/Actions.nqp:3040-3231`) is already
  generic over sigil string and needs no new branches — `~`/`#` fall into the
  existing "not `@`/not `%`" = Item-context default.
- Parameters/signatures have their own sigil-aware code in
  `src/Raku/ast/signature.rakumod` (needs the same default-type wiring so
  `sub f(~$x)`... — actually `sub f(~x)` — works).

### 3. Proposed semantics

- `~name` declares/refers to a native-`str` scalar — no `Scalar` container
  object (see §2), value defaults to `""`, cannot be `Nil`/undefined, and
  currently cannot be `state`-scoped (inherits the existing native-scalar
  `state` NYI). This is the same semantics as today's `my str $x`, just
  spelled with the sigil instead of an explicit type.
- `#name` declares/refers to a native-`int` scalar — no `Scalar` container
  object (see §2), value defaults to `0`, cannot be `Nil`/undefined, and
  currently cannot be `state`-scoped (inherits the existing native-scalar
  `state` NYI). This is the same semantics as today's `my int $x`, just
  spelled with the sigil instead of an explicit type.
- `my Str ~x`, `my str ~x`, `my int #x`, `my Int #x`, `my ~x is Str`,
  `my Foo ~x`, etc. are all compile-time errors ("sigil `~`/`#` already
  implies a type; remove the explicit type"). One new typed exception, e.g.
  `X::Syntax::Variable::SigilImpliesType`, covers both the redundant-match
  case (`my str ~x`, `my int #x`) and the conflicting-mismatch case
  (`my Str ~x`, `my Int #x`, `my Str #x`) — the user's spec treats them the
  same ("can't be typed"), so don't special-case "but you named the same
  type".
- `~name where *.chars > 0` remains legal — `where` adds a runtime
  refinement, it isn't a type in the sigil sense.
- Applies to `my`/`our`/`state`/`has`/`HAS` scopes and to signature
  parameters, symmetrically with `$`.

#### 3.1 Why native, not boxed — references aren't needed for subscripting

`$`-sigiled variables are backed by a `Scalar` container object precisely
*because* Raku wants more than "holds a value" from them: a `Scalar` lets a
variable be re-bound to a different value's storage (`:=`), passed into a
sub by reference so the callee can mutate the caller's variable (`is rw`),
and generally be aliased so two names can refer to the same storage slot.
None of that is what `~name`/`#name` are for.

Their entire reason to exist (§1, §7) is to drive the new `.` subscript
operator unambiguously: `.~expr` picks `{}` because `~expr`'s sigil
guarantees a string, `.#expr` picks `[]` because `#expr`'s sigil guarantees
an integer. That's it — a subscript position **reads** the value once, to
decide which key or index to hit, and moves on. It never needs to:
- write back through the subscript expression itself (`@a[$i] = 5` mutates
  the *array slot* `$i` names, never `$i` itself),
- keep the container being subscripted holding a live alias to the variable
  that supplied the key/index, or
- hand the key/index off to something else that expects to mutate it by
  reference.

So the `Scalar` container's entire reason for existing — supporting
aliasing/rebinding/mutation-by-reference — is dead weight for this use case.
A plain native value (`str`/`int`) is not a lesser version of a `$` variable
for this purpose, it's the *right-sized* one: cheaper (no boxing, no
container allocation), and it still supports ordinary local reassignment
(`~name = "new value"` — confirmed: reassigning a native lexical works fine
today) — the only thing genuinely given up is aliasing/rw-by-reference,
which a subscript key/index was never going to use.

This is also why it doesn't matter that Rakudo's native-lexical
implementation happens to support some binding today (`my str $x = "a"; my
$y := $x; $y = "z";` does mutate `$x` too, confirmed against a stock build) —
that's an implementation detail of native locals, not something `~`/`#`
depend on or should be designed around. The argument for dropping the
`Scalar` container isn't "natives literally can't be aliased," it's "the
subscript use case never asks for aliasing in the first place," so there's
nothing lost by choosing the simpler representation.

Two further observations back this up:
- **References are for composite data.** In practice, taking a reference
  (aliasing, `is rw`, binding) matters mostly for composite data structures —
  arrays, hashes, objects — where sharing the structure is the point. A
  string or an integer used as a key/index is a scalar *value*; there's
  rarely a reason to share its storage, so losing reference semantics on
  `~`/`#` costs essentially nothing.
- **Native `int` range is enough for indices.** `#` being native `int` rather
  than arbitrary-precision `Int` looks like a restriction, but an index
  larger than a native int is essentially never used for subscripting — a
  dense array that big can't exist in memory. The only realistic exception
  is sparse ("holey") arrays with huge, mostly-empty index ranges; code that
  needs that can keep using a `$` variable with explicit brackets
  (`@a[$big]`).

If some future use of `~`/`#` outside subscripting turns out to genuinely
need alias/rebind/rw-parameter semantics, that's a sign it should have been
an explicitly-typed `$` variable (`my Str $x` / `my Int $x`) instead — `~`/
`#` are not meant to be general-purpose replacements for typed `$`
variables, just the fixed-type, subscript-driving pair described in §1.

### 4. Risks, ordered by severity

#### 4.1 `~` collides with existing operator uses of `~` — low, by policy (§0)

`~` today is, all at term/operator level, not just twigil:
- infix concatenation: `$a ~ $b`
- prefix stringify/coercion: `~$x`, and critically `~foo` (stringify the
  result of calling/resolving bareword `foo`)
- `~~` smartmatch, `~=` concat-assign
- the `~` twigil (§2)

`~foo` **already parses today** as prefix-`~` applied to term `foo`. That
reading and "the `~`-sigiled variable named `foo`" are a genuine grammar
ambiguity — same input, two meanings — and under a compatibility-preserving
design this would need an LTM feasibility spike (whether `token variable`
matching `~foo` as one unit beats the 1-character prefix-operator token
`~` across the `<prefix>`/`<term>` proto-hierarchy boundary that NQP's
generic `EXPR` operator-precedence method combines them through).

Per §0, that spike isn't required: **`~` directly followed by an
identifier-start character, with no space, is defined to always mean the
`~`-sigiled variable.** The old bareword-stringify reading of that exact
spelling (`~foo` meaning `~(foo())`) is simply dropped — write `~ foo` (with
a space) or `~(foo)` if that meaning is still wanted somewhere. `~$x`
(stringify a `$`-sigiled variable), `$a ~ $b` (infix, space-delimited),
`~~` (smartmatch, distinct two-char token), `~=` (distinct token), and the
`~` twigil (only ever reachable *after* an existing sigil, e.g. `$~MAIN`,
never at the start of a term) are all unaffected — none of them have an
identifier immediately after a bare `~` at a term-starting position, so this
rule doesn't touch them.

#### 4.2 `#` vs. plain-`#` line comments — medium, solvable

Requiring `# ` (space) for `comment:sym<#>` and treating bare `#identifier`
as the sigil is mechanically simple (tighten one token,
`src/Raku/Grammar.nqp:5841-5843`), but note the special comment forms
(`` #` ``, `#|`, `#=`) are untouched either way (§2), and this is silent on
what `#123`, `#!/usr/bin/env raku` (shebang), or `#----divider----` (a
banner-comment style some code uses with no space) should do — `#123` and
`#----` can't be valid sigil terms either (digit/punct can't start a
`desigilname`), so they'd need to still fall back to comment-parsing, or
become hard errors. Recommend: `comment:sym<#>` matches when `#` is followed
by whitespace, EOL, *or* a character that cannot start a `desigilname`
(covers shebangs and banner comments); only `#` immediately followed by an
identifier-start char is reinterpreted as the sigil. This is a smaller,
safer rule than a blanket "space always required," and worth stating
explicitly rather than assuming the user's literal "starts by `# `" wording
is exhaustive.

#### 4.3 Backward compatibility — accepted breakage, not a design constraint (§0)

Both changes are backward-incompatible for existing source. Recorded here as
known fallout, not as something to engineer around (§0 — no language-revision
gating, no `experimental` pragma, no dual-meaning support):
- Any existing code with a bareword-stringify use of `~word` (rare but not
  impossible) changes meaning now that `~` is a sigil unconditionally (§4.1).
- Any existing comment written as `#word` with no space (common — section
  dividers, commented-out code, TODO markers) either becomes a compile error
  (undeclared `#`-sigiled variable) or silently changes meaning, now that `#`
  is a sigil unconditionally (§4.2).

Practical upshot for the test suite (§0): any upstream Rakudo test that
exercises one of these two now-defunct meanings is expected to start failing
and should be omitted (not symlinked in), rather than fixed or preserved.

#### 4.4 Two frontends — resolved: target Rakudo/RakuAST, not legacy Perl6

`src/Perl6/Grammar.nqp` is a near-duplicate of `src/Raku/Grammar.nqp`
(both define `token comment`, `token sigil`, independently). **Decision:**
target is Rakudo — the `src/Raku/*` RakuAST frontend — only. `src/Perl6/*`
(the legacy QAST frontend, carrying the pre-rename "Perl6" name) is left
unsupported for this feature; do not add `~`/`#` to its `token sigil` or
touch its `token comment`. If legacy ever needs parity, that's a separate,
explicitly-scoped follow-up, not part of this branch.

### 5. Implementation plan

Ordered; each phase assumes the previous one landed and its tests pass. No
spike/feasibility phase is needed for `~` (§4.1) now that compatibility with
the old bareword-stringify reading isn't a requirement (§0) — the
disambiguation is a design decision (sigil wins), not an open question.

Test-first (§0, and the request that started this): `t/02-rakudo/new-sigil-str.t`
and `t/02-rakudo/new-sigil-int.t` already exist and are the acceptance target
for Phases 1-2 — they currently fail (nothing is implemented yet) and should
go green as each phase lands.

**Phase 1 — `#` sigil + comment-spacing rule — DONE.** `t/02-rakudo/
new-sigil-int.t` is 18/18. What actually shipped (commit "Phase 1 complete:
# sigil fully wired, 18/18 tests passing"), beyond the bullets originally
planned here:
- `#` forcing native `int` needed more than feeding `int` in as `$of`: six
  places had `sigil eq '$'` hardcoded as the native-scalar gate (lexical
  declaration codegen, `state` NYI check, bind-type check, lvalue lookup
  scope, local-lowering decline, plus one in `variable-access.rakumod` and
  one in `code.rakumod`) — all now go through a shared
  `IMPL-SIGIL-CAN-BE-NATIVE` predicate instead of the literal comparison.
- A bareword native-type keyword (`int`) written directly in this
  bootstrap-compiled `.rakumod` resolves to NQP's own lower-level native
  (`NQPNativeHOW`, no `.mro`), not the Raku-level one (`Perl6::Metamodel::
  NativeHOW`) that `my int $x` gets via the resolver — forcing `$of` needs
  the resolved value (`$!forced-native-int` in `variable-declaration.
  rakumod`, resolved once in `PERFORM-BEGIN`), not the bare literal.
- The `SigilImpliesType` check has to run in two places, not one: the
  explicit-type half in `PERFORM-BEGIN` *before* the `where`-clause subset
  synthesis there (which unconditionally overwrites `$!type`, so checking
  after misfires on `my #x where * > 0 = 5`), and the `is Type`-trait half
  in `PERFORM-CHECK` (traits aren't processed until `PERFORM-BEGIN` runs).
- `where` on a native sigil isn't actually exercisable at all yet — Rakudo
  doesn't support subsets of native types currently ("Subsets of native
  types not yet implemented", confirmed identical for `my int $x where
  ...`), so `#x`/`~x where COND` die unconditionally, regardless of whether
  the value would satisfy the condition. Not a bug in this feature; just
  another inherited native-scalar limitation alongside the `state` one.
- `#` inside a `qq` string needed a "looks like a sigil" guard (identifier,
  or twigil+identifier, directly after, no space) before even attempting
  interpolation — a literal `#` is extremely common in ordinary string
  content (this broke loading `lib/Test.rakumod`'s own TAP line, `"1..0 #
  Skipped: $reason"`, before the guard was added). Also: setting `$*QSIGIL`
  to `'#'` in that interpolation role hung the parser (infinite loop); root
  cause untracked, so the role just omits it.
- **Known gap, not yet audited:** `#`-sigiled signature parameters
  (`sub f(#x)`) read/write correctly but haven't been confirmed to actually
  be *native* the way `my #n` now is — `RakuAST::ParameterTarget::Var` has
  no container-creator machinery of its own to force through. Candidate
  first task for Phase 3.

**Phase 2 — `~` sigil — DONE.** `t/02-rakudo/new-sigil-str.t` is 18/18.
Mirrored Phase 1's wiring for native `str`, plus the part Phase 1 didn't
need: making §4.1's design decision (bare `~identifier` always the sigil)
real in the grammar (commit "Phase 2 complete: ~ sigil fully wired, 18/18
tests passing"):
- `token prefix:sym<~>` gets the negative lookahead (identifier, or
  twigil+identifier, directly after — same shape as the `#`-vs-comment
  guard) that makes it decline in favor of `term:sym<variable>` claiming
  `~foo`. `~$x`, `~42`, `~(...)`, infix `~`, `~~`, `~=`, and the `~` twigil
  are all untouched (none of them have an identifier directly after a bare
  `~` at a term-starting position).
- That alone wasn't sufficient: `token variable` has three sigil-generic
  fallback branches — `$0`-style numeric capture, `$<foo>`-style match-name
  capture, and a bare-sigil "anonymous state variable" catch-all (a real,
  pre-existing feature: bare `$`/`@`/`%`/`&` alone as a term references the
  most recent `state` declaration of that sigil in scope). None of these
  are meaningful for a fixed-type native sigil, and left unexcluded the
  catch-all specifically broke `~42`: with the other two branches declined,
  it fell through to matching *just* the `~` as an anonymous state
  variable, leaving `42` dangling — and since state can't be native, that
  crashed with the `state` NYI instead of leaving `42` for `prefix:sym<~>`
  to stringify. All three branches now explicitly exclude `~`/`#` (`#`
  didn't strictly need it — `comment:sym<#>` already keeps `#42`/bare `#`
  from ever reaching `token variable` — but excluded for consistency rather
  than relying solely on that).
- Same interpolation guard and `$*QSIGIL` omission as `#`'s `i1`, applied
  proactively to `~`'s `t1` rather than rediscovering the same two bugs.
- Same known gap as Phase 1: `~`-sigiled signature parameters aren't
  confirmed native either.

**Phase 3 — attributes & introspection**
- First task: audit whether `#x`/`~x` signature parameters are actually
  native, not just correct-by-value — Phase 1/2 confirmed the latter but not
  the former (see the known-gap notes on both phases above).
- `has ~x` / `has #x` — already confirmed working (both test files, "has
  ~.x"/"has #.x" attribute tests), so this part is done, not just planned.
- Still open: `.sigil`, `.VAR`, `.perl`/`.raku` round-tripping, and any
  place that enumerates the sigil character set literally (grep for
  `'$@%&'`-style string constants beyond the ones found in §2 — there may be
  more, e.g. in `Metamodel`, MOP introspection, or `core.c` setting
  sources). Also unaudited: the two cosmetic `'$@%&'`-literal sites found
  while implementing Phase 1 (an error-message heuristic for common P5-isms
  at `Grammar.nqp:3517`, and a Levenshtein typo-suggestion cost function at
  `resolver.rakumod:1032`) — harmless as-is, `~`/`#` just won't get the
  nicer wording/suggestions those give `$@%&`.

**Phase 4 — test-suite triage (§0)**
Run this repo's existing `t/`/spec-style suite, symlink in whatever upstream
tests still pass unmodified, and omit (don't symlink, or remove) whatever now
fails because it asserted one of the dropped old meanings (§4.3). Then docs
and a NEWS/changelog entry noting the breaking changes plainly (since they're
intentional, not gated).

### 6. Explicitly out of scope for MVP

- Boxed `Str`/`Int` as an alternative reading of `~`/`#` — both sigils are
  native (§1, §3.1); don't hedge by making it configurable.
- Any `Scalar`-container capability for `~`/`#` — aliasing (`:=`), `is rw`
  parameters relying on container identity, rebinding. §3.1 covers why this
  is a deliberate cut, not an oversight; a plain `$` with an explicit type
  is the escape hatch for code that genuinely needs those.
- Sigils for other types (e.g. a hypothetical `Num` or `Bool` sigil) — not
  requested, don't generalize preemptively.
- Changing the `~` twigil's behavior.
- The `.` subscript operator itself (§7) — not part of this branch's scope,
  documented here only because it motivates some of the choices above.

### 7. Follow-on motivation: `.` as a generalized subscript operator

Not part of this feature, but the stated reason it's being done first — record
it so the design choices above (especially §4.1's `~` resolution) are made
with this in mind, not discovered to conflict with it later.

**Proposed equivalence:**
```
@a.1.toto.~str.#int  ≡  @a[1]<toto>{~str}[#int]
```
i.e. after a `.`, the kind of subscript is inferred from what follows it:

| after `.`         | desugars to  | subscript kind                          |
|--------------------|--------------|------------------------------------------|
| bare integer (`1`)  | `[1]`        | positional, literal index                |
| bare identifier (`toto`) | `<toto>` | associative, literal (quoted-word) key |
| `~expr` (Str sigil)  | `{~expr}`   | associative, key from a `~`-sigiled value |
| `#expr` (int sigil)  | `[#expr]`   | positional, index from a `#`-sigiled value |

**Resolving the biggest blocker — `.toto` vs. method calls:** parameterless
method calls move to `->toto` (`@a->toto`), freeing plain `.toto` to mean
`<toto>` unconditionally, with no runtime `FALLBACK` trick and no ambiguity
with method dispatch. Method calls *with* arguments are unaffected and keep
`.toto(args)` — `(` immediately after an identifier is not a subscript shape,
so there's nothing to disambiguate there. `->` is free for this: today it
only appears in pointy-block signatures (`-> $x { ... }`), a different
grammatical position (statement/block-introducer, not postfix/dotty chain),
so repurposing it as a postfix "call this parameterless method" operator
doesn't collide with anything existing. This is a real, deliberate
break from upstream Raku (where `.toto` is the only spelling for a
parameterless method call) — acceptable per §0, and it's what makes the
`@a.1.toto.~str.#int` equivalence in this section actually parse without a
runtime fallback for the `.toto`/`<toto>` piece.

**Why the `~`/`#` work here is the prerequisite, specifically:** Raku already
lets a variable drive a subscript today, but only with explicit brackets —
`.{$key}` for associative, `.[$idx]` for positional — because a bare
`$`-sigiled variable carries no static information about which kind of
subscript it should mean. `~foo` and `#foo` are the first variable forms
whose *sigil alone* guarantees the value's type (Str vs. int), which is what
would let `.~foo` and `.#foo` desugar unambiguously to `{}` vs `[]` *without*
brackets and without a runtime type check at parse time. Generic `$foo` can't
play this role — `.{$foo}`/`.[$foo]` would still need explicit brackets, or
some other new marker. So this branch isn't just "add two sigils," it's
"add the two sigils whose fixed types make bracket-less variable-driven
subscripting resolvable at parse time" — worth keeping in the front matter
of the actual PR/commit description when this lands, not just here.

**What §7 does *not* get for free from this branch, and will need its own
design work** (the `.toto`-vs-method-call clash itself is resolved above by
moving parameterless calls to `->`, not left as an open problem):

- Moving parameterless method calls to `->toto` still touches every existing
  parameterless `.identifier` call site in the language — `token methodop`'s
  `<longname>` branch, `src/Raku/Grammar.nqp:2650-2652`, is where that
  grammar-level split (parameterless → error/reinterpret, with-args → stays
  `.identifier(...)`) has to happen. That's a mechanical but wide-reaching
  change (every method call without explicit `()` in existing code and specs
  needs rewriting to `->`), independent of the sigil work in this branch.
- `.1` (bare integer after `.`) doesn't collide with anything today — plain
  `.` followed by a digit isn't valid `dottyop` syntax currently (`methodop`
  has no numeric-literal branch, `src/Raku/Grammar.nqp:2650-2661`), so this
  is a comparatively low-risk grammar addition, independent of the sigil
  work, whenever §7 is tackled.
- `.~expr`/`.#expr` land in `token methodop` right next to the *existing*
  `<?[$@&]> <variable>` branch (`src/Raku/Grammar.nqp:2656`), which today
  means "call the method whose name/object is held in this `$`/`@`/`&`
  variable" (indirect method call) — a different meaning from "subscript by
  this value." Extending that lookahead to `<?[$@&~#]>` isn't enough by
  itself; `~`/`#` need a genuinely different branch in `dottyop`/`methodop`
  that means *subscript*, not *dispatch*, so §7's design has to introduce
  that branch deliberately rather than widen the existing character class.

### 8. For users: what this means for your code

*(Draft doc text. Describes the target end state once §5's phases land —
**nothing in this section is implemented yet**. The `.` subscript sugar and
`->` method calls it mentions at the end are a separate, later feature (§7),
not part of `~`/`#` themselves.)*

#### Two new sigils: `~` for strings, `#` for whole numbers

```raku
my ~name = "Alice";       # always a string
my #age  = 30;             # always a whole number (native int)
```

You don't write a type in front of them — the sigil already says what the
variable holds. That's the whole point: less to type, and the variable's
type is right there in every place you use it, not just at the declaration.

Easy to remember: `~` is already Raku's string operator (`$a ~ $b` joins
strings, `~$x` makes a string), and `#` is the usual shorthand for "number"
(as in "item #3") — so `~` for strings, `#` for whole numbers.

They behave like ordinary variables otherwise:

```raku
~name = "Bob";              # reassign, same as any variable
say "Hello, ~name!";        # interpolates in strings, like $name does
say #age + 1;                # ordinary arithmetic
```

`~name` is always a `Str`; `#name` is always a whole number (technically a
native `int` under the hood — faster, and the only real-world difference you
should notice is that it can never be undefined; see below).

#### You can't (and don't need to) give them a type

```raku
my Str ~name = "Alice";     # error: ~ already means Str
my int #age  = 30;          # error: # already means a whole number
my Int #age  = 30;          # error: same reason, even for the "boxed" Int
```

Any of these is a compile-time error, whether the type you wrote agrees with
the sigil or not — the sigil isn't a shorthand you can override, it's the
whole declaration. If you need a different type, or you need a variable that
might be `Nil`/undefined, that's what `$` is for:

```raku
my Str $name;                # can be undefined, can hold any Str subtype
my Int $age is rw;           # needs full container behavior? use $
```

`where` constraints still work, since they don't change the type, just add a
runtime check:

```raku
my ~name where *.chars > 0 = "Alice";   # fine
my ~name where *.chars > 0 = "";         # dies: the where clause fails
```

#### `#age` defaults to `0`, `~name` defaults to `""` — never undefined

Unlike a plain `$` variable, `~`/`#` variables can't be `Nil` or left
undefined:

```raku
my ~s; say ~s.raku;   # ""
my #n; say #n;          # 0
```

If your code relies on checking `.defined` to see whether a variable was
ever set, that check won't do what you expect on a `~`/`#` variable — it's
always "set," just perhaps to the empty string or zero.

#### Comments now need a space after `#`

This is the one change here that isn't about the new sigils directly, but is
required by `#` becoming one: a `#` immediately followed by a letter or
underscore, with **no space**, is now a variable reference, not a comment.

```raku
# this is still a comment (space after #)
#this is now a variable reference to #this, not a comment
#----------------------------------------  # still a comment (not a letter after #)
```

`#TODO: fix this` is affected (`T` is a letter, so it now looks like a
variable reference); `#---section---` is not (`-` can't start a variable
name, so it's still read as a comment). Add a space after `#` and it's
always a comment again, same as always. Comments starting with
`` #`(...) ``, `#|`, or `#=` (embedded comments, declarator docs) are
untouched either way.

#### If you're coming from standard Rakudo

This project doesn't keep old code working unchanged (see §0) — a few things
that used to compile will now mean something different or won't compile:

- `~word` with no space, where `word` used to be a bareword call you meant
  to stringify (e.g. `~foo` meaning "call `foo()` and stringify it"), is now
  always the `~`-sigiled variable named `word`. Write `~ foo` (with a space)
  or `~(foo)` if you meant the old thing.
- A comment written as `#word` with no space (a common style for section
  dividers or disabled code) is now a variable reference, and probably a
  compile error if you never declared a `#`-sigiled or `~`-sigiled variable
  by that name. Add a space: `# word`.

Everything else — `$a ~ $b` (concatenation), `~$x` (stringify a variable),
`~~` (smartmatch), `~=` (concat-assign), and `$~Name`-style slang variables
— works exactly as before.

#### Coming later (not yet implemented): `.` as a shorthand subscript

Once `~`/`#` exist, a planned follow-up feature will let you chain
subscripts after a `.` without brackets, using the sigil to tell strings
from numbers:

```raku
@a.1.toto.~str.#int
# will be the same as:
@a[1]<toto>{~str}[#int]
```

and calling a method with no arguments will be spelled `->name` instead of
`.name`, so `.name` can always mean "look up this key" without being
confused with a method call. None of this exists yet — it's mentioned here
so the reasoning behind the two sigils above (why they had to be fixed-type,
native values) makes sense in context.
