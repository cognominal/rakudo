use Test;

plan 2;

# ---------------------------------------------------------------------------
# Gating test: a .raku file must NOT interpret `>` as redirection.
# Running this with `raku` uses traditional Raku semantics, so:
#   say foo >output_raku.txt
# should NOT create a file — `foo` is a bare function call (which fails),
# and `>` is a comparison operator, not a redirection.
# ---------------------------------------------------------------------------

# 1. `say foo >output_raku.txt` should NOT create a file in .raku mode
#    (in standard Raku, `foo` is a bareword function call that dies)
{
    try {
        say foo >output_raku.txt;
    }
    # Either it throws (foo is undeclared) or it doesn't redirect.
    # Either way, no output_raku.txt should exist.
    nok 'output_raku.txt'.IO.e,
        '1: .raku file does not interpret > as output redirection (naked string)';
    'output_raku.txt'.IO.unlink if 'output_raku.txt'.IO.e;
}

# 2. Even with quotes, `> 'output_raku2.txt'` has a space, so it's a comparison
{
    my $result = 'hello' > 'output_raku2.txt';
    nok 'output_raku2.txt'.IO.e,
        '2: .raku file: quoted "> filename" with space is comparison, not redirection';
    'output_raku2.txt'.IO.unlink if 'output_raku2.txt'.IO.e;
}

done-testing;