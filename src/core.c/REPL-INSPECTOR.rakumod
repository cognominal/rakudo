# REPL-INSPECTOR.rakumod — Data structure inspector (YAML preview)

class REPL::DataInspector {
    has Int $.max-depth = 3;
    has Int $.max-items = 50;
    has Int $.max-width = 2000;

    method preview(Mu $subject, Int :$max-depth = $!max-depth,
                   Int :$max-items = $!max-items,
                   Int :$max-width = $!max-width --> Str) {
        self!render($subject, 0)
    }

    method !render(Mu $value, Int $depth) returns Str {
        return "<max-depth>" if $depth >= $!max-depth;
        self!render-scalar($value);
    }

    method !render-scalar(Mu $value --> Str) {
        given $value {
            when Str { return ~$_; }
            when Int | Num | Rat { return ~$_; }
            when Bool { return .so ?? 'true' !! 'false'; }
            default { return ~$_.Str; }
        }
    }

    method show(Mu $subject, |c) {
        print self.preview($subject, |c);
    }
}

sub inspect(Mu $value, |c) {
    REPL::DataInspector.new.show($value, |c);
}