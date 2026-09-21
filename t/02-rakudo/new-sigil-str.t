use Test;

# Test-first spec for the new `~` (Str) sigil.
# Design: CLAUDE.md, "Feature: new fixed-type sigils `~` (Str) and `#` (int)".
#
# NOTHING IS IMPLEMENTED YET (CLAUDE.md §5, Phase 2). Every "positive"
# assertion below is expected to fail (report `Any`/undefined) until `~` is
# added to `token sigil` and wired through IMPL-CALCULATE-TYPES. This file
# is the acceptance target for that phase, not a description of current
# behavior.
#
# Per CLAUDE.md §0 (no compatibility policy), there is no gating and no
# attempt to keep this and the old bareword-stringify reading of `~foo`
# coexisting — see new-sigil-int.t's header for the parallel note on `#`,
# and CLAUDE.md §4.1 for what the old reading was and why it's dropped.
#
# All `~`-sigil syntax below is inside EVAL'd strings, never written
# directly in this file: this file itself must keep parsing under the
# *current*, unmodified grammar regardless of whether the feature exists yet.

plan 13;

# `try` keeps a compile-time failure (the expected state today) a normal,
# reported failure for that one test, instead of aborting the whole file.
sub try-eval(str $code) { try EVAL($code) }

# --- declaration, type, default, mutation ---

is try-eval('my ~s = "hello"; ~s'), 'hello',
    'my ~s = "..." declares a ~-sigiled scalar and ~s reads its value';

is try-eval('my ~s = "hello"; ~s.WHAT'), Str,
    '~s is a Str';

is try-eval('my ~s; ~s.WHAT'), Str,
    'an uninitialized ~s is still typed Str (the type object)';

is try-eval('my ~s; ~s.defined'), False,
    'an uninitialized ~s is undefined, same as `my Str $x`';

is try-eval('my ~s = "a"; ~s = "b"; ~s'), 'b',
    '~s can be reassigned after declaration';

# --- interpolation ---

is try-eval('my ~s = "world"; "hello ~s"'), 'hello world',
    '~name interpolates in a double-quoted string';

# --- the sigil already implies the type: an explicit type is an error ---
# (these already "fail to compile" today for the unrelated reason that `~`
# isn't a sigil at all yet; they become meaningful once Phase 2 lands, to
# confirm the explicit-type *rejection* itself was implemented and not just
# incidentally absent along with the rest of the feature)

throws-like 'my Str ~s = "a";', Exception,
    'an explicit (redundant) Str type on a ~-sigiled declaration is a compile-time error';

throws-like 'my Int ~s = "a";', Exception,
    'an explicit (conflicting) Int type on a ~-sigiled declaration is a compile-time error';

throws-like 'my ~s is Str = "a";', Exception,
    'an `is Str` trait on a ~-sigiled declaration is a compile-time error';

# --- `where` still works: it is a runtime refinement, not a type ---

is try-eval('my ~s where *.chars > 0 = "ok"; ~s'), 'ok',
    'a `where` constraint on ~s is allowed and satisfied';

throws-like 'my ~s where *.chars > 0 = "";', Exception,
    'a violated `where` constraint on ~s still dies, same as for $-sigiled variables';

# --- attributes: has ~.x is a public Str-typed attribute ---

is try-eval('class NewSigilStrAttr { has ~.x = "default" }; NewSigilStrAttr.new(x => "v").x'), 'v',
    'has ~.x declares a public Str attribute with a working accessor and constructor argument';

# --- signature parameters ---

is try-eval('sub f(~x) { ~x }; f("z")'), 'z',
    'a ~-sigiled signature parameter works the same as a ~-sigiled my variable';

# vim: expandtab shiftwidth=4
