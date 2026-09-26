# INTERACTIVE-NAVIGATION.md — this repo

**Nushell-style TAB completion and YAML preview for the `.` subscript operator.**
A design spec for the next layer above Phases 1-3 (SUBSCRIPT-OPERATOR.md):
given `@a.`, `%h.`, or any `.`-subscriptable expression in an interactive
REPL/editor context, what should TAB and SHIFT-TAB show?

Status: **Not implemented.** This is a pure design document — nothing here
has code written for it yet. Read SUBSCRIPT-OPERATOR.md (especially §1-3)
for the grammar-level `.name`/`.1`/`.~expr`/`.#expr` sugar this builds on.

## 0. Relationship to this branch's other work

This branch has already implemented and tested:

| Feature                        | File                                    | Tests |
|--------------------------------|-----------------------------------------|-------|
| `~` sigil (native `str`)      | CLAUDE.md §1‑3                          | 18/18 |
| `#` sigil (native `int`)      | CLAUDE.md §1‑3                          | 18/18 |
| `.1` (literal positional index)| SUBSCRIPT-OPERATOR.md §5 Phase 1       | 7/7   |
| `.~expr`/`.#expr` (sigil subscript)| SUBSCRIPT-OPERATOR.md §5 Phase 2    | 8/8   |
| `.name` → `<name>` / `->name` (`.rak` only)| SUBSCRIPT-OPERATOR.md §5 Phase 3| 11/11 |

All of those are **grammar-level** changes — they define how `.` after a
term parses and desugars to subscript AST nodes. This document describes
what happens *after* parsing: when an interactive environment (REPL,
editor plugin, language server) is positioned at a `.` with nothing yet
typed after it, and the user asks for completions or a structural preview.

The `.` operator described in all five phases above is the **parse-time
surface** this feature makes navigable at **edit time**.

## 1. Request

Add two interactive navigation primitives for the `.` subscript surface:

1. **TAB** — after a term followed by `.` (the user has typed `@a.` or
   `%h.` or `$obj.` and pressed TAB before typing any subscript selector),
   show a menu of available keys, indices, or both, depending on the
   subject's representation. The same behavior at `.1` (partially typed
   digit) or `.name` (partially typed identifier) narrows the list by
   prefix matching.

2. **SHIFT-TAB** — after the same `.`-prefixed position, instead of a
   completion menu, dump the structure at that point as YAML (a compact,
   indented preview of what accessing this node would let you reach). If
   the structure is large, truncate at a configurable depth/width.

Both are designed around **REPR** (Raku's representation system), where a
single object can expose both positional and associative access:

```raku
my $m = "hello world" ~~ /(.)\w+ (.)/;  # Match object — REPR is both
# $m[0]   gives 'h'
# $m<0>   gives 'h'  (same, via Str capture-name)
# $m.keys gives ('0',)
```

A nushell user would expect `$m. TAB` to show both numeric indices
(0 through `$m.elems - 1`) and string keys (`$m.keys`), because REPR
exposes both interfaces, and the `.` subscript sugar can reach either one
(depending on what follows `.`). This spec makes that explicit.

### Mnemonic

| Key       | Meaning                                        |
|-----------|------------------------------------------------|
| **TAB**   | "What can I put here?" — list subscripts       |
| **SHIFT-TAB** | "What's under there?" — preview the value  |

Mirrors the nushell convention where TAB completes commands/paths and
SHIFT-TAB previews data structure content inline.

## 2. Grounding: what already exists

### 2.1 The `.` subscript sugar (this branch, DONE)

After a term, `.` followed by one of four shapes desugars as follows
(SUBSCRIPT-OPERATOR.md §3):

| after `.`                | desugars to | target interface |
|---------------------------|-------------|------------------|
| bare integer (`1`)        | `[1]`       | positional       |
| bare identifier (`toto`)  | `<toto>`    | associative      |
| `~expr` (Str‑sigiled)     | `{expr}`  | associative      |
| `#expr` (int‑sigiled)     | `[#expr]`   | positional       |

The interactive mode doesn't need to know which shape the user will pick —
it just needs to know that the *subject* (the term before `.`) exposes one
or both subscript interfaces, and list the available keys/indices for each.

### 2.2 Raku's `.WHAT`, `.^roles`, `.REPR` introspection

Available at runtime — and in an interactive/REPL context, available in
principle via a `try`-wrapped introspect call on the subject:

```raku
.say for $subject.^attributes;     # list all attributes
$subject.^can('elems') ?? "positional" !! "not positional";
$subject.^can('keys')  ?? "associative" !! "not associative";
```

But for a completion engine, the relevant interface is:

- **Positional (`@`‑ish):** `$subject.elems` gives the count; `^$subject`
  gives the range of valid indices `0..^elems`.
- **Associative (`%`‑ish):** `$subject.keys` lists available keys.

**REPR-aware check:** `$subject.HOW.archetypes.positional` and
`$subject.HOW.archetypes.associative` return `True`/`False` and determine
whether the object can be subscripted with `[...]` or `{...}` respectively
(or both). This is distinct from whether it *happens to have those methods*
— a `Hash` has both archetypes false at the HOW level (it's a concrete
`Hash`, not a parametric role) but its `.keys` method works; the correct
introspection path is `$subject.^can('AT-POS')` / `$subject.^can('AT-KEY')`
for the raw subscript interface, or `.elems`/`.keys` for the human-facing
one. This spec uses the latter (`.elems`/`.keys`) for the completion
display, with the note that `AT-POS`/`AT-KEY` is the definitive check.

**Empty/zero-length subjects** (`my @a;`, `my %h;`): TAB should show
`<empty>` or a dimmed "(no entries)" message, not an empty list or a crash.

### 2.3 YAML output

No YAML library is assumed in the core. A viable first implementation is a
hand-written recursive subroutine that mirrors `$obj.raku`-style output but
formatted as indented YAML blocks, roughly:

```
- 10
- 20
- 30
```

for a positional array, and:

```
name: Alice
age: 30
```

for an associative structure. For mixed REPR (both positional and
associative), the YAML output should first show the associative keys as
mapping entries, with positional indices collected under an `_indexed:` key
or at a separate YAML document (decided below in §5).

This is deliberately NOT `%h.perl` or `%h.raku` — those produce Raku code,
not structural data. It's also deliberately NOT `.YAML()` from a CPAN
module, to avoid an external dependency in the REPL/bootstrap build.
Instead it produces the simplest YAML subset that a human can scan:

- Scalars: strings, numbers, booleans, `null` (for `Any`/`Nil`).
- Sequences: `- item` style.
- Mappings: `key: value` style.
- Nested structures: indented, 2 spaces per level.
- Depth limit (default 3) with `...` truncation marker.
- Width limit (default 2000 chars per line / 20 items per level) with
  `... and N more` truncation message.

## 3. Proposed behavior

### 3.1 TAB — list available subscripts

After `@a.` (positional subject):

```
@a.█  →  TAB
─────────────────────────────────────
Indices [0..9] (10 entries):
  0   1   2   3   4   5   6   7   8   9
─────────────────────────────────────
```

If the user has typed a partial digit — `@a.3█` — narrow to `3`‑prefixing
indices:

```
@a.3█  →  TAB
───────────────────────────
Indices matching "3":
  3   30   31   32   …   39
───────────────────────────
```

After `%h.` (associative subject):

```
%h.█  →  TAB
─────────────────────────────────
Keys: name   age   occupation
─────────────────────────────────
```

If the user typed a partial identifier — `%h.n█` — narrow:

```
%h.n█  →  TAB
───────────────────────────
Keys matching "n":
  name
───────────────────────────
```

After `$obj.` where REPR is both positional and associative (e.g. a `Match`
object, an `Any`‑mapped `MixHash`, a custom REPR):

```
$m.█  →  TAB
────────────────────────────────────────────────────
Indices [0..4] (5 entries):   0   1   2   3   4
Keys:   0   1   from   to   orig   str
────────────────────────────────────────────────────
```

Both lists shown, separated by section. A note about the `#`/`~` sigil
choice is *not* shown by default — the completion engine doesn't force the
user to pick a sigil; it shows keys/indices, and the user types the
appropriate selector. If the user tabs on `$m.#█`, only indices are shown.
If the user tabs on `$m.~█` or `$m.█` (identifier regex), only keys are
shown (because `~` and bare identifier both hit the associative path).

**Interaction with `.1` and `.#`:** After `@a.#█`, the TAB menu should show
indices (same as plain `@a.█`). After `%h.~█`, the TAB menu should show
keys (same as plain `%h.█`). This is because `.#` and `.~` are specifying
which *subscript form* the user intends (positional vs associative), not
restricting the *value domain* — the list of available integer indices is
the same whether the user will type `.#3` or `.3`, and the list of keys is
the same whether typed `.~name` or `.name`.

**Interaction with `.name` sugar (`.rak` mode):** In `.rak` mode
(SUBSCRIPT-OPERATOR.md §5 Phase 3), a bare identifier after `.` means
`<name>`, i.e. associative. So the TAB menu after `$x.foo█` in `.rak` mode
should show *only* the associative keys (matching prefix `foo`), not
indices. In `.raku` mode, `.foo█` is the start of a method call — TAB
there should show method-name completions (the existing REPL behavior),
not subscript keys. The file extension gate (`$*NEW-DOTTY-SEMANTICS`) is
the natural discriminator: the same dynamic variable that decides how `.`
parses also decides how TAB completion behaves.

**Implementation note — safety:** An arbitrary subject may have side-
effecting `.elems` or `.keys` methods (e.g. an `IO::Cat` that opens files, a
lazy `Seq` that must be consumed to report an element count). The
completion engine MUST:
- **Time-box** the introspection (wall‑clock timeout, e.g. 500ms total).
- **Catch exceptions** from `.elems` / `.keys` and fall back to
  `<side-effecting — can't enumerate>` or the count from `.WHICH` alone.
- **Not consume** lazy structures — for a `Seq`, check `$seq.is-lazy`
  first; if True, show `<lazy — count unknown>`.
- **Cache** the result for the same textual subject expression within a
  single completion session (the user might TAB twice with no intervening
  keystroke).

### 3.2 SHIFT-TAB — preview structure as YAML

After `@a.█` SHIFT-TAB:

```yaml
- "first"
- "second"
- "third"
```

After `%h.█` SHIFT-TAB:

```yaml
name: Alice
age: 30
occupation: engineer
```

After `$match.█` SHIFT-TAB (mixed REPR):

```yaml
# Positional indices [0..4]:
- "h"
- "ello"
- "w"
- "orld"
# Associative keys:
from: 0
orig: "hello world"
str: "h"
to: 2
```

The YAML preview should:
1. Show the **top-level** subscript targets (all indices or keys reachable
   by a single `.selector` from the subject).
2. Optionally (default on) drill one level deeper for a sample of items —
   e.g. for a hash of hashes, the first 3 keys' values are also expanded.
   Depth is configurable but defaults to 1 (top level only) for SHIFT-TAB
   and 2 for a double-tap SHIFT-TAB (hold and press again).
3. For large structures: truncate at 50 entries per level, with
   `... and 172 more` appended.
4. For lazy/uncountable subjects: `<lazy — preview not available>` or
   `<lazy — first N items only>` where N is configurable (default 10).
5. For side-effecting subjects: same time-box and catch-all as TAB.

### 3.3 YAML renderer specification

The YAML output must be valid YAML 1.2 for the subset it covers. The
renderer is a standalone function `yaml-preview($subject, :$max-depth = 1,
:$max-items = 50, :$max-width = 2000)` that produces a `Str`. Rules:

- Scalars: `.raku` style for strings (quoted if they contain special chars
  or YAML‑ambiguous prefixes like `true`/`false`/`null`/digits with
  leading zero), numeric `.raku` for numbers, plain `true`/`false`/`null`
  for `Bool`/`Nil`/`Any`.
- Sequences: `- value` with each value on its own line, indented 2 spaces
  per nesting level.
- Mappings: `key: value` with each pair on its own line, indented 2 spaces
  per level.
- Nested sequences/mappings within a value are indented further and
  rendered recursively — e.g. a hash with an array value:

  ```yaml
  tags:
    - perl
    - raku
    - language
  ```

- Mixed REPR (both positional and associative): rendered as a mapping with
  a synthesized key `_indices` for the positional part, plus the associative
  keys as normal mapping entries. This is a design choice (not standard
  YAML) to avoid YAML's inability to have both `-` sequence items and
  `key:` mapping items at the same level. Alternative: output two YAML
  documents separated by `---` — first document is the positional sequence,
  second document is the associative mapping — and let the reader/viewer
  handle them. **Decision:** single mapping with `_indices`, because
  SHIFT-TAB is a quick preview, not a data-exchange format. Two-document
  output would split what the user sees across two scroll regions, which is
  harder to scan at a glance. The `_indices` key is always emitted with a
  YAML‑comment annotation (`# positional`) for clarity:

  ```yaml
  _indices:   # positional
    - "h"
    - "ello"
    - "w"
    - "orld"
  from: 0
  orig: "hello world"
  str: "h"
  to: 2
  ```

## 4. Implementation sketch

### 4.1 Where this lives: the REPL, not the grammar

Unlike Phases 1-3 (SUBSCRIPT-OPERATOR.md), which modify `src/Raku/Grammar.nqp`
and `src/Raku/Actions.nqp`, this feature lives **outside the compiler core**,
in whichever frontend provides interactive editing:

- If the Raku REPL (`src/core.c/REPL.rakumod`, `src/Perl6/REPL.nqp`) is
  enhanced: the TAB/SHIFT-TAB handler intercepts the cursor position,
  walks backward to find the `.` and its subject expression, eval‑introspects
  the subject, and produces the completion/preview display.
- If a Language Server Protocol (LSP) implementation is the target:
  `textDocument/completion` and `textDocument/hover` (or a custom
  `textDocument/preview`) handlers implement the same logic. This spec
  assumes the REPL is the first target (lowest friction, fastest iteration)
  and leaves LSP to a follow-up.

### 4.2 REPL‑level pseudocode

```
on tab(editor-buffer, cursor-pos):
    prefix = buffer[0..cursor-pos]   # everything left of cursor
    if prefix matches / (.+) \. $ /:
        subject-expr = $1             # the term before the last dot
        selector-prefix = ""          # nothing typed after the dot yet
    elsif prefix matches / (.+) \. (\w*)$ /:
        subject-expr = $1
        selector-prefix = $2          # partial identifier/digit
    else:
        fallback to normal TAB completion (current REPL behavior)

    subject = try-eval(subject-expr)
    unless subject.defined:
        show "<unknown subject>"
        return

    # Determine available interfaces
    my @indices   = subject.^can('AT-POS') ?? 0 ..^ subject.elems !! ()
    my @keys      = subject.^can('AT-KEY')  ?? subject.keys     !! ()

    # Filter by selector-prefix (if any)
    @indices = @indices.grep: *.Str.starts-with(selector-prefix)
    @keys    = @keys.grep:    *.starts-with(selector-prefix)

    # Display
    if @indices:
        display-section("Indices [{@indices.min}..{@indices.max}] ({@indices.elems} entries)",
                        @indices.join("    "))
    if @keys:
        display-section("Keys", @keys.join("   "))
    if !@indices && !@keys:
        display-section("(no subscriptable entries)", "")
```

```
on shift-tab(editor-buffer, cursor-pos):
    prefix = (same detection logic as tab)
    subject = try-eval(subject-expr)

    yaml = yaml-preview(subject, max-depth => 1, max-items => 50)
    show-preview-window(yaml)
```

The `yaml-preview` function:

```
sub yaml-preview($subject, :$max-depth = 1, :$max-items = 50, :$max-width = 2000, :$depth = 0) returns Str:
    return "<max-depth>" if $depth >= $max-depth
    return "<max-width truncated>" if accumulated-width >= $max-width

    my $indent = "  " x $depth

    if $subject.^can('AT-KEY') && $subject.^can('AT-POS'):
        # Mixed REPR — use _indices convention
        return render-mixed-repr($subject, :$max-depth, :$max-items, :$max-width, :$depth)

    if $subject.^can('AT-KEY'):
        # Associative — mapping
        my @keys = $subject.keys
        @keys = @keys[0..^min(@keys.elems, $max-items)]
        my $truncated = @keys.elems < $subject.keys.elems
        my @lines
        for @keys -> $k:
            @lines.push: "$indent$k: {yaml-preview($subject{$k}, :$max-depth, :$max-items, :$max-width, depth => $depth + 1)}"
        if $truncated:
            @lines.push: "$indent... and {$subject.keys.elems - $max-items} more"
        return @lines.join("\n")

    if $subject.^can('AT-POS'):
        # Positional — sequence
        my $elems = $subject.elems
        my $count = min($elems, $max-items)
        my @lines
        for ^$count -> $i:
            @lines.push: "$indent- {yaml-preview($subject[$i], :$max-depth, :$max-items, :$max-width, depth => $depth + 1)}"
        if $count < $elems:
            @lines.push: "$indent- ... and {$elems - $count} more"
        return @lines.join("\n")

    # Scalar fallback
    return scalar-yaml($subject)
```

### 4.3 Safety: lazy, side-effecting, and infinite subjects

Every `.elems` and `.keys` call in the TAB/SHIFT-TAB path must be wrapped:

```raku
sub safe-elems($subject) {
    return "<lazy>" if $subject.^can('is-lazy') && $subject.is-lazy;
    try {
        my $timeout = Promise.in(0.5);
        my $result  = Promise.start({ $subject.elems });
        await any($result, $timeout);
        $result.status ~~ Kept ?? $result.result !! "<timeout>";
    }
}
```

Same pattern for `.keys`. The REPL itself runs in a single-threaded event
loop, so blocking for 500ms is acceptable (the user already waited for a
TAB press); an LSP implementation would use a non‑blocking request.

### 4.4 Caching

Within one interaction (TAB, modify, TAB, modify, SHIFT-TAB), the
introspection result for the *same textual subject expression* is cached.
Key = `$subject-expr` as a string; value = `{ indices => ..., keys => ...,
yaml => ... }`. The cache is cleared when the cursor leaves the `.`
position (i.e., the user moves the cursor to a different line, or types
a space, or deletes back past the subject).

## 5. Open questions and design decisions

### 5.1 Where should `_indices` appear in mixed‑REPR YAML?

Two alternatives considered:

| Option       | Rendering                                    | Trade‑off                              |
|--------------|----------------------------------------------|-----------------------------------------|
| **Single mapping with `_indices` key** | `_indices: [a, b, c]` plus `{key: val}` entries | One document, easy to scan. Synthetic key name. |
| **Two YAML documents** (`---` separator) | `---\n- a\n- b\n---\nkey: val` | No synthetic keys. Harder to read on one screen. Viewer may not handle multi‑doc YAML. |

**Decision: single mapping with `_indices`.** Rationale: SHIFT-TAB is a
preview, not an interchange format. A single scrolling region is more
important than purity of the YAML spec. The `_indices` key is decorated
with a YAML comment (`# positional`) to disambiguate.

### 5.2 Should SHIFT-TAB also work on a *complete* subscript expression?

After the user types `@a.3` and SHIFT-TABs before hitting Enter, should the
preview show the value at `@a[3]` (a single scalar) or the top-level
structure of `@a`? **Decision: the latter.** SHIFT-TAB always previews the
*subject* of the current `.`, not the subscript result. The `.` is the
"navigation anchor" — TAB/SHIFT-TAB answer "where am I / what can I step
into," not "what does the complete line evaluate to." The latter is what
`say` / the REPL's auto‑print does on execution. So `@a.3█` SHIFT-TAB still
previews `@a`'s indices and keys, not the single value at index 3.

If the user wants to preview a specific subscript result, they should
complete the expression and press Enter (execution), or type `.` again to
drill into that result: `@a.3.█` TAB would then show what's inside
`@a.3`'s value.

### 5.3 Should TAB also offer `->` completions in `.rak` mode?

In `.rak` mode, `.name` is a subscript and `->name` is a method call.
After `%h.█` TAB in `.rak` mode, should the menu *also* show available
`->method`s? **Decision: no.** The TAB is anchored on `.`, so it answers
"what subscripts can I type after this `.`?" `->name` completions would
be a separate interaction (triggered by typing `->` and then TAB). Splitting
the menu prevents confusion between subscript keys and method names at the
same position.

### 5.4 Does TAB need to show `~`/`#` sigil hints?

After `@a.█` TAB, should the menu say "use `#3` (not `3`) for native‑int
subscript"? **Decision: no, not in the initial version.** The TAB output
shows plain integers. The user already has a choice between `.3` (bare
digit → sugar for `[3]`) and `.#n` (sigil → `[#n]`). The completion menu
doesn't need to explain this; the user can type either form. A future
version may add a tooltip or a `#` suffix hint, but it's explicitly out of
scope for MVP.

### 5.5 LSP integration surface

For a Language Server Protocol implementation, the mapping is:

| Editor action | LSP request                          |
|---------------|--------------------------------------|
| TAB           | `textDocument/completion`            |
| SHIFT-TAB     | `textDocument/hover` (with YAML content) or a custom command `textDocument/preview` |

The completion response would include a custom `CompletionItemKind` hint
so the editor can render indices and keys differently. The hover response
would return a `MarkupContent` with `kind: 'markdown'` and the YAML inside
a fenced code block (` ```yaml `).

## 6. Explicitly out of scope for MVP

- Any grammar‑level change to support this — it's entirely a REPL/LSP‑level
  feature, not a new parse rule.
- `.keys` / `.elems` results for subjects that require `use`‑loading a
  module the REPL hasn't seen yet (the subject must be evaluable in the
  current scope; unknown symbols get `<unknown subject>`).
- Fuzzy or substring matching in TAB (only prefix matching, mirroring how
  most shells complete).
- Preview of `->` method calls (only `.`‑subscript preview).
- Folding the YAML preview into a column/buffer view (terminal REPL
  displays it inline; LSP shows it in a hover/completion-detail popup).
- Editing the YAML and writing back to the structure (read‑only preview).
- `$*NEW-DOTTY-SEMANTICS` awareness for environments that don't have it
  (if the compiler doesn't export this variable, fall back to traditional
  REPL completion — no `.`‑subscript‑specific behavior).

## 7. Acceptance criteria (test plan)

A test file `t/02-rakudo/interactive-navigation.t` (REPL‑simulation via
`Proc::Async` driving a REPL subprocess) should assert:

**TAB — positional:**
- `my @a = <a b c>; [streaming input] @a.` TAB → menu contains `0`, `1`, `2`
- `my @a = <a b c>; @a.1` TAB → matches `1` (narrowed), does NOT show `0` or `2`
- `my @a;` (empty array) TAB → shows `<empty>` indicator

**TAB — associative:**
- `my %h = a => 1, b => 2; %h.` TAB → menu contains `a`, `b`
- `my %h = a => 1, b => 2; %h.a` TAB → matches `a`, does NOT show `b`
- `my %h;` (empty hash) TAB → shows `<empty>` indicator

**TAB — mixed REPR (e.g. Match):**
- `my $m = "abc" ~~ /(.)(.)/; $m.` TAB → menu includes indices `0` `1` AND
  associative keys (at minimum `0`, `1`, `from`, `to`, `orig`, `str`)

**TAB — safety:**
- `my $lazy = (1..Inf).grep(* %% 2); $lazy.` TAB → shows `<lazy — count unknown>`
  or similar, does not hang
- A subject whose `.keys` croaks → shows `<error>` indicator, does not abort

**SHIFT-TAB — YAML:**
- `my @a = <x y z>; [cursor at @a.]` SHIFT‑TAB → output matches
  ```
  - "x"
  - "y"
  - "z"
  ```
- `my %h = name => "Alice", age => 30; %h.` SHIFT‑TAB → output matches
  ```
  name: "Alice"
  age: 30
  ```
- Mixed REPR preview uses `_indices:` convention
- Depth truncation (max‑depth=1 on a hash of hashes shows `<max-depth>` for
  nested values, not full expansion)
- Large array (100 elements, max‑items=10) shows `... and 90 more`

**Extension‑aware behavior:**
- In `.raku` mode (at a REPL that tracks the file type): `.foo` TAB → method
  completions, not subscript keys
- In `.rak` mode: `.foo` TAB → subscript keys (as above)

(Note: testing the file‑extension gate from the REPL is non‑trivial — `EVAL`
has no notion of a source‑file extension. The test may need to either
launch a subprocess with a `.rak`/`.raku` temp file that exercises a REPL‑
simulation `$*IN` feed, or accept that extension‑aware tests are done at
the `dot-subscript-name.t` level only and mark this test as `todo`.)

## 8. Prior art: nushell's navigation model

Nushell's `ls` / `open` / `$env` / `$config` navigation works as follows

| Action     | Result                                                    |
|------------|-----------------------------------------------------------|
| `ls ` TAB  | Shows files/dirs in current dir (completion list)         |
| `open .` TAB  | Lists fields within a structured file                    |
| `ls | where` TAB | Shows column names                                 |
| SHIFT-TAB  | Preview pane shows file contents or data sample           |

This spec mirrors that: `.` is analogous to `ls`'s path separator (it opens
a "directory" of subscriptable entries), TAB lists the entries, and
SHIFT-TAB previews the content at that point without committing to a
selection.

The key difference: nushell's TAB is purely filesystem‑ or column‑oriented;
Raku's `.` is polymorphic (positional, associative, mixed REPR), so the
completion engine must detect the interface at runtime rather than assuming
a fixed schema. The `_indices` convention for mixed REPR in SHIFT-TAB is
analogous to nushell's handling of records that are both `list` and
`record` (e.g. `open` on a JSON file that is an array of objects — nushell
shows both the array index and the object keys).

## 9. Future directions (post‑MVP)

- **Visual preview**: Instead of text YAML, a tree‑widget in the terminal
  (e.g., `blessed`‑style or `Ratatouille`‑rendered) that lets the user
  expand/collapse nodes with arrow keys, then insert the selected path as
  a `.`‑subscript expression. This is a full‑terminal‑UI feature, far
  beyond the MVP SHIFT-TAB YAML dump.

- **Write‑back**: After preview, allow the user to edit a value in the YAML
  and commit it back to the structure (e.g., change a hash value or an
  array element). This would require tracking the navigation path as a
  sequence of subscript operations and applying the edited value through
  them. Not part of MVP.

## 10. The `rak` binary: argumentless invocation enters `.rak`-mode REPL

### 10.1 The `rak` entry point

This branch's new dotty semantics (SUBSCRIPT-OPERATOR.md §5 Phase 3) are gated
behind a **`.rak` file extension**: a source file named `foo.rak` gets `$*NEW-
DOTTY-SEMANTICS=1`, which turns `.name` (parameterless, no `(`) into `<name>`
subscript sugar instead of a method call, and `->name` into a real
parameterless method call. All other extensions (`.raku`, `.rakumod`, `.pm6`,
`.nqp`) keep traditional semantics permanently — zero rewrites of the standard
library (SUBSCRIPT-OPERATOR.md §4.1).

This spec adds a third path to set `$*NEW-DOTTY-SEMANTICS`: **running `rak`
with no arguments** (no filename, no `-e` code) starts an interactive REPL
that defaults to `.rak`-mode semantics. The progression:

| invocation | mode | behavior of `.name` | behavior of `->name` |
|---|---|---|---|
| `raku foo.raku` | `.raku` | method call | obsolete-syntax error |
| `raku foo.rak` | `.rak` | `<name>` subscript | real method call |
| `rak` (no args) | `.rak` interactive | `<name>` subscript | real method call |
| `raku` (no args) | `.raku` interactive | method call | obsolete-syntax error |

**Why `rak` and not `raku` with a flag?** Two reasons:

1. **File-extension logic already exists** in `comp-unit-prologue` (Actions.nqp,
   SUBSCRIPT-OPERATOR.md §5 Phase 3). For a physical `.rak` file, the
   extension tells the compiler which mode to use. But an *interactive REPL*
   has no file — there's no extension to inspect. `$*NEW-DOTTY-SEMANTICS`
   defaults to `0` for `-e`/STDIN/REPL because the proc entry point is
   `raku` (the traditional binary). A separate `rak` binary signals intent
   without needing a `--dotty` flag or an environment variable.

2. **The binary name mirrors the extension.** Just as `.rak` is the opt-in
   extension for files that want the new semantics, `rak` is the opt-in
   binary for an interactive session that starts in the same mode. The
   mnemonic is immediate: "I ran `rak` → I'm in `.rak` mode."

### 10.2 How it works: `rak` as a wrapper binary

`rak` is a thin shell wrapper (or symlink) placed alongside the `raku` binary
at install time. It adds a single command-line flag that the existing
`Perl6::Compiler.command_eval` or the REPL entry path can read:

```bash
#!/bin/sh
# rak — invoke raku with argumentless .rak-mode REPL
exec raku "$@" --rak-mode
```

The `--rak-mode` flag does one thing: force `$*NEW-DOTTY-SEMANTICS=1` in any
compilation unit that has **no source file** (i.e. interactive REPL, `-e`
code, or STDIN pipe). Physical `.rak` files already set it from their
extension; physical `.raku`/`.rakumod` files continue to be unaffected by this
flag because they have their own extension to query. The flag is ignored for
any unit where `%*COMPILING<%?OPTIONS><source-name>` is already set to a re-
al file path.

**Detection in `comp-unit-prologue` (Actions.nqp):**

```perl6
# Set $*NEW-DOTTY-SEMANTICS from three sources, in priority order:
# 1. Explicit --rak-mode flag (lowest priority: only applies when there's
#    no source file)
# 2. .rak/.raku file extension (already implemented, Phase 3)
# 3. Default: 0 (traditional semantics)
#
# The order matters: a .raku file run as `rak foo.raku` should NOT get
# dotty semantics — its own extension says .raku. --rak-mode only kicks
# in when there IS no extension to ask.

my str $source-name := %*COMPILING<%?OPTIONS><source-name> // '';

if nqp::chars($source-name) >= 4
    && nqp::eqat($source-name, '.rak', nqp::chars($source-name) - 4) {
    $*NEW-DOTTY-SEMANTICS := 1;  # physical .rak file
}
elsif nqp::chars($source-name) {
    $*NEW-DOTTY-SEMANTICS := 0;  # physical file with any other extension
}
elsif %*COMPILING<%?OPTIONS><rak-mode> {
    $*NEW-DOTTY-SEMANTICS := 1;  # no source file, --rak-mode flag present
}
else {
    $*NEW-DOTTY-SEMANTICS := 0;  # no source file, no flag (default raku)
}
```

The `rak-mode` option is injected into `%options` in `command_eval` when the
`rak` binary passes `--rak-mode`:

```perl6
# In Perl6::Compiler.command_eval (already the right place — see
# SUBSCRIPT-OPERATOR.md §5 Phase 3's source-name capture):

%options<rak-mode> := 1 if nqp::existskey(%options, 'rak-mode');
```

### 10.3 What the `rak` REPL looks like

When `rak` starts with no arguments, the user sees an interactive REPL where
the dotty semantics are active from the first prompt:

```
$ rak
rak> %h = a => 1, b => 2
rak> %h.a
1
rak> %h.b
2
rak> %h.keys
(a b)
rak> ->say
(a b)
```

Compare with `raku` (traditional REPL):

```
$ raku
> %h = a => 1, b => 2
> %h.a
1                      # wait, that works too — because method call `.a`
                        # on a Hash dispatches to the .a *method* (which
                        # dies with "No such method 'a' for Hash") but
                        # .a without parens is actually resolved as
                        # method 'a' with no args... let's check:
> %h.a                  # No such method 'a' for Hash (dies)
```

Actually, the `->` transition on `%h.keys ->say` is the giveaway: in `.rak`
mode, `%h.keys` (a list) has `.` methods, but you use `->` to call them.
`%h.a` is a hash-key lookup, not a method call.

**Prompt:** the REPL prompt changes to `rak>` (instead of `>`) to remind the
user which semantic mode they're in. This is a small but critical visual cue:
without it, a user switching between `rak` and `raku` terminals would
easily forget which mode each one is in.

### 10.4 Interaction with TAB/SHIFT-TAB

When the REPL is in `.rak` mode (either from `rak` argumentless or from
evaluating code with `$*NEW-DOTTY-SEMANTICS=1`), TAB/SHIFT-TAB behavior as
described in §3 follows the `.rak` rules:

- `.foo█` TAB shows subscript keys (not method names), because `.foo` will
  parse as `<foo>`.
- `->foo█` TAB shows method completions (the methods available on the
  subject), because `->foo` will parse as a method call.
- `.foo█` SHIFT-TAB shows the YAML preview of the subject, as with any
  subscript position.

In `.raku` mode (default `raku` binary), TAB on `.foo█` shows the traditional
method-name completions, unchanged from the current REPL behavior.

This is consistent with the existing behavior from §3.1 ("Interaction with
`.name` sugar (`.rak` mode)") and §5.3 ("Should TAB also offer `->`
completions in `.rak` mode?"). The only difference is that the mode is now
set by the binary name, not just the file extension.

### 10.5 Implementation sketch: the `rak` binary

Two approaches, listed in order of preference:

**Approach A — shell wrapper (recommended for MVP):**

```bash
#!/bin/sh
# Installed alongside `raku`.
# --rak-mode is the only addition: the rest is passed through unmodified.
exec raku --rak-mode "$@"
```

This is a single file generated during `make install`. The `--rak-mode` flag
is unknown to older `raku` binaries, but this branch's `Perl6::Compiler`
recognizes it (see `command_eval` above). If run against a stock Rakudo
binary (not this branch), the flag is silently ignored via `nqp::existskey`
— it won't crash, it just won't enable dotty semantics.

**Approach B — symlink to `raku` (alternative):**

```
ln -s raku /usr/local/bin/rak
```

Then `rak` is literally `raku` by another name, and detection happens via
`$*PROGRAM-NAME` in the compiler bootstrap. This avoids a wrapper script
but requires modifying the compiler startup (in `Perl6::Compiler`'s
`command_eval` or the `MAIN` of `raku`'s entry point) to inspect
`$*PROGRAM-NAME` and set `--rak-mode` automatically. More elegant but
assumes `$*PROGRAM-NAME` is reliable across operating systems and
invocation methods. MVP adopts the shell wrapper.

**Installation integration (in `Makefile.in` or equivalent):**

```make
install:
    # existing raku binary install
    cp raku $(DESTDIR)$(PREFIX)/bin/raku
    # rak wrapper — argumentless invocations default to .rak-mode REPL
    printf '#!/bin/sh\nexec raku --rak-mode "$$@"\n' \
        > $(DESTDIR)$(PREFIX)/bin/rak
    chmod +x $(DESTDIR)$(PREFIX)/bin/rak
```

### 10.6 Interaction with interactive-navigation.t (test plan additions)

Add these assertions to the test plan from §7:

**Binary invocation:**
- `rak` with no arguments starts a REPL whose prompt is `rak>`
- `rak` REPL: `%h = a => 1; %h.a` produces `1` (hash-key lookup via `.name` sugar)
- `raku` REPL: `%h = a => 1; %h.a` produces "No such method 'a'" (method call, not subscript)
- `rak foo.raku` (explicit .raku file) compiles without error AND does NOT
  enable dotty semantics — the file's own extension takes priority over the
  binary name
- `rak -e 'my %h = a => 1; say %h.a'` — whether this uses `--rak-mode` is
  an open design point (see §10.7 below).

**Prompt display:**
- The `rak>` prompt (or a distinct marker) is shown at every REPL input line
  when running under `rak`.
- The traditional `>` prompt is shown under `raku`.

**TAB behavior in `rak` vs `raku`:**
- `rak` REPL: `@a.foo█` TAB shows subscript keys (associative narrowing)
- `raku` REPL: `@a.foo█` TAB shows method completions (no change)
- `rak` REPL: `@a->█` TAB shows method completions (because `->` triggers
  method completion, per §5.3)

### 10.7 Open question: should `-e` code inherit `--rak-mode`?

Two positions:

| Position | Behavior | Rationale |
|---|---|---|
| **A: No** (conservative) | `rak -e '...'` defaults to traditional semantics for the `-e` string. Only argumentless interactive REPL gets `.rak` mode. | `-e` is a one-liner, not an interactive session. Users who write `rak -e 'say %h.keys'` almost certainly meant method calls. Surprising them with a syntax change for a throwaway command is not worth it. |
| **B: Yes** (consistent) | `rak -e '...'` also gets `.rak` mode, same as argumentless REPL. | Consistency: "`rak` = `.rak` mode everywhere". Users who want traditional semantics for a one-liner can write `raku -e` instead. |

**Decision: Position A (conservative) for MVP.** `--rak-mode` only flips the
default for compilation units that have **no source-name at all** (the
interactive REPL session). A `-e` one-liner still gets a synthetic source-
name of `-e` (or similar), which is set and non-empty — so the extension-
based check runs, finds no `.rak`, and leaves semantics at `0`. This is the
exact behavior the current Phase 3 implementation already has for `-e` code
(confirmed: `$*NEW-DOTTY-SEMANTICS := 0` for `-e`), extended unchanged.

The `rak` binary's `--rak-mode` flag only overrides the default when there's
*no* source-name at all — which is exactly the case that maps to the
argumentless, interactive REPL.

### 10.8 Summary: three paths to `$*NEW-DOTTY-SEMANTICS=1`

| Path | Detected by | Scope |
|---|---|---|
| `.rak` file extension | `comp-unit-prologue` string check on `source-name` | Per-file compilation unit |
| `--rak-mode` flag, no source file | Same place, fallback when `source-name` is empty | Interactive REPL session |
| (future: `use v6.rak` pragma) | Same place, fallback from language-revision | Opt-in from any file |

The third path (a pragma) is not implemented and not planned for MVP. It's
listed for completeness: if a user wants dotty semantics in a `.raku` file
without renaming it, a `use v6.rak`-style pragma would be the eventual
mechanism. But the file-extension gate is deliberately the primary mechanism
for this branch (SUBSCRIPT-OPERATOR.md §4.1), and the binary name extends
that same philosophy to the REPL without inventing a new syntax.

## 11. Borrowing nushell's interactive API for `rak`

Nushell is installed at `/usr/bin/nu` and cloned to `~/git/nushell---nushell`
(commit 798c55d on this system). Its interactive layer is a Rust stack:
`reedline` (line editor), `nu-cli` (completions/menus/keybindings), and
`nu-explore` (TUI data previewer). This section evaluates whether to embed,
wrap, or ignore that stack for `rak`.

### 11.1 What nushell's source offers

| Crate | Path in source tree | Relevance |
|---|---|---|
| `reedline` | External dependency (not vendor in this clone) | Tab/BackTab handling, completion menus, multi-line editing, history, keybinding configuration |
| `nu-cli` | `crates/nu-cli/` | Completion framework with `CellPathCompletion` (its `.cell_path` completer already does what this spec describes: after `$obj.`, it eval-walks the object and lists `.keys`/`.elems` as completions) |
| `nu-explore` | `crates/nu-explore/` | TUI table/record pager with keyboard navigation, expand/collapse nested values, `--peek` to extract a cell value on exit |

**`CellPathCompletion`** (`crates/nu-cli/src/completions/cell_path_completions.rs`)
is the closest analogue to this spec's §3.1. It:
1. Walks the `FullCellPath` AST to find which `.member` the cursor is on.
2. Evaluates the tail of the path up to that point (`eval_cell_path`).
3. Calls `get_columns` on the result (which returns `.keys()` for records,
   `.column_types()` for tables).
4. Filters by prefix and returns completions as reedline `Suggestion` objects.

This is almost exactly what §4.2 sketches in pseudocode — except nushell
eas only records/tables (nu's type system), while we need generic
`AT-POS`/`AT-KEY`-detection for any Raku object.

**`nu-explore`** is a full-screen TUI pager (~500 lines across
`crates/nu-explore/src/explore/` plus supporting code). It renders any
nushell `Value` as an interactive tree with:
- Arrow keys to move between rows
- Enter to drill into a nested value
- `q`/`Esc` to close
- `--peek` to print the cursor cell value on exit (`explore -p`)

It uses `crossterm` for raw terminal control, which is the same TUI library
`Terminal::LineEditor` (already a Raku REPL backend) wraps.

### 11.2 The architectural mismatch

Despite the functional overlap, embedding nushell's Rust TUI directly into
`rak` is impractical:

1. **Language boundary.** Nushell is at least 10 Rust crates totalling
   >61MB, all compiled to a standalone ELF with no public C ABI. The Raku
   REPL runs on MoarVM (NQP/Raku). Calling into nushell's internals would
   require either a C FFI bridge (which nushell does not expose) or a
   subprocess protocol (too slow for per-keystroke TAB).

2. **reedline is already superseded.** The Raku REPL already abstracts
   over three line-editor backends: `Readline`, `Linenoise`, and
   `Terminal::LineEditor` — the last of which is a pure-Raku module that
   provides the same keybinding/completion/history primitives as reedline.
   Adding a fourth backend that talks to reedline over IPC would be
   redundant.

3. **`CellPathCompletion` is nushell-specific.** Its `eval_cell_path` works
   on nushell's own AST and type system, not on arbitrary Raku objects.
   We need to call `AT-POS`/`AT-KEY` on a Raku value — a fundamentally
   different evaluation path. The *idea* („walk the path, eval the subject,
   list its columns“) is what we borrow; the code is not reusable.

4. **`nu-explore` is a full TUI, not a library.** It captures the terminal
   and runs its own event loop. You can't call it on a single value mid-REPL
   without forking a subprocess, waiting for the user to quit, and parsing
   the `--peek` output — an awkward dance with ~60ms startup cost per
   invocation. A lighter-weight approach for SHIFT-TAB is a few lines of
   Raku code that renders the YAML preview inline (§3.2) or, in a future
   version, a minimalist tree widget using the same `Terminal::LineEditor`
   backend the REPL already uses.

### 11.3 What we borrow: design, not code

| Idea | Nushell's implementation | Our analogue |
|---|---|---|
| Cell-path completions after `.` | `CellPathCompletion` in `nu-cli` | §4.2's `subscript-completions` in `Completions` role |
| BackTab as distinct from Tab | `completion_previous` bound to `BackTab` in reedline config | §5.3, §11.6 (BackTab → YAML preview, handled in `Terminal::LineEditor` backend) |
| Explore value by key | `nu-explore` with `--peek` | §3.2's inline YAML (MVP), future tree-widget (§9) |
| Columns from runtime value | `get_columns()` (calls `.keys` on record) | `safe-keys($subject)` via `AT-KEY` detection |
| External completer protocol | `$env.config.completions.external`: shell out to any binary returning JSON | §12 (future: `rak --complete` as nushell external completer for `.rak` files) |

### 11.4 The REPL already has the right hook

The Raku REPL's `Completions` role (`src/core.c/REPL.rakumod`, lines
~167-215) has a `completions-for-line` method that all three backends call.
It currently returns identifier completions (CORE:: symbols, lexical scope
variables). The gap is that it has no awareness of `.` as a subscript anchor.

This spec adds one new method and extends `completions-for-line`:

```raku
# New helper: detect whether cursor is in a `.`-subscript position
method parse-at-cursor(Str $line, int $cursor-index --> SubscriptAnchor) { ... }

# New helper: eval the subject, list its keys/indices, filter by prefix
method subscript-completions(Str $subject-expr, Str $prefix --> Seq) { ... }

# Extended existing method:
method completions-for-line(Str $line, int $cursor-index) {
    my $parsed = self.parse-at-cursor($line, $cursor-index);
    return self.subscript-completions($parsed.subject, $parsed.prefix)
        if $parsed.is-subscript-anchor;
    # ... existing logic unchanged (CORE:: + lexical scope) ...
}
```

No Rust code, no subprocess, no new binary. The `Terminal::LineEditor`
backend already distinguishes Tab from BackTab at the raw-terminal level
(SHIFT-TAB → `KeyCode::BackTab` in reedline's terminology as well —
confirmed in `reedline_config.rs` line 18: `"backtab" => KeyCode::BackTab`),
so adding a SHIFT-TAB → YAML-preview path there is ~50 lines of Raku.

The `Linenoise` backend does not expose BackTab natively — SHIFT-TAB there
falls back to no-op for MVP. `Readline` may handle it if configured via
`.inputrc`; that's best-effort.

### 11.5 Decision summary

| Option | Viable? | What it costs | Recommendation |
|---|---|---|---|
| Embed reedline via Rust FFI in `rak` | No | Requires C ABI from reedline, MoarVM NativeCall bridge, new build dep | **Reject** — the REPL already has a pure-Raku line editor backend |
| Call `nu --explore` as subprocess for SHIFT-TAB | Technically yes | ~60ms startup per invocation, awkward stdin/stdout juggle | **Acceptable as a configurable option**, not the default |
| Write a nushell external completer (`rak --complete`) | Yes | ~50 lines of Raku + one line of nushell config | **Future (§12)** — orthogonal to the REPL, useful for people who edit `.rak` files in nushell |
| **Extend the existing Raku REPL's `completions-for-line`** | **Yes** | Pure Raku, no new deps, ~200 lines total | **Default path for MVP** |
| BackTab → YAML preview via `Terminal::LineEditor` | **Yes** | ~50 lines of Raku (new method on REPL) | **Default path for MVP** |

### 11.6 Nushell external completer (future, §12 sketch)

If nushell is configured as the user's shell, `rak --complete` could serve
as nushell's external completer for Raku source files:

```nushell
# In $env.config.completions.external:
completer: {|ctx|
    if ($ctx.file | path extension) =~ 'rak|raku|rakumod|pm6' {
        ^rak --complete $ctx.line $ctx.pos
        | from json
    }
}
```

Where `rak --complete` reads `$line` and `$pos` from argv, parses the
buffer to find `.`-subscript positions, and returns completions as JSON:

```json
[
  {"value": "name", "description": "Str key"},
  {"value": "age", "description": "Int key"}
]
```

This is a small, standalone Raku script registered as a nushell plugin.
It does not require the full REPL; it only needs the `Completions`-role
logic (parse-at-cursor + subscript-completions) factored into a library
that both the REPL and the `--complete` entry point can use.

### 11.7 Integration architecture (final)

```
╔═══════════════════════════════════════════════════════════════════╗
║                    Raku REPL (src/core.c/REPL.rakumod)          ║
║  ┌─────────────────────────────────────────────────────────┐    ║
║  │ Completions role                                         │    ║
║  │  - completions-for-line (existing: symbols)              │    ║
║  │  + parse-at-cursor        (NEW: detect . as anchor)      │    ║
║  │  + subscript-completions  (NEW: eval subject, list keys) │    ║
║  │  + yaml-preview           (NEW: BackTab → YAML preview)  │    ║
║  └─────────────────────────────────────────────────────────┘    ║
║  ┌────────────┬──────────────┬────────────────────┐            ║
║  │ Readline   │ Linenoise    │ Terminal::LineEditor│            ║
║  │ (Tab only) │ (Tab only)   │ (Tab + BackTab)     │            ║
║  └────────────┴──────────────┴────────────────────┘            ║
╚═══════════════════════════════════════════════════════════════════╝
                           │
                           v
╔═══════════════════════════════════════════════════════════════════╗
║              `rak` binary (shell wrapper: raku --rak-mode)       ║
║  Sets $*NEW-DOTTY-SEMANTICS=1 in REPL (no source-file fallback) ║
║  Also provides `rak --complete` for nushell external completer   ║
╚═══════════════════════════════════════════════════════════════════╝
                           │
                           v
╔═══════════════════════════════════════════════════════════════════╗
║  Nushell integration (optional, post-MVP)                       ║
║  ┌─────────────────────────────────────────────────────────┐    ║
║  │ External completer: `rak --complete $line $pos`         │    ║
║  │ Returns JSON completions to nushell's reedline          │    ║
║  │ Registered in $env.config.completions.external          │    ║
║  └─────────────────────────────────────────────────────────┘    ║
╚═══════════════════════════════════════════════════════════════════╝
```