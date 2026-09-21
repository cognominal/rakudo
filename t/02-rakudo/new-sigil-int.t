use Test;

# Test-first spec for the new `#` (native int) sigil.
# Design: CLAUDE.md, "Feature: new fixed-type sigils `~` (Str) and `#` (int)".
#
# NOTHING IS IMPLEMENTED YET (CLAUDE.md §5, Phase 1). Every "positive"
# assertion below is expected to fail (report `Any`/undefined) until `#` is
# added to `token sigil`, `comment:sym<#>` is tightened, and `#` is wired to
# force the native `int` type through the existing IMPL-CONTAINER primspec
# path (CLAUDE.md §2). This file is the acceptance target for that phase,
# not a description of current behavior.
#
# `#name` is deliberately native `int`, not boxed `Int` — see CLAUDE.md §1/§3
# for why that asymmetry with `~`/`Str` is intentional, not a typo.
#
# Per CLAUDE.md §0 (no compatibility policy), there is no gating and no
# attempt to keep old unspaced `#comment` text working the way it used to —
# see CLAUDE.md §4.2/§4.3 for what breaks and why that's accepted here.
#
# All `#`-sigil syntax below is inside EVAL'd strings, never written
# directly in this file: this file itself must keep parsing under the
# *current*, unmodified grammar regardless of whether the feature exists yet.

plan 18;

# `try` keeps a compile-time failure (the expected state today) a normal,
# reported failure for that one test, instead of aborting the whole file.
sub try-eval(str $code) { try EVAL($code) }

# --- declaration, type, default, mutation, arithmetic ---

is try-eval('my #n = 5; #n'), 5,
    'my #n = 5 declares a #-sigiled scalar and #n reads its value';

is try-eval('my #n = 5; #n.WHAT'), Int,
    '#n autoboxes to Int when introspected (native storage, boxed on demand)';

is try-eval('my #n; #n'), 0,
    'an uninitialized #n defaults to 0 (native int semantics, unlike ~s/undefined Str)';

is try-eval('my #n = 5; #n = 9; #n'), 9,
    '#n can be reassigned after declaration';

is try-eval('my #n = 5; #n + 3'), 8,
    '#n participates in arithmetic like any Int-ish value';

# --- interpolation ---

is try-eval('my #n = 7; "count: #n"'), 'count: 7',
    '#name interpolates in a double-quoted string';

# --- the sigil already implies the type: an explicit type is an error ---
# (these already "fail to compile" today for the unrelated reason that `#`
# isn't a sigil at all yet; they become meaningful once Phase 1 lands, to
# confirm the explicit-type *rejection* itself was implemented and not just
# incidentally absent along with the rest of the feature)

throws-like 'my int #n = 5;', Exception,
    'an explicit (redundant) native int type on a #-sigiled declaration is a compile-time error';

throws-like 'my Int #n = 5;', Exception,
    'an explicit boxed Int type on a #-sigiled declaration is a compile-time error (native vs boxed still counts as "typed")';

throws-like 'my Str #n = 5;', Exception,
    'an explicit (conflicting) Str type on a #-sigiled declaration is a compile-time error';

throws-like 'my #n is Int = 5;', Exception,
    'an `is Int` trait on a #-sigiled declaration is a compile-time error';

# --- `where` still works: it is a runtime refinement, not a type ---

is try-eval('my #n where * > 0 = 5; #n'), 5,
    'a `where` constraint on #n is allowed and satisfied';

throws-like 'my #n where * > 0 = -5;', Exception,
    'a violated `where` constraint on #n still dies, same as for $-sigiled variables';

# --- inherited native-scalar limitation: state is not yet implemented ---

throws-like 'sub f { state #n = 0; #n++ }; f; f;', Exception,
    '#n cannot be state-scoped yet, inheriting the existing "Natively typed state variables not yet implemented" limitation';

# --- attributes: has #.x is a public native-int attribute ---

is try-eval('class NewSigilIntAttr { has #.x = 5 }; NewSigilIntAttr.new(x => 9).x'), 9,
    'has #.x declares a public native-int attribute with a working accessor and constructor argument, like `has int $.x` today';

# --- signature parameters ---

is try-eval('sub f(#x) { #x }; f(5)'), 5,
    'a #-sigiled signature parameter works the same as a #-sigiled my variable';

# --- comment-spacing disambiguation (CLAUDE.md §4.2) ---

my $spaced-comment-code = q:to/CODE/.trim;
my #n = 5; # a real comment with a space after #, unaffected by the sigil
42
CODE
is try-eval($spaced-comment-code), 42,
    'a "# " comment (space right after #) is still an ordinary comment';

my $banner-comment-code = q:to/CODE/.trim;
#----------------------------------------
# a banner comment: no identifier follows the very first #, so it can't
# be a desigilname and stays a comment either way
42
CODE
is try-eval($banner-comment-code), 42,
    'a #---- banner comment (non-identifier-start after #) still behaves as a comment';

throws-like '#thisWasNeverDeclared', Exception,
    'a bare #identifier with no matching #-sigiled declaration is now a compile-time error (undeclared variable), not a silently-swallowed comment';

# vim: expandtab shiftwidth=4
