# REPL-INSPECTOR.rakumod — Data structure inspector (YAML preview)

class REPL::DataInspector {
    has Int $.max-depth = 3;
    has Int $.max-items = 50;

    method preview(Mu $subject, Int :$max-depth = $!max-depth,
                   Int :$max-items = $!max-items --> Str) {
        self!render($subject, 0, :$max-depth, :$max-items)
    }

    method show(Mu $subject, |c) { print self.preview($subject, |c); }

    method !render(Mu $value, Int $depth,
                   Int :$max-depth = $!max-depth,
                   Int :$max-items = $!max-items) returns Str {
        return '<max-depth>' if $depth >= $max-depth;

        # Use role checks first (accurate for standard types like Hash, Array).
        # Fall back to .^can for types like Match that implement the
        # interface without doing the role.
        my $is-assoc = $value ~~ Associative
          || !($value ~~ Numeric)
             && $value.^can('AT-KEY') && $value.^can('keys');
        my $is-pos   = $value ~~ Positional
          || !($value ~~ Associative)
             && !($value ~~ Numeric)
             && $value.^can('AT-POS') && $value.^can('elems');
        # Array has AT-KEY (coerces to int), demote assoc for strict Positionals
        if $is-assoc && $is-pos && $value ~~ Positional {
            $is-assoc = False;
        }

        if $is-assoc && $is-pos {
            return self!render-mixed($value, $depth, :$max-depth, :$max-items);
        }
        if $is-assoc {
            return self!render-associative($value, $depth, :$max-depth, :$max-items);
        }
        if $is-pos {
            return self!render-positional($value, $depth, :$max-depth, :$max-items);
        }
        self!render-scalar($value);
    }

    method !render-scalar(Mu $value --> Str) {
        given $value {
            when Str   { return .chars > 80 ?? self!q(.substr(0,80)) !! $_; }
            when Int | Num | Rat { return ~$_; }
            when Bool  { return .so ?? 'true' !! 'false'; }
            when Nil | Mu | Any { return 'null'; }
            default    { return self!q(.Str); }
        }
    }

    method !q(Str $s --> Str) { return '"' ~ $s ~ '"'; }

    method !render-associative(Mu $value, Int $depth,
                   Int :$max-depth = $!max-depth,
                   Int :$max-items = $!max-items) returns Str {
        my @keys = $value.keys.List.sort;
        my $n = min(+@keys, $max-items);
        my $indent = '  ' x $depth;
        my @lines;
        for @keys[^$n] -> $k {
            my $v = self!render($value{$k}, $depth + 1, :$max-depth, :$max-items);
            @lines.push: $indent ~ $k ~ ': ' ~ $v;
        }
        @lines.push: $indent ~ '... and ' ~ (+@keys - $n) ~ ' more'
            if +@keys > $max-items;
        @lines.join("\n")
    }

    method !render-positional(Mu $value, Int $depth,
                   Int :$max-depth = $!max-depth,
                   Int :$max-items = $!max-items) returns Str {
        my $total = $value.elems;
        my $n = min($total, $max-items);
        my $indent = '  ' x $depth;
        my @lines;
        for ^$n -> $i {
            my $v = self!render($value[$i], $depth + 1, :$max-depth, :$max-items);
            @lines.push: $indent ~ '- ' ~ $v;
        }
        @lines.push: $indent ~ '- ... and ' ~ ($total - $n) ~ ' more'
            if $total > $max-items;
        @lines.join("\n")
    }

    method !render-mixed(Mu $value, Int $depth,
                   Int :$max-depth = $!max-depth,
                   Int :$max-items = $!max-items) returns Str {
        my $indent = '  ' x $depth;
        my @lines;

        my $total = $value.elems;
        my $n = min($total, $max-items);
        @lines.push: $indent ~ 'indices:';
        for ^$n -> $i {
            my $v = self!render($value[$i], $depth + 1, :$max-depth, :$max-items);
            @lines.push: $indent ~ '  - ' ~ $v;
        }
        @lines.push: $indent ~ '  - ... and ' ~ ($total - $n) ~ ' more'
            if $total > $max-items;

        my @keys = $value.keys.List.sort;
        for @keys[^min(+@keys, $max-items)] -> $k {
            my $v = self!render($value{$k}, $depth + 1, :$max-depth, :$max-items);
            @lines.push: $indent ~ $k ~ ': ' ~ $v;
        }
        @lines.join("\n")
    }
}

sub inspect(Mu $value, |c) {
    REPL::DataInspector.new.show($value, |c);
}