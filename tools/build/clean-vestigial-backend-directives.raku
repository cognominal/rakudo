#!/usr/bin/env raku
# Remove vestigial #?if jvm / #?if !jvm / #?if js / #?if !js directives
# since those backends are no longer maintained.
#
# Semantics:
#   #?if jvm    → DELETE the block entirely (JVM dead)
#   #?if !jvm   → KEEP inner lines, remove guards (everyone is "not JVM" now)
#   #?if js     → DELETE the block entirely (JS dead)
#   #?if !js    → KEEP inner lines, remove guards (everyone is "not JS" now)

use strict;

sub MAIN(*@files) {
    for @files -> $file {
        next unless $file.IO.f;
        my @lines = $file.IO.lines;
        my @out;
        my $i = 0;
        my $changed = False;
        my $in_any_cond = 0;  # track nesting depth of ANY #?if (for accurate stray detection)

        while $i < @lines.elems {
            my $line = @lines[$i];

            if $line ~~ /^ '#?if' \s+ ('!'?) (jvm|js) \s* $/ {
                my $neg = ~$0;
                my $backend = ~$1;
                my $delete_block = $neg ?? False !! True;

                $i++;
                my @block;
                my $found_endif = False;
                while $i < @lines.elems {
                    if @lines[$i] ~~ /^ '#?endif' \s* $/ {
                        $found_endif = True;
                        $i++;
                        last;
                    }
                    # Guard against nested conditionals (gen-cat doesn't support them)
                    if @lines[$i] ~~ /^ '#?if' \s/ {
                        die "Nested conditional in $file at line $i (not supported)";
                    }
                    push @block, @lines[$i];
                    $i++;
                }

                unless $found_endif {
                    note "Unmatched #?if in $file at line $i";
                    push @out, "#?if " ~ ($neg ?? "!" ~ $backend !! $backend);
                    $i -= @block.elems + 1;
                    next;
                }

                if $delete_block {
                    $changed = True;
                    # Skip the entire block
                }
                else {
                    $changed = True;
                    push @out, @block.Slip;
                }
            }
            elsif $line ~~ /^ '#?if' \s+ ('!'?) (\w+) \s* $/ {
                # Non-jvm/js conditional (#?if moar, #?if !moar)
                $in_any_cond++;
                push @out, $line;
                $i++;
            }
            elsif $line ~~ /^ '#?endif' \s* $/ {
                if $in_any_cond {
                    $in_any_cond--;
                    push @out, $line;
                }
                else {
                    note "Stray #?endif in $file at line $i (no matching #?if) — keeping as-is";
                    push @out, $line;
                }
                $i++;
            }
            else {
                push @out, $line;
                $i++;
            }
        }

        if $changed {
            say "Cleaning: $file";
            $file.IO.spurt: @out.join("\n") ~ "\n";
        }
    }
}

# vim: expandtab sw=4