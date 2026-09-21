# CLAUDE.md — this repo

This file carries design notes for in-progress language changes on this branch,
for Claude's (and future contributors') use. It is not user documentation.

## Feature: new fixed-type sigils `~` (Str) and `#` (int)

Status: **design draft, nothing implemented yet**. Branch `new-sigils`.

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

- `~name` — always a `Str`-typed (boxed) scalar variable.
- `#name` — always a native-`int`-typed scalar variable (not boxed `Int`).

Note the deliberate asymmetry: `~` implies the boxed class `Str`, `#` implies
the *native* type `int`, not the boxed class `Int`. This mirrors the user's
own wording ("String" vs. "int") and has real implementation consequences —
see §3 and §5, Phase 1.

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
    `container-base-type`/`container-type`/`bind-constraint`/`default`. This
    is where the `~` branch gets added (default `Str`, base type `Scalar`,
    bind-constraint `Str`) — same shape as `$`, just with a forced default.
  - `#` is different: it isn't "another boxed-Scalar branch," it's "`$`
    with `$of` forced to the native `int` type object." The relevant code
    already exists for this, in `IMPL-CONTAINER` (line 336-361):
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
    raw native local, exactly like today's explicit `my int $x`. Making
    `#name` mean native int is a matter of feeding `int` in as `$of` for
    `#`-sigiled declarations, not writing new container logic — but it also
    means `#name` **inherits existing native-scalar limitations**, notably
    the `state` NYI death above (`state #x` won't work until that's fixed,
    independent of this feature), no `Mu`/undefined state (natives default
    to `0`, can't hold `Nil`), and attribute (`has #x`) vs. non-attribute
    behavior already forking at `return nqp::null unless $attribute` above.
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

- `~name` declares/refers to a `Str`-bound scalar (`Scalar` container,
  bind-constraint `Str`, default value per current `Str` default rules) —
  the same boxed shape `@`/`%`/`&` already use for their implied roles.
- `#name` declares/refers to a native-`int` scalar — no `Scalar` container
  object (see §2), value defaults to `0`, cannot be `Nil`/undefined, and
  currently cannot be `state`-scoped (inherits the existing native-scalar
  `state` NYI). This is the same semantics as today's `my int $x`, just
  spelled with the sigil instead of an explicit type.
- `my Str ~x`, `my int #x`, `my Int #x`, `my ~x is Str`, `my Foo ~x`, etc.
  are all compile-time errors ("sigil `~`/`#` already implies a type; remove
  the explicit type"). One new typed exception, e.g.
  `X::Syntax::Variable::SigilImpliesType`, covers both the redundant-match
  case (`my int #x`) and the conflicting-mismatch case (`my Int #x`,
  `my Str #x`) — the user's spec treats them the same ("can't be typed"), so
  don't special-case "but you named the same type".
- `~name where *.chars > 0` remains legal — `where` adds a runtime
  refinement, it isn't a type in the sigil sense.
- Applies to `my`/`our`/`state`/`has`/`HAS` scopes and to signature
  parameters, symmetrically with `$`.

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

**Phase 1 — `#` sigil + comment-spacing rule (independent of `~`, lower risk)**
- Add `#` to `token sigil` (`Grammar.nqp:5455`). No gating (§0).
- Tighten `comment:sym<#>` per §4.2. No gating (§0).
- Wire `#` to force `$of` to the native `int` type object, riding the
  existing primspec path in `IMPL-CONTAINER` (§2) rather than adding a new
  boxed-type branch; confirm `IMPL-CALCULATE-TYPES`'s default `$` branch
  (line 265-269) needs no change beyond that, and decide how `state #x`
  should fail (reuse the existing NYI message, or a clearer one naming the
  sigil).
- Reject explicit types/`is Type` (`int`, `Int`, or anything else) on
  `#`-sigiled declarations (new `X::Syntax::Variable::SigilImpliesType`).
- Add `i1`/`i0` interpolation roles, compose into `qq` (`Grammar.nqp:6388`).
- Parameters: wire `signature.rakumod` the same way.
- Get `t/02-rakudo/new-sigil-int.t` green.

**Phase 2 — `~` sigil**
Same steps as Phase 1, mirrored for `~`/`Str`, applying the §4.1 resolution
(bare `~identifier` always the sigil) with no compatibility fallback. Get
`t/02-rakudo/new-sigil-str.t` green.

**Phase 3 — attributes & introspection**
`has ~x` / `has #x` (should mostly fall out of Phase 1/2 wiring since `has`
shares the `scoped`/`variable-declaration.rakumod` path — verify, don't
assume). Check `.sigil`, `.VAR`, `.perl`/`.raku` round-tripping, and any
place that enumerates the sigil character set literally (grep for
`'$@%&'`-style string constants beyond the ones found in §2 — there may be
more, e.g. in `Metamodel`, MOP introspection, or `core.c` setting sources).

**Phase 4 — test-suite triage (§0)**
Run this repo's existing `t/`/spec-style suite, symlink in whatever upstream
tests still pass unmodified, and omit (don't symlink, or remove) whatever now
fails because it asserted one of the dropped old meanings (§4.3). Then docs
and a NEWS/changelog entry noting the breaking changes plainly (since they're
intentional, not gated).

### 6. Explicitly out of scope for MVP

- Native `str` storage for `~` (it's specified as boxed `Str`; only `#` is
  native, per §3's deliberate asymmetry).
- Boxed `Int` as an alternative reading of `#` — the spec is native `int`;
  don't hedge by making it configurable.
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
