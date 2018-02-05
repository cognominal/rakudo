use v6.d.PREVIEW;
use lib <t/packages/>;
use Test;
use Test::Helpers;

plan 1;

# https://github.com/rakudo/rakudo/issues/1323
throws-like { await 42 }, Exception, 'giving await non-Awaitable things throws';

# vim: ft=perl6 expandtab sw=4
