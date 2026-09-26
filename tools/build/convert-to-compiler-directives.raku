#!/usr/bin/env raku
# Convert #?if moar / #?endif to #COMPILER::if moar / #COMPILER::endif
# in .rakumod core source files. Leaves #?if / #?endif (non-moar) untouched
# since those are handled by gen-cat for NQP sources.

use strict;

sub MAIN(*@files) {
    for @files -> $file {
        next unless $file.IO.f;
        my $content = $file.IO.slurp;
        my $changed = $content.subst-mutate(
            / ^^ '#?if' \s+ ('!'?) (moar) \s* $$ /,
            { "#COMPILER::if $0$1" },
            :g
        );
        $changed = $content.subst-mutate(
            / ^^ '#?endif' \s* $$ /,
            { "#COMPILER::endif" },
            :g
        ) || $changed;
        if $changed {
            say "Converting: $file";
            $file.IO.spurt: $content;
        }
    }
}