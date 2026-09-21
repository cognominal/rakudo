# CLAUDE.md — this repo

This file carries design notes for in-progress language changes on this branch,
for Claude's (and future contributors') use. It is not user documentation.

## Feature: new fixed-type sigils `~` (Str) and `#` (Int)

Status: **design draft, nothing implemented yet**. Branch `new-sigils`.

### 1. Request

Add two new sigils:

- `~name` — always a `Str`-typed scalar variable.
- `#name` — always an `Int`-typed scalar variable.

Because the sigil *is* the type, an explicit type in the declaration is
redundant at best and contradictory at worst, so it's a compile-time error to
write one (`my Str ~name` and `my Int ~name` are both illegal, not just the
first). A `where` constraint is still allowed, since it doesn't change the
nominal type.

Consequence: since `#name` (no space) becomes a term, plain end-of-line
comments must require a space after `#` (`# like this`) so `#name` isn't
swallowed as a comment. `#|...`, `#=...`, `` #`(...)` `` stay comment forms
regardless (see §4.2).

### 2. Grounding: how sigils work today

Two parser frontends both define the grammar and both would need the change:

- `src/Raku/Grammar.nqp` / `src/Raku/Actions.nqp` / `src/Raku/ast/*.rakumod` —
  the RakuAST frontend, where active development (RakuAST lowering, etc.) is
  happening per recent commit history.
- `src/Perl6/Grammar.nqp` / `src/Perl6/Actions.nqp` — legacy QAST-generating
  frontend, near-duplicate of the above. `token comment` and `token sigil`
  exist in both files.

Before writing code, confirm which frontend is the build default in this
checkout and whether legacy still needs parity or can be skipped (see §4.5).
The rest of this doc cites `src/Raku/*` line numbers.

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
    is where `~`/`#` branches get added (default `Str`/`Int`, base type
    `Scalar`, bind-constraint `Str`/`Int`).
  - The explicit-type/`is Type` path (line 271-292,
    `IMPL-HAS-EXPLICIT-CONTAINER-BASE-TYPE`) is exactly the mechanism to
    **reject** for `~`/`#`: if a sigil is `~` or `#`, any explicit type or
    `is Type` must be a compile error, not silently accepted.
- Actions-level plumbing (`compile-variable-access`, `sigil-to-context`,
  `contextualizer-for-sigil` in `src/Raku/Actions.nqp:3040-3231`) is already
  generic over sigil string and needs no new branches — `~`/`#` fall into the
  existing "not `@`/not `%`" = Item-context default.
- Parameters/signatures have their own sigil-aware code in
  `src/Raku/ast/signature.rakumod` (needs the same default-type wiring so
  `sub f(~$x)`... — actually `sub f(~x)` — works).

### 3. Proposed semantics

- `~name` declares/refers to a `Str`-bound scalar (`Scalar` container,
  bind-constraint `Str`, default value per current `Str` default rules).
- `#name` declares/refers to an `Int`-bound scalar (same shape, `Int`).
- Boxed classes (`Str`, `Int`), not native `str`/`int` — this matches how
  `@`/`%`/`&` map to boxed roles (`Positional`/`Associative`/`Callable`), not
  to native arrays. Native storage (today spelled `my str $x` / `my int $x`)
  is a distinct, orthogonal feature and out of scope; don't conflate "sigil
  implies Int" with "sigil implies native int".
- `my Str ~x`, `my Int #x`, `my ~x is Str`, `my Foo ~x`, etc. are all
  compile-time errors ("sigil `~` already implies type `Str`; remove the
  explicit type"). One new typed exception, e.g.
  `X::Syntax::Variable::SigilImpliesType`, covers both the redundant-match
  and the conflicting-mismatch cases — the user's spec treats them the same
  ("can't be typed"), so don't special-case "but you named the same type".
- `~name where *.chars > 0` remains legal — `where` adds a runtime
  refinement, it isn't a type in the sigil sense.
- Applies to `my`/`our`/`state`/`has`/`HAS` scopes and to signature
  parameters, symmetrically with `$`.

### 4. Risks, ordered by severity

#### 4.1 `~` collides with existing operator uses of `~` — **high, possibly blocking**

`~` today is, all at term/operator level, not just twigil:
- infix concatenation: `$a ~ $b`
- prefix stringify/coercion: `~$x`, and critically `~foo` (stringify the
  result of calling/resolving bareword `foo`)
- `~~` smartmatch, `~=` concat-assign
- the `~` twigil (§2)

`~foo` **already parses today** as prefix-`~` applied to term `foo`. Making
`~foo` also mean "the Str variable named foo" is a genuine grammar ambiguity,
not just a style clash — same input, two meanings, and it's not solvable by
whitespace convention the way `#`'s comment problem is, because `~foo` with
no space is the *existing* valid spelling of the stringify-a-call form.

Mitigation to prototype before committing to full implementation: NQP's
grammar engine resolves same-position alternatives by longest-token-match
(LTM). `token variable` (as a `<term>` alternative) matching `~foo` as one
unit is a longer match than the 1-character prefix-operator token `~`, which
in similar existing cases (see how `token twigil` cleanly disambiguates from
other punctuation, or how `-` unary-minus vs. numeric-literal-sign is
resolved elsewhere in this grammar) is exactly the kind of thing LTM is
supposed to get right automatically. But `<prefix>` and `<term>` are
different proto-hierarchies combined by the generic `EXPR`
operator-precedence method (from NQP's `Cursor`), not one flat alternation —
whether LTM applies *across* that boundary the way it does within a single
`proto token` is not something to assume; it must be spiked. This is Phase 0
below and gates everything else about `~`.

Fallback if the spike fails: restrict the `~` sigil to declaration position
only (`my ~x`, `has ~x`, signature parameters), and require existing `$x`-style
access at use sites is a non-starter given the request's intent, so a cleaner
fallback is picking a different, non-colliding character while keeping `#`
as specified — worth a real conversation with the user if Phase 0 shows the
LTM approach doesn't work cleanly.

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

#### 4.3 Backward compatibility — high

Both changes are backward-incompatible for existing source:
- Any existing code with a bareword-stringify use of `~word` (rare but not
  impossible) changes meaning if `~` becomes a sigil unconditionally.
- Any existing comment written as `#word` with no space (extremely common —
  section dividers, commented-out code, TODO markers) either becomes a
  syntax/type error or silently changes meaning if `#` becomes a sigil
  unconditionally.

This repo already has a proven mechanism for exactly this situation:
`$*LANGUAGE-REVISION` / `self.language-revision`, gating other breaking
changes (e.g. `src/Raku/Grammar.nqp:243`, `:1771`, `:2753`). **Recommend
gating both new sigils and the comment-spacing change behind a language
revision bump** (or an `experimental` pragma while iterating), not a global
change to `v6`/current-revision parsing. Don't skip this step even for a
prototype — testing "does `~` sigil parsing work" against the live grammar
without a gate will make every other `.rakutest`/roast file that has an
unspaced `#comment` a false failure and hide real regressions.

#### 4.4 Two frontends — medium

`src/Perl6/Grammar.nqp` is a near-duplicate of `src/Raku/Grammar.nqp`
(both define `token comment`, `token sigil`, independently). Decide up front:
implement in both (double the grammar work, keeps legacy compiling), or
RakuAST (`src/Raku/*`) only, with legacy explicitly left unsupported for this
feature (cheaper, plausible if legacy is genuinely being phased out — verify
that assumption for this checkout rather than assuming it from general
Rakudo history).

### 5. Implementation plan

Ordered; each phase assumes the previous one landed and its tests pass. Phase
0 is a spike, not shippable work — do it before writing any of the "real"
phases so the `~` feasibility question is answered with evidence.

**Phase 0 — spike: `~` term/prefix disambiguation**
Throwaway branch. Add `~` to `token sigil`, do nothing else, and write a
handful of one-off parse tests: `~foo` as a fresh declaration, `~foo` after
`~foo` was declared, `~$x` (existing stringify, must still work), `$a ~ $b`
(existing infix, must still work), `~~ 42` (smartmatch), `~=` (concat-assign).
Establish whether LTM resolves these correctly with no special-casing, or
whether hand-written disambiguation (e.g. a negative lookahead in the prefix
`~` token for "followed directly by identifier chars with no preceding
space") is needed and how much it breaks. **Report back before Phase 2.**

**Phase 1 — `#` sigil + comment-spacing rule (independent of `~`, lower risk)**
- Add `#` to `token sigil` (`Grammar.nqp:5455`), gated by language revision.
- Tighten `comment:sym<#>` per §4.2, gated the same way.
- Wire `#` through `IMPL-CALCULATE-TYPES` (new branch, default `Int`,
  base type `Scalar`, bind-constraint `Int`) and `IMPL-SIGIL-LOOKUP` if it
  needs an entry.
- Reject explicit types/`is Type` on `#`-sigiled declarations
  (new `X::Syntax::Variable::SigilImpliesType`).
- Add `i1`/`i0` interpolation roles, compose into `qq` (`Grammar.nqp:6388`).
- Parameters: wire `signature.rakumod` the same way.
- Tests: parser tests for declaration/use/error cases, interpolation, params.

**Phase 2 — `~` sigil (only if Phase 0 spike is clean)**
Same steps as Phase 1, mirrored for `~`/`Str`, plus explicit regression tests
for every existing `~`-operator/twigil use listed in §4.1.

**Phase 3 — attributes & introspection**
`has ~x` / `has #x` (should mostly fall out of Phase 1/2 wiring since `has`
shares the `scoped`/`variable-declaration.rakumod` path — verify, don't
assume). Check `.sigil`, `.VAR`, `.perl`/`.raku` round-tripping, and any
place that enumerates the sigil character set literally (grep for
`'$@%&'`-style string constants beyond the ones found in §2 — there may be
more, e.g. in `Metamodel`, MOP introspection, or `core.c` setting sources).

**Phase 4 — legacy frontend parity decision**
Resolve §4.4 explicitly (implement in `src/Perl6/*` too, or document as
RakuAST-only) rather than discovering it late.

**Phase 5 — docs, NEWS entry, roast-style tests, rollout**
Update language docs, add a NEWS/changelog entry describing the language
revision gate, and add tests in the style this repo's test suite already
uses (`t/`, `roast` submodule if applicable) covering both success and error
paths.

### 6. Explicitly out of scope for MVP

- Native `str`/`int` storage for `~`/`#` (a real but separate feature).
- Sigils for other types (e.g. a hypothetical `Num` or `Bool` sigil) — not
  requested, don't generalize preemptively.
- Changing the `~` twigil's behavior.
