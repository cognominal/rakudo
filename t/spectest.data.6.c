# This is a list of all spec tests that are expected to pass.
#
# Empty lines and those beginning with a # are ignored
#
# We intend to include *all* tests from roast, even when we
# skip most of the tests or the entire test file. To verify
# we are running all tests, run:
#
# perl tools/update-passing-test-data.pl
#
# If a file appears in the output of the script, it is not run
# by default. It may need to be fudged in order to run successfully.
# Open an RT when necessary as part of the fudge process, using the
# RT in the fudge message, and then add the test file to this file, sorted.
#
# Each file may have one or more markers that deselects the test:
#     long   - run tests unless --quick
#     stress - run tests only if --stress
#     moar   - run tests only for MoarVM backend
# See the "make quicktest" and "make stresstest" targets in
# build/Makefile.in for examples of use.


S01-perl-5-integration/basic.t              # perl5
S01-perl-5-integration/class.t              # perl5
S01-perl-5-integration/exception_handling.t # perl5
S01-perl-5-integration/hash.t               # perl5
S01-perl-5-integration/import.t             # perl5
S01-perl-5-integration/return.t             # perl5
S01-perl-5-integration/roundtrip.t          # perl5
S01-perl-5-integration/subs.t               # perl5
S02-lexical-conventions/begin_end_pod.t
S02-lexical-conventions/bom.t
S02-lexical-conventions/end-pod.t
S02-lexical-conventions/minimal-whitespace.t
S02-lexical-conventions/one-pass-parsing.t
S02-lexical-conventions/pod-in-multi-line-exprs.t
S02-lexical-conventions/sub-block-parsing.t
S02-lists/indexing.t
S02-lists/tree.t
S02-literals/allomorphic.t
S02-literals/array-interpolation.t
S02-literals/autoref.t
S02-literals/char-by-number.t
S02-literals/fmt-interpolation.t
S02-literals/hash-interpolation.t
S02-literals/listquote-whitespace.t
S02-literals/subscript.t
S02-literals/types.t
S02-literals/underscores.t
S02-literals/version.t
S02-magicals/78258.t
S02-magicals/args.t
S02-magicals/block.t
S02-magicals/dollar-underscore.t
S02-magicals/file_line.t
S02-magicals/pid.t
S02-magicals/progname.t
S02-magicals/subname.t
S02-names/bare-sigil.t
S02-names/identifier.t
S02-names/indirect.t
S02-names/is_cached.t
S02-names/is_dynamic.t
S02-names/name.t
S02-names/pseudo.t
S02-names-vars/contextual.t
S02-names-vars/list_array_perl.t
S02-names-vars/variables-and-packages.t
S02-one-pass-parsing/less-than.t
S02-packages/package-lookup.t
S02-types/array_extending.t
S02-types/assigning-refs.t
S02-types/autovivification.t
S02-types/bag.t
S02-types/built-in.t
S02-types/catch_type_cast_mismatch.t
S02-types/flattening.t
S02-types/hash_ref.t
S02-types/instants-and-durations.t
S02-types/keyhash.t
S02-types/lazy-lists.t
S02-types/lists.t
S02-types/mix.t
S02-types/nan.t
S02-types/nested_arrays.t
S02-types/nested_pairs.t
S02-types/parsing-bool.t
S02-types/range.t
S02-types/resolved-in-setting.t    # moar
S02-types/sethash.t
S02-types/subscripts_and_context.t
S02-types/subset.t
S02-types/version.t
S03-binding/arrays.t
S03-binding/hashes.t
S03-binding/nested.t
S03-junctions/associative.t
S03-metaops/cross.t
S03-metaops/reverse.t
S03-metaops/zip.t
S03-operators/andthen.t
S03-operators/orelse.t
S03-operators/assign-is-not-binding.t
S03-operators/autoincrement-range.t
S03-operators/autovivification.t
S03-operators/bag.t
S03-operators/basic-types.t
S03-operators/boolean-bitwise.t
S03-operators/composition.t
S03-operators/custom.t
S03-operators/chained-declarators.t
S03-operators/cmp.t
S03-operators/context.t
S03-operators/gcd.t
S03-operators/div.t
S03-operators/infixed-function.t
S03-operators/lcm.t
S03-operators/list-quote-junction.t
S03-operators/mix.t
S03-operators/not.t
S03-operators/numeric-shift.t
S03-operators/range-basic.t
S03-operators/range-int.t
S03-operators/range.t
S03-operators/scalar-assign.t
S03-operators/set.t
S03-operators/so.t
S03-operators/spaceship.t
S03-operators/subscript-adverbs.t
S03-operators/subscript-vs-lt.t
S03-operators/value_equivalence.t
S03-sequence/arity0.t
S03-sequence/arity-2-or-more.t
S03-sequence/basic.t
S03-sequence/limit-arity-2-or-more.t
S03-smartmatch/any-complex.t
S03-smartmatch/any-method.t
S03-smartmatch/capture-signature.t
S04-blocks-and-statements/pointy-rw.t
S04-declarations/multiple.t
S04-declarations/my.t
S04-declarations/our.t
S04-declarations/smiley.t
S04-exception-handlers/top-level.t
S04-exceptions/control_across_runloop.t
S04-phasers/ascending-order.t
S04-phasers/check.t
S04-phasers/descending-order.t
S04-phasers/eval-in-begin.t
S04-phasers/first.t
S04-phasers/init.t
S04-phasers/multiple.t
S04-phasers/rvalue.t
S04-statement-modifiers/for.t
S04-statement-modifiers/given.t
S04-statement-modifiers/unless.t
S04-statement-modifiers/until.t
S04-statement-modifiers/values_in_bool_context.t
S04-statement-modifiers/while.t
S04-statement-modifiers/with.t
S04-statement-modifiers/without.t
S04-statement-parsing/hash.t
S04-statements/for-scope.t
S04-statements/for_with_only_one_item.t
S04-statements/given.t
S04-statements/label.t
S04-statements/last.t
S04-statements/map-and-sort-in-for.t
S04-statements/next.t
S04-statements/no-implicit-block.t
S04-statements/once.t
S04-statements/quietly.t
S04-statements/redo.t
S04-statements/terminator.t
S04-statements/try.t
S04-statements/until.t
S04-statements/when.t
S04-statements/while.t
S04-statements/with.t
S05-capture/subrule.t
S05-grammar/methods.t
S05-grammar/namespace.t
S05-grammar/parse_and_parsefile.t
S05-grammar/polymorphism.t
S05-grammar/protos.t
S05-grammar/signatures.t
S05-interpolation/lexicals.t
S05-mass/named-chars.t
S05-mass/properties-block.t
S05-mass/recursive.t
S05-mass/stdrules.t
S05-match/arrayhash.t
S05-match/make.t
S05-match/non-capturing.t
S05-match/perl.t
S05-match/positions.t
S05-metachars/newline.t
S05-metachars/tilde.t
S05-metasyntax/assertions.t
S05-metasyntax/changed.t
S05-metasyntax/delimiters.t
S05-metasyntax/lookaround.t
S05-metasyntax/null.t
S05-metasyntax/repeat.t
S05-metasyntax/single-quotes.t
S05-modifier/counted-match.t
S05-modifier/counted.t
S05-modifier/global.t
S05-modifier/overlapping.t
S05-modifier/perl5_0.t
S05-modifier/perl5_1.t
S05-modifier/perl5_2.t
S05-modifier/perl5_3.t
S05-modifier/perl5_4.t
S05-modifier/perl5_5.t
S05-modifier/perl5_6.t
S05-modifier/perl5_7.t
S05-modifier/perl5_8.t
S05-modifier/perl5_9.t
S05-modifier/sigspace.t
S05-substitution/67222.t
S05-transliteration/79778.t
S05-transliteration/with-closure.t
S06-advanced/recurse.t
S06-currying/positional.t
S06-currying/slurpy.t
S06-macros/errors.t
S06-macros/quasi-blocks.t
S06-macros/unquoting.t
S06-macros/opaque-ast.t
S06-multi/redispatch.t
S06-operator-overloading/imported-subs.t
S06-operator-overloading/semicolon.t
S06-operator-overloading/term.t
S06-other/anon-hashes-vs-blocks.t
S06-other/main-eval.t
S06-other/main.t
S06-other/main-semicolon.t
S06-other/pairs-as-lvalues.t
S06-routine-modifiers/native-lvalue-subroutines.t
S06-routine-modifiers/proxy.t
S06-signature/caller-param.t
S06-signature/closure-over-parameters.t
S06-signature/defaults.t
S06-signature/multidimensional.t
S06-signature/multi-invocant.t
S06-signature/named-renaming.t
S06-signature/positional.t
S06-signature/scalar-type.t
S06-signature/shape.t
S06-signature/sigilless.t
S06-signature/slurpy-and-interpolation.t
S06-signature/unpack-array.t
S06-signature/unpack-object.t
S06-signature/unspecified.t
S06-traits/as.t
S06-traits/is-readonly.t
S06-traits/is-rw.t
S06-traits/native-is-copy.t
S06-traits/native-is-rw.t
S07-slip/slip.t
S07-hyperrace/hyper.t
S07-hyperrace/race.t
S06-traits/slurpy-is-rw.t
S09-autovivification/autoincrement.t
S09-subscript/multidim-assignment.t
S09-multidim/XX-POS-on-dimensioned.t
S09-multidim/XX-POS-on-undimensioned.t
S09-multidim/assign.t
S09-multidim/decl.t
S09-multidim/methods.t
S09-multidim/subs.t
S09-typed-arrays/native-decl.t
S10-packages/joined-namespaces.t
S11-compunit/compunit-dependencyspecification.t
S11-compunit/compunit-repository.t
S11-modules/import-tag.t
S11-modules/lexical.t
S11-modules/need.t
S11-repository/curli-install.t
S11-repository/cur-candidates.t
S11-repository/cur-current-distribution.t
S12-attributes/clone.t
S12-attributes/defaults.t
S12-attributes/delegation.t
S12-attributes/inheritance.t
S12-attributes/undeclared.t
S12-class/attributes.t
S12-class/attributes-required.t
S12-class/basic.t
S12-class/declaration-order.t
S12-class/extending-arrays.t
S12-class/inheritance-class-methods.t
S12-class/inheritance.t
S12-class/lexical.t
S12-class/magical-vars.t
S12-class/mro.t
S12-class/namespaced.t
S12-class/open.t
S12-class/rw.t
S12-class/self-inheritance.t
S12-class/type-object.t
S12-coercion/coercion-types.t
S12-construction/construction.t
S12-enums/anonymous.t
S12-enums/pseudo-functional.t
S12-introspection/can.t
S12-introspection/meta-class.t
S12-introspection/parents.t
S12-introspection/roles.t
S12-introspection/WHAT.t
S12-meta/grammarhow.t
S12-methods/chaining.t
S12-methods/delegation.t
S12-methods/how.t
S12-methods/lvalue.t
S12-methods/qualified.t
S12-methods/topic.t
S12-methods/trusts.t
S12-methods/typed-attributes.t
S12-methods/what.t
S13-type-casting/methods.t
S14-roles/anonymous.t
S14-roles/attributes.t
S14-roles/bool.t
S14-roles/composition.t
S14-roles/conflicts.t
S14-roles/crony.t
S14-roles/instantiation.t
S14-roles/lexical.t
S14-roles/mixin.t
S14-roles/namespaced.t
S14-roles/parameterized-basic.t
S14-roles/stubs.t
S14-roles/submethods.t
S14-traits/attributes.t
S15-nfg/case-change.t           # moar
S15-nfg/cgj.t                   # moar
S15-nfg/concatenation.t         # moar
S15-nfg/crlf-encoding.t         # moar
S15-nfg/from-buf.t              # moar
S15-nfg/grapheme-break.t        # moar
S15-nfg/long-uni.t              # moar
S15-nfg/mass-chars.t            # moar
S15-nfg/many-combiners.t        # moar
S15-nfg/many-threads.t          # moar
S15-nfg/mass-equality.t         # moar
S15-nfg/mass-roundtrip-nfc.t    # moar
S15-nfg/mass-roundtrip-nfd.t    # moar
S15-nfg/mass-roundtrip-nfkc.t   # moar
S15-nfg/mass-roundtrip-nfkd.t   # moar
S15-nfg/regex.t                 # moar
S15-normalization/nfc-0.t       # moar stress
S15-normalization/nfc-1.t       # moar stress
S15-normalization/nfc-2.t       # moar stress
S15-normalization/nfc-3.t       # moar stress
S15-normalization/nfc-4.t       # moar stress
S15-normalization/nfc-5.t       # moar stress
S15-normalization/nfc-6.t       # moar stress
S15-normalization/nfc-7.t       # moar stress
S15-normalization/nfc-8.t       # moar stress
S15-normalization/nfc-9.t       # moar stress
S15-normalization/nfc-sanity.t  # moar
S15-normalization/nfd-0.t       # moar stress
S15-normalization/nfd-1.t       # moar stress
S15-normalization/nfd-2.t       # moar stress
S15-normalization/nfd-3.t       # moar stress
S15-normalization/nfd-4.t       # moar stress
S15-normalization/nfd-5.t       # moar stress
S15-normalization/nfd-6.t       # moar stress
S15-normalization/nfd-7.t       # moar stress
S15-normalization/nfd-8.t       # moar stress
S15-normalization/nfd-9.t       # moar stress
S15-normalization/nfd-sanity.t  # moar
S15-normalization/nfkc-0.t      # moar stress
S15-normalization/nfkc-1.t      # moar stress
S15-normalization/nfkc-2.t      # moar stress
S15-normalization/nfkc-3.t      # moar stress
S15-normalization/nfkc-4.t      # moar stress
S15-normalization/nfkc-5.t      # moar stress
S15-normalization/nfkc-6.t      # moar stress
S15-normalization/nfkc-7.t      # moar stress
S15-normalization/nfkc-8.t      # moar stress
S15-normalization/nfkc-9.t      # moar stress
S15-normalization/nfkc-sanity.t # moar
S15-normalization/nfkd-0.t      # moar stress
S15-normalization/nfkd-1.t      # moar stress
S15-normalization/nfkd-2.t      # moar stress
S15-normalization/nfkd-3.t      # moar stress
S15-normalization/nfkd-4.t      # moar stress
S15-normalization/nfkd-5.t      # moar stress
S15-normalization/nfkd-6.t      # moar stress
S15-normalization/nfkd-7.t      # moar stress
S15-normalization/nfkd-8.t      # moar stress
S15-normalization/nfkd-9.t      # moar stress
S15-normalization/nfkd-sanity.t # moar
S15-string-types/Uni.t          # moar
S16-filehandles/argfiles.t
S16-filehandles/io_in_while_loops.t
S16-filehandles/mkdir_rmdir.t
S16-filehandles/open.t
S16-filehandles/unlink.t
S16-io/bare-say.t
S16-io/cwd.t
S16-io/getc.t
S16-io/lines.t
S16-io/newline.t
S16-io/note.t
S16-io/say-and-ref.t
S16-io/say.t
S16-io/split.t
S16-io/tmpdir.t
S16-io/words.t
S17-channel/basic.t
S17-lowlevel/lock.t      # slow
S17-lowlevel/thread-start-join-stress.t # stress
S17-procasync/kill.t     # moar stress slow
S17-procasync/no-runaway-file-limit.t # moar slow
S17-procasync/many-processes-no-close-stdin.t # moar slow
S17-promise/allof.t      # slow
S17-promise/at.t
S17-promise/anyof.t
S17-promise/in.t         # slow
S17-promise/stress.t     # stress
S17-promise/then.t
S17-scheduler/at.t       # slow
S17-scheduler/in.t       # slow
S17-scheduler/times.t    # slow
S17-supply/act.t         # slow
S17-supply/basic.t
S17-supply/batch.t       # slow
S17-supply/categorize.t
S17-supply/Channel.t
S17-supply/classify.t
S17-supply/do.t
S17-supply/elems.t       # slow
S17-supply/flat.t
S17-supply/from-list.t
S17-supply/grab.t
S17-supply/grep.t
S17-supply/head.t
S17-supply/interval.t
S17-supply/list.t
S17-supply/map.t
S17-supply/max.t
S17-supply/merge.t
S17-supply/migrate.t
S17-supply/min.t
S17-supply/minmax.t
S17-supply/on-demand.t
S17-supply/Promise.t
S17-supply/produce.t
S17-supply/reduce.t
S17-supply/reverse.t
S17-supply/schedule-on.t
S17-supply/sort.t
S17-supply/squish.t
S17-supply/start.t        # slow
S17-supply/tail.t
S17-supply/unique.t       # slow
S17-supply/words.t
S19-command-line/arguments.t
S19-command-line/dash-e.t
S19-command-line/help.t
S19-command-line/repl.t    # moar
S19-command-line-options/03-dash-p.t
S24-testing/0-compile.t
S24-testing/3-output.t
S26-documentation/01-delimited.t
S26-documentation/03-abbreviated.t
S26-documentation/05-comment.t
S26-documentation/06-lists.t
S26-documentation/07-tables.t
S26-documentation/10-doc-cli.t
S26-documentation/module-comment.t
S26-documentation/wacky.t
S28-named-variables/slangs.t    # moar
S29-any/are.t
S29-any/cmp.t
S29-any/isa.t
S29-context/die.t
S29-context/evalfile.t
S29-context/exit-in-if.t
S29-context/exit.t
S29-context/sleep.t  # slow
S29-conversions/hash.t
S32-array/adverbs.t
S32-array/bool.t
S32-array/create.t
S32-array/delete.t
S32-array/delete-adverb.t
S32-array/delete-adverb-native.t
S32-array/elems.t
S32-array/end.t
S32-array/kv.t
S32-array/pairs.t
S32-array/perl.t
S32-array/push.t
S32-array/shift.t
S32-array/unshift.t
S32-basics/warn.t
S32-basics/xxPOS-native.t    # moar
S32-container/roundrobin.t
S32-hash/antipairs.t
S32-hash/delete.t
S32-hash/delete-adverb.t
S32-hash/exists-adverb.t
S32-hash/invert.t
S32-hash/pairs.t
S32-hash/push.t
S32-io/IO-Socket-Async-UDP.t    # moar
S32-io/chdir.t
S32-io/copy.t
S32-io/file-tests.t
S32-io/io-spec-unix.t
S32-io/io-spec-win.t
S32-io/io-spec-cygwin.t
S32-io/move.t
S32-io/native-descriptor.t  # moar
S32-io/note.t
S32-io/other.t
S32-io/rename.t
S32-io/socket-recv-vs-read.t
S32-list/categorize.t
S32-list/create.t
S32-list/combinations.t
S32-list/grep-kv.t
S32-list/grep-p.t
S32-list/grep-v.t
S32-list/head.t
S32-list/join.t
S32-list/map_function_return_values.t
S32-list/permutations.t
S32-list/pick.t
S32-list/reverse.t
S32-list/seq.t
S32-list/tail.t
S32-list/squish.t
S32-num/abs.t
S32-num/complex.t
S32-num/exp.t
S32-num/fatrat.t
S32-num/is-prime.t
S32-num/narrow.t
S32-num/pi.t
S32-num/polar.t
S32-num/polymod.t
S32-num/rat.t
S32-num/real-bridge.t
S32-num/roots.t
S32-num/rounders.t
S32-num/rshift_pos_amount.t
S32-num/unpolar.t
S32-scalar/defined.t
S32-str/append.t
S32-str/bool.t
S32-str/chop.t
S32-str/contains.t
S32-str/ends-with.t
S32-str/fc.t            # moar
S32-str/index.t
S32-str/indices.t
S32-str/lc.t
S32-str/lines.t
S32-str/pack.t
S32-str/pos.t
S32-str/rindex.t
S32-str/samecase.t
S32-str/sprintf-b.t
S32-str/starts-with.t
S32-str/substr-eq.t
S32-str/substr-rw.t
S32-str/trim.t
S32-str/unpack.t
S32-temporal/DateTime.t   # slow
S32-trig/e.t
S32-trig/pi.t
S32-trig/simple.t
integration/99problems-01-to-10.t
integration/99problems-11-to-20.t
integration/advent2009-day01.t
integration/advent2009-day02.t
integration/advent2009-day03.t
integration/advent2009-day04.t
integration/advent2009-day05.t
integration/advent2009-day06.t
integration/advent2009-day07.t
integration/advent2009-day10.t
integration/advent2009-day11.t
integration/advent2009-day12.t
integration/advent2009-day13.t
integration/advent2009-day14.t
integration/advent2009-day15.t
integration/advent2009-day17.t
integration/advent2009-day18.t
integration/advent2009-day19.t
integration/advent2009-day21.t
integration/advent2009-day22.t
integration/advent2009-day23.t
integration/advent2009-day24.t
integration/advent2010-day03.t
integration/advent2010-day04.t
integration/advent2010-day06.t
integration/advent2010-day07.t
integration/advent2010-day08.t
integration/advent2010-day12.t
integration/advent2010-day14.t
integration/advent2010-day16.t
integration/advent2010-day19.t
integration/advent2010-day21.t
integration/advent2010-day22.t
integration/advent2010-day23.t
integration/advent2011-day03.t
integration/advent2011-day05.t
integration/advent2011-day07.t
integration/advent2011-day10.t
integration/advent2011-day11.t
integration/advent2011-day14.t
integration/advent2011-day15.t
integration/advent2011-day16.t
integration/advent2011-day20.t
integration/advent2011-day22.t
integration/advent2011-day23.t
integration/advent2011-day24.t
integration/advent2012-day02.t
integration/advent2012-day03.t
integration/advent2012-day06.t
integration/advent2012-day10.t
integration/advent2012-day12.t
integration/advent2012-day13.t
integration/advent2012-day14.t
integration/advent2012-day15.t
integration/advent2012-day16.t
integration/advent2012-day19.t # slow
integration/advent2012-day20.t
integration/advent2012-day22.t
integration/advent2012-day23.t
integration/advent2012-day24.t
integration/advent2013-day02.t
integration/advent2013-day04.t
integration/advent2013-day06.t
integration/advent2013-day07.t
integration/advent2013-day08.t
integration/advent2013-day09.t
integration/advent2013-day12.t
integration/advent2013-day15.t
integration/advent2013-day19.t
integration/advent2013-day20.t
integration/advent2013-day21.t
integration/advent2013-day22.t
integration/advent2013-day23.t
integration/advent2014-day13.t
integration/advent2014-day16.t
integration/lazy-bentley-generator.t
integration/lexical-array-in-inner-block.t
integration/lexicals-and-attributes.t
integration/man-or-boy.t
integration/method-calls-and-instantiation.t
integration/no-indirect-new.t
integration/packages.t
integration/pair-in-array.t
integration/passing-pair-class-to-sub.t
integration/precompiled.t      # moar slow
integration/real-strings.t
integration/rule-in-class-Str.t
integration/say-crash.t
integration/substr-after-match-in-gather-in-for.t
integration/topic_in_double_loop.t
integration/variables-in-do.t
rosettacode/greatest_element_of_a_list.t
rosettacode/sierpinski_triangle.t
