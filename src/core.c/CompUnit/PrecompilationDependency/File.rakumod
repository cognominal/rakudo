class CompUnit::PrecompilationDependency::File
  does CompUnit::PrecompilationDependency
{
    has CompUnit::PrecompilationId        $.id   is built(:bind);
    has CompUnit::DependencySpecification $.spec is built(:bind);
    has Str $.src             is built(:bind);
    has Str $.checksum        is rw;
    has Str $!serialized-spec is built(:bind);

    method source-name() {
        "$.src ($.spec.short-name())"
    }

    method deserialize(str $str) {
        my $parts := nqp::split("\0",$str);
        self.new(
          :id(CompUnit::PrecompilationId.new-without-check(nqp::atpos($parts,0))),
          :src(nqp::atpos($parts,1)),
          :checksum(nqp::atpos($parts,2))
          :serialized-spec(nqp::atpos($parts,3))
        )
    }

    method spec(--> CompUnit::DependencySpecification:D) {
        $!spec //= $!serialized-spec
            ?? do {
                use MONKEY-SEE-NO-EVAL;
                EVAL $!serialized-spec;
            }
            !! Nil;
    }

    method serialize(--> Str:D) {
        "$!id\0$!src\0$!checksum\0{
            $!serialized-spec ?? $!serialized-spec !! $!spec.raku
        }"
    }

    method Str() {
        "$.id $.src $.checksum {$!serialized-spec ?? $!serialized-spec !! $!spec.raku}"
    }
}

# vim: expandtab shiftwidth=4
