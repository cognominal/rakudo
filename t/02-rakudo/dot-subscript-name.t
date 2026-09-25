use Test;

# Test-first spec for SUBSCRIPT-OPERATOR.md's §5 Phase 3: in a `.rak`-mode
# source file, a bare `.identifier` (no following `(`/adverbial `: args`)
# is sugar for `<identifier>` (literal hash-key lookup), not a parameterless
# method call — parameterless method calls move to `->identifier` instead.
# `.identifier(args)`/`.identifier: args` (real method calls with explicit
# arguments) are unaffected by any of this. `.raku`/`.rakumod` files are
# completely unaffected: `.identifier` there keeps meaning exactly what it
# always has, and `->identifier` stays the pre-existing obsolete-syntax
# error.
#
# This phase can't use the usual EVAL'd-string pattern the other new-syntax
# test files in this directory use, because the behavior under test is
# keyed off the *file extension* of the compilation unit itself — something
# EVAL has no notion of. So this file writes real fixture files to a temp
# directory and runs each one in a subprocess with the RakuAST frontend
# (RAKUDO_RAKUAST=1) explicitly requested, matching how
# t/02-rakudo/compiler-frontend-id.t already drives cross-frontend
# subprocess checks.

plan 11;

my $tmp-dir = $*TMPDIR.add("dot-subscript-name-test-{$*PID}");
mkdir $tmp-dir;
END { rmdir $tmp-dir if $tmp-dir.e }

my $n = 0;

sub run-file(str $ext, str $code) {
    my $path = $tmp-dir.add("f{$n++}.$ext");
    spurt $path, $code;
    LEAVE { unlink $path }

    my %env = %*ENV;
    %env<RAKUDO_RAKUAST> = 1;

    my $proc = run $*EXECUTABLE.absolute, $path.absolute, :env(%env), :out, :err;
    my $out  = $proc.out.slurp(:close);
    my $err  = $proc.err.slurp(:close);
    %(:$out, :$err, exitcode => $proc.exitcode);
}

# --- .rak mode: bare .identifier is <identifier> sugar, not a method call ---

is run-file('rak', 'my %h = toto => 42; print %h.toto;').<out>, '42',
    '.rak: %h.toto reads the same element as %h<toto>';

is run-file('rak', 'my %h; %h.toto = 42; print %h<toto>;').<out>, '42',
    '.rak: %h.toto = 42 assigns the same as %h<toto> = 42';

is run-file('rak', 'my %h = toto => "x"; print((%h.toto eq %h<toto>)->Str);').<out>, 'True',
    '.rak: %h.toto and %h<toto> give the identical value';

# --- .rak mode: ->identifier is the real parameterless method call ---

is run-file('rak', 'class Foo { method bar() { "bar-called" } }; my $f = Foo->new; print $f->bar;').<out>,
    'bar-called',
    '.rak: Foo->new / $f->bar are real parameterless method calls';

# --- .rak mode: method calls WITH arguments are unaffected ---

is run-file('rak', 'class Foo { method baz(Int $x) { "baz-$x" } }; my $f = Foo->new; print $f.baz(5);').<out>,
    'baz-5',
    '.rak: .identifier(args) is still a real method call, unaffected';

is run-file('rak', 'class Foo { method baz(Int $x) { "baz-$x" } }; my $f = Foo->new; print $f.baz: 5;').<out>,
    'baz-5',
    '.rak: .identifier: args (colon-arg form) is still a real method call, unaffected';

# --- .rak mode: ->[ / ->{ / ->( stay obsolete-syntax errors ---

my $bracket-arrow = run-file('rak', 'my @a = 1, 2, 3; print @a->[0];');
isnt $bracket-arrow.<exitcode>, 0,
    '.rak: @a->[0] is still a compile-time error, not repurposed as a deref';
like $bracket-arrow.<err>, /'postfix dereferencer'/,
    '.rak: @a->[0]\'s error is the existing obsolete-postfix-dereferencer message';

# --- .rak mode: chains with the pre-existing .1/.~/.# sugar ---

is run-file('rak', 'my %h; %h<toto> = [10, 20, 30]; my #i = 1; print %h.toto.#i;').<out>, '20',
    '.rak: %h.toto.#i chains .identifier sugar with the existing .#expr sugar';

# --- .raku mode: nothing here changes ---

is run-file('raku', 'class Foo { method bar() { "bar-called" } }; print Foo.new.bar;').<out>,
    'bar-called',
    '.raku: .new / .bar stay real parameterless method calls, unaffected';

my $raku-arrow = run-file('raku', 'class Foo { method bar() { "bar-called" } }; my $f = Foo.new; print $f->bar;');
isnt $raku-arrow.<exitcode>, 0,
    '.raku: $f->bar still errors as obsolete postfix syntax, unaffected';

# vim: expandtab shiftwidth=4
