# Converting PLAN/RAKFILE.md to a general blueprint

> **Context:** The original `RAKFILE.md` was written for the **`new-sigils`** branch, which implemented new dotty semantics (`.name → <name>`, `->name → real method call`) gated to files with a `.rak` extension.
>
> The **3-step scheme** it describes — capture filename → thread into a dynamic variable in `comp-unit-prologue` → branch the grammar with `<?{ }>` — **is the exact scheme we adopt wholesale** for the current branch (adding shellish redirection support to `.rak` files). Everything documented below follows that same architecture.
>
> Below is the original mechanism, annotated for the redirection goal.

---

## Two executables: `rak` vs `raku`

There will be **two executables** — `rak` and `raku` — with the following contract:

### `rak` (no arguments)

Running **`rak` without arguments** enters an interactive **REPL/shell** that uses **`.rak` semantics** — the same extension-gated parsing that `.rak` files get. This means all `.rak` features (redirection, dotty semantics, etc.) are active in the REPL.

This is equivalent to `raku` with an imaginary `.rak` source — the dynamic flag `$*RAK-SEMANTICS` (or equivalent) is set to true by default in the REPL path.

### `rak <file>` / `raku <file>`

When **either executable is given a file argument**, the **file extension determines the semantics**:

| Extension | Semantics used |
|-----------|----------------|
| `.rak` | Full rak syntax (dotty, redirection, all extensions) |
| `.raku`, `.rakumod`, `.pm6`, `.nqp` | Traditional Raku semantics (no new syntax) |
| No extension / unknown | Falls back to traditional semantics |

This means:
- `rak script.rak` → compiles with all rak features enabled
- `rak script.raku` → compiles with traditional semantics (same as `raku script.raku`)
- `raku script.rak` → compiles with all rak features (the extension gates the syntax, not the executable name)

The executable name (`rak` vs `raku`) is irrelevant when a file argument is given — **only the extension matters**. Both honor the same extension-based gating mechanism described in the sections below.

### Implementation consequence

The `$*RAK-SEMANTICS` dynamic variable (or the specific flags like `$*NEW-DOTTY-SEMANTICS` and `$*REDIRECTION-SYNTAX`) must be set to **true for the REPL** when launched from `rak`, and **determined by the file extension** when a file argument is given by either executable.

---

## Redirection syntax design

### Naked strings

A **naked string** is an unquoted string value with these properties:

- Contains no whitespace
- Starts with an alphanumeric character (`[a-zA-Z0-9]`)
- Is **not** interpretable as a number literal (`42`, `3.14`, `0xff`, `1e10`, etc.)
- No globbing (for now)

Examples of naked strings:

| Token | Naked string? | Reason |
|-------|---------------|--------|
| `foo` | ✅ yes | Starts with alpha, not a number |
| `foo.txt` | ✅ yes | Starts with alpha, dot is allowed inside |
| `file123` | ✅ yes | Starts with alpha, digits inside are fine |
| `a_b` | ✅ yes | Underscore is allowed inside |
| `42` | ❌ no | Interpretable as an integer |
| `3.14` | ❌ no | Interpretable as a number |
| `0xff` | ❌ no | Interpretable as a hex number |
| `1e10` | ❌ no | Interpretable as scientific notation |
| `foo bar` | ❌ no | Contains whitespace |
| `$foo` | ❌ no | Starts with `$`, not alphanumeric (it's a variable) |

### Binary operators are space-delimited

All binary operators (`>`, `>=`, `<`, `<=`, `==`, `!=`, `~~`, `+`, `-`, `*`, etc.) **must be surrounded by whitespace** in rak syntax. This is what prevents ambiguity between:

- `say foo >foo.txt` → `>` is a **redirection** operator (no space after `>`, the filename `foo.txt` is directly attached)
- `say foo > foo.txt` → `>` is a **comparison** operator (spaces on both sides, comparing two naked strings)
- `$a > $b` → `>` is a **comparison** operator (variables on both sides)
- `$a > 42` → `>` is a **comparison** operator

A token `>` that **touches the filename on the right** (`>foo.txt`) is a redirection. A token `>` with spaces on both sides (`> foo.txt`) is a comparison. This rule makes parsing redirection unambiguous without lookahead.

### Where redirections can appear

Redirection operators are only valid at **two positions** in a statement. The operator must **directly touch the filename** (no space between the operator and the filename):

| Position | Example | Meaning |
|----------|---------|---------|
| **Start of statement** | `<input.txt say $x` | Read input from file `input.txt` |
| **End of statement** | `say $x >output.txt` | Write output to file `output.txt` |
| End (append) | `say $x >>output.txt` | Append output to file `output.txt` |

The following are **not** redirection because there's a space after the operator:

| Non-example | Why |
|-------------|-----|
| `say $x > output.txt` | Space after `>` — it's a comparison `$x > output.txt` |
| `say $x < input.txt` | Space after `<` — it's a comparison |

Redirections in the middle of a statement are **not supported**.

### The filename: quoted string, naked string, or scalar variable

The filename after the redirection operator must evaluate to a string. Currently supported:

| Form | Example | Valid? |
|------|---------|--------|
| Naked string | `say foo >foo.txt` | ✅ yes |
| Quoted string | `say foo >'foo.txt'` | ✅ yes |
| Quoted string with spaces | `say foo >'my file.txt'` | ✅ yes |
| Scalar variable | `say foo >$file` | ✅ yes |
| Postcircumfix (future) | `say foo >@files[0]` or `say foo >%config<output>` | 🔜 later |
| Postcircumfix with new sigils (future) | `say foo >.filename` or `say foo >.conf<output>` | 🔜 later |

A scalar variable like `$file` is dereferenced at runtime to get the filename. Postcircumfix expressions (array indexing, hash lookup, and the new dotty-sigil forms) will be supported in a future step.

This restriction keeps the initial grammar simple: the redirection target is a single token directly adjacent to the operator.

### First step: output redirection with `>`

The first concrete goal is to support:

```raku
say foo >foo.txt
```

Here:
- `foo` → naked string, value is `"foo"` (the content to print)
- `>` → output redirection operator, **directly touching** the filename (no space)
- `foo.txt` → naked string, value is `"foo.txt"` (the target filename)

`say` evaluates to `"foo"` and writes it to the file `foo.txt`.

### All equivalent forms

All of the following produce the **same result**:

```raku
# Naked string content + naked string filename
say foo >foo.txt

# Quoted string content + naked string filename
say 'foo' >foo.txt

# Variable content + naked string filename
my $foo = 'foo';
say $foo >foo.txt

# Naked string content + quoted string filename
say foo >'foo.txt'

# Quoted string content + quoted string filename
say 'foo' >'foo.txt'

# Variable content + quoted string filename
my $foo = 'foo';
say $foo >'foo.txt'

# Naked string content + scalar variable filename
my $file = 'foo.txt';
say foo >$file

# Quoted string content + scalar variable filename
my $file = 'foo.txt';
say 'foo' >$file

# Variable content + scalar variable filename
my $foo = 'foo';
my $file = 'foo.txt';
say $foo >$file
```

In every case, `say` receives the string `"foo"` and the output is redirected to the file named `foo.txt`. The redirection target can be a naked string, a quoted string, or a scalar variable.

### How naked strings interact with `say`

`say` in Raku already takes a list of strings (or anything that does `.Str`). A naked string like `foo` is parsed as a string literal `"foo"`, so:

```raku
say foo            # prints "foo\n"
say 'foo'          # prints "foo\n"
say foo bar baz    # prints "foo bar baz\n" (three naked strings)
```

The redirection `>` then intercepts the output of `say` and writes it to the specified file instead of stdout.

---

## The general mechanism (end to end)

The core idea: new syntax should apply **only** to `.rak` files, leaving `.raku`/`.rakumod`/`.pm6`/`.nqp` completely untouched. This must not be a global grammar change.

Three pieces, threaded together:

### 1. Capture the source filename

**File:** `src/Perl6/Compiler.nqp`, in `command_eval`

NQP's `HLL::Compiler.evalfiles` computes the filename internally but never threads it into `%adverbs`. Rakudo must grab it itself.

```nqp
unless nqp::defined(%options<e>) || nqp::defined(%options<source-name>) {
    %options<source-name> := @args[0] if nqp::elems(@args);
}
```

This only fires for a plain file argument, not `-e`/STDIN, so those always fall back to traditional semantics (no extension to opt in with).

For the **redirection** branch, this is where the source filename is captured the same way — the redirection grammar branches will read the same dynamic variable.

### 2. Turn the filename into a dynamic variable

**File:** `src/Raku/Actions.nqp`, in `comp-unit-prologue` (same hook that sets `$*LANGUAGE-REVISION`)

```nqp
my str $source-name := %*COMPILING<%?OPTIONS><source-name> // '';
$*NEW-DOTTY-SEMANTICS := (nqp::chars($source-name) >= 4
  && nqp::eqat($source-name, '.rak', nqp::chars($source-name) - 4))
  ?? 1 !! 0;
```

For the **redirection** branch, this same pattern applies. Instead of `$*NEW-DOTTY-SEMANTICS`, use a new dynamic variable — say `$*REDIRECTION-SYNTAX`:

```nqp
my str $source-name := %*COMPILING<%?OPTIONS><source-name> // '';
$*REDIRECTION-SYNTAX := (nqp::chars($source-name) >= 4
  && nqp::eqat($source-name, '.rak', nqp::chars($source-name) - 4))
  ?? 1 !! 0;
```

The dynamic variable must be declared with `:my` in a grammar token to give it the same "fresh per-compilation-unit, doesn't leak across `use`/`EVAL`" scoping that `$*LANGUAGE-REVISION` already has for free. A `.rak` file `use`-ing a `.rakumod` module doesn't affect the module's own parsing, and vice versa.

### 3. Branch the grammar on that flag

**File:** `src/Raku/Grammar.nqp`

The original `RAKFILE.md` describes two branching spots in the grammar:

- **postfixish:** a new `dotty-name-sugar` alternative tried via `||` (procedural, first-match) ahead of the existing `|`-based LTM group that contains real method-call parsing.
- **postfix:sym«->»:** gained `<?{ $*NEW-DOTTY-SEMANTICS }> <methodop(Mu)>` as its first-tried branch.

For the **redirection** branch, the same technique applies — you gate new redirection syntax tokens with `<?{ $*REDIRECTION-SYNTAX }>` assertions. The redirection operators (`>`, `>>`, `<`) would be added as new alternatives gated by this flag, so they only activate when parsing a `.rak` file.

The key pattern:

```perl6
token postfix:sym«redir-out» {
    <?{ $*REDIRECTION-SYNTAX }>
    '>>'  # or '>', '<'
    ...
}
```

Or if the redirection operators conflict with existing tokens (like `>` already meaning "generic comparison" or `>>` being a hyper operator), the branching must use `||` (procedural) instead of `|` (LTM), exactly as the original `RAKFILE.md` describes for dotty-name-sugar.

---

## Summary for the redirection branch

| Step | File | What to do |
|------|------|------------|
| 1 | `src/Perl6/Compiler.nqp` | Already done — same capture of `%options<source-name>` |
| 2 | `src/Raku/Actions.nqp` | Add `$*RAK-SEMANTICS` (or `<feature>-SYNTAX` flags) check in `comp-unit-prologue`, same `.rak` check |
| 2b | `src/Raku/Grammar.nqp` | Declare `:my $*RAK-SEMANTICS;` (or per-feature dynamic variables) in the relevant token with the same per-compilation-unit scope |
| 3 | `src/Raku/Grammar.nqp` | Add redirection syntax tokens gated by `<?{ $*RAK-SEMANTICS }>` |
| 4 | `src/Perl6/Compiler.nqp` or REPL entry | Force `$*RAK-SEMANTICS` to true when `rak` starts in REPL mode |

---

## Next steps

### 1. Generate tests first

Before touching any grammar or compiler code, the **first step** is to write a suite of test files that exercise the redirection syntax using the same `.rak` extension-gating scheme. These tests will:

- Define the expected behavior before the implementation exists
- Serve as the specification for what the grammar changes must produce
- Be runnable with `raku` (once the feature is implemented) and gated by the `.rak` extension

The test files live in `t/` and use the `.rak` extension so they exercise the full extension-gating path. Example:

```raku
# t/redirection-basic.rak
use Test;

# Output redirection with naked strings
say foo >output.txt;
ok 'output.txt'.IO.e, 'file was created';
is 'output.txt'.IO.slurp.trim, 'foo', 'content matches';

# Quoted strings produce the same result
say 'bar' >output2.txt;
is 'output2.txt'.IO.slurp.trim, 'bar', 'quoted strings work';

# Variables work too
my $msg = 'hello';
say $msg >output3.txt;
is 'output3.txt'.IO.slurp.trim, 'hello', 'variables work';

# Quoted filename (allows spaces)
say 'baz' >'my output.txt';
is 'my output.txt'.IO.slurp.trim, 'baz', 'quoted filename works';

# Variable content + quoted string filename
my $msg2 = 'test';
say $msg2 >'test output.txt';
is 'test output.txt'.IO.slurp.trim, 'test', 'variable + quoted filename works';

# Scalar variable as filename
my $outfile = 'var-output.txt';
say 'from-var' >$outfile;
is $outfile.IO.slurp.trim, 'from-var', 'scalar variable as filename works';

done-testing;
``````

Running with traditional `.raku` extension **must fail** (or at least not interpret `>` as redirection), confirming the gating mechanism works:

```bash
$ raku t/redirection-basic.rak      # works — .rak gates the new syntax
$ raku t/redirection-basic.raku     # fails — .raku uses traditional semantics
```

### 2. Implement compiler changes

Once the tests are written and the expected behaviour is clear, implement the 3-step scheme detailed above:

1. Capture filename in `Compiler.nqp`
2. Set `$*RAK-SEMANTICS` in `Actions.nqp`
3. Branch the grammar in `Grammar.nqp`

### 3. Run tests

Execute the test suite to verify:

```bash
$ raku t/redirection-basic.rak
```

The `.rak` extension triggers the feature; the extension-based gating keeps all existing `.raku`/`.rakumod`/`.pm6`/`.nqp` tests unaffected.