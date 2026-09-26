# REPL-COMPLETIONS.rakumod — Completion engine with site resolution
#
# Replaces the simple `Completions` role's flat-identifier approach with a
# site-aware engine that understands what kind of thing the cursor is on
# (identifier, sigiled variable, dot-subscript, method call, etc.) and
# dispatches to the appropriate completer.
#
# Architecture (mirrors nushell's CompletionEngine, simplified):
#   1. parse-at-cursor(Str $line, int $cursor) --> CompletionSite
#      Walks backwards from cursor to identify the site kind.
#   2. Each site kind has a dedicated completer method.
#   3. completions-for-line uses the site to dispatch.

class REPL::Completions::Engine {
    # Site kinds
    constant SITE-IDENTIFIER    = 'identifier';
    constant SITE-SIGILED       = 'sigiled';
    constant SITE-TWIGILED      = 'twigiled';
    constant SITE-DOT-SUBSCRIPT = 'dot-subscript';
    constant SITE-DOT-METHOD    = 'dot-method';
    constant SITE-IMPORT        = 'import';
    constant SITE-TYPE          = 'type';
    constant SITE-COMMENT       = 'comment';
    constant SITE-EOF           = 'eof';
    constant SITE-UNKNOWN       = 'unknown';

    class CompletionSite {
        has Str  $.kind       is required;
        has Str  $.prefix     = '';
        has Str  $.subject    = '';
        has Str  $.sigil      = '';
        has Str  $.twigil     = '';
        has Str  $.whole-line = '';
        has Int  $.cursor     = 0;
        has      $.metadata;

        method is-subscript-anchor(--> Bool) {
            $!kind eq SITE-DOT-SUBSCRIPT || $!kind eq SITE-DOT-METHOD
        }
    }

    # Main entry: walk backwards from cursor to classify the site.
    method parse-at-cursor(Str $line, Int $cursor-index --> CompletionSite) {
        my $cursor = $cursor-index < 0 ?? 0 !! $cursor-index;
        $cursor = $cursor > $line.chars ?? $line.chars !! $cursor;
        my $before = $line.substr(0, $cursor);

        if $before ~~ /^ \h* $/ {
            return CompletionSite.new(
                kind => SITE-EOF, whole-line => $line, cursor => $cursor, prefix => '',
            );
        }

        # 1. Sigiled/twigiled variable — must come before comment and dot checks.
        if self.is-sigiled-at-cursor($before) -> $h {
            my $kind = $h<twigil> ?? SITE-TWIGILED !! SITE-SIGILED;
            return CompletionSite.new(
                kind => $kind, prefix => $h<partial>, sigil => $h<sigil>,
                twigil => $h<twigil> // '', whole-line => $line, cursor => $cursor,
            );
        }

        # 2. Comment — # followed by space/non-identifier.
        if self.is-comment-at-cursor($before) {
            return CompletionSite.new(
                kind => SITE-COMMENT, whole-line => $line, cursor => $cursor, prefix => '',
            );
        }

        # 3. Dot-subscript / dot-method.
        if self.is-dot-at-cursor($before) -> $h {
            my $dc = self.classify-dot-site($h);
            return CompletionSite.new(
                kind => $dc<kind>, prefix => $dc<prefix>,
                subject => $dc<subject>, whole-line => $line,
                cursor => $cursor, metadata => $dc,
            );
        }

        # 4. Import keyword
        my $m = self.is-import-at-cursor($before);
        if $m && $m<keyword>.chars {
            return CompletionSite.new(
                kind => SITE-IMPORT, prefix => ~$m<partial>,
                subject => ~$m<keyword>, whole-line => $line, cursor => $cursor,
            );
        }

        # 5. Type keyword
        $m = self.is-type-at-cursor($before);
        if $m && $m<keyword>.chars {
            return CompletionSite.new(
                kind => SITE-TYPE, prefix => ~$m<partial>,
                subject => ~$m<keyword>, whole-line => $line, cursor => $cursor,
            );
        }

        # 6. Bare identifier
        $m = self.is-identifier-at-cursor($before);
        if $m {
            return CompletionSite.new(
                kind => SITE-IDENTIFIER, prefix => ~$m<partial>,
                whole-line => $line, cursor => $cursor,
            );
        }

        # 7. Fallback
        return CompletionSite.new(
            kind => SITE-UNKNOWN, whole-line => $line, cursor => $cursor, prefix => '',
        );
    }

    # Scan backwards for '#', return True only if it's a comment (not sigil).
    # Rule: # followed by identifier-start char => sigil, not comment.
    method is-comment-at-cursor(Str $before --> Bool) {
        my $pos = $before.chars;
        my $in-string = 0;
        while $pos-- > 0 {
            my $ch = $before.substr($pos, 1);
            if $ch eq '"' || $ch eq "'" { $in-string = $in-string ?? 0 !! 1; }
            elsif $ch eq '#' && !$in-string {
                my $next = $pos + 1 < $before.chars
                    ?? $before.substr($pos + 1, 1) !! '';
                # If followed by an identifier-start char, this is a # sigil, not a comment
                return False if $next.chars && $next ~~ /<[a..zA..Z_]>/;
                # If preceded by '.', this is a dot-subscript suffix (#expr), not a comment
                my $prev = $pos > 1 ?? $before.substr($pos - 1, 1) !! '';
                return False if $prev eq '.';
                return True;
            }
        }
        False;
    }

    # Scan backwards for '.' that starts a subscript/method selector.
    method is-dot-at-cursor(Str $before) {
        my $pos = $before.chars - 1;
        my $in-string = False;
        while $pos >= 0 {
            my $ch = $before.substr($pos, 1);
            if $ch eq '"' || $ch eq "'" { $in-string = !$in-string; }
            elsif $ch eq '.' && !$in-string {
                my $prev = $pos > 0 ?? $before.substr($pos - 1, 1) !! '';
                my $next = $pos < $before.chars - 1 ?? $before.substr($pos + 1, 1) !! '';
                next if $prev eq '.' || $prev eq ':';
                if $prev ne '' && $prev !~~ /<[a..zA..Z_\]\)\}]>/ {
                    next if $prev ~~ /\d/ && $next ~~ /\d/;
                }
                return %( subject => $before.substr(0, $pos).trim-trailing,
                          after-dot => $before.substr($pos + 1), dot-pos => $pos );
            }
            $pos--;
        }
        Nil;
    }

    # Classify what's after the dot.
    method classify-dot-site(Hash $dm --> Hash) {
        my $ad = $dm<after-dot>;
        if $ad ~~ /^ (<[~#]>) (\w*?) $/ {
            return %( kind => SITE-DOT-SUBSCRIPT, prefix => ~$1,
                      subject => $dm<subject>, sigil => ~$0, sigil-kind => ~$0 );
        }
        if $ad ~~ /^ (\d+) $/ {
            return %( kind => SITE-DOT-SUBSCRIPT, prefix => ~$0,
                      subject => $dm<subject>, sigil => '', sigil-kind => 'int' );
        }
        if $ad ~~ /^ (\w*?) $/ {
            return %( kind => SITE-DOT-METHOD, prefix => ~$0,
                      subject => $dm<subject>, sigil => '', mode => 'raku' );
        }
        return %( kind => SITE-DOT-METHOD, prefix => $ad,
                  subject => $dm<subject>, sigil => '' );
    }

    # Scan backwards for sigil + optional twigil + partial name.
    method is-sigiled-at-cursor(Str $before) {
        my $pos = $before.chars;
        my $partial = '';
        my $twigil = '';
        my $sigil = '';

        while $pos > 0 {
            my $ch = $before.substr($pos - 1, 1);
            if $ch ~~ /<[a..zA..Z_0..9]>/ {
                $partial = $ch ~ $partial;
                $pos--;
            }
            elsif $ch ~~ /<[.?!*<=\^:]>/ && !$sigil {
                # Potential twigil char. But only if preceded by a sigil
                # (not by a letter, which would mean it's a postfix dot).
                my $before-ch = $pos > 1 ?? $before.substr($pos - 2, 1) !! '';
                if $before-ch !~~ /<[\$@%&~#]>/ {
                    # Not preceded by sigil — this is a postfix dot, not a twigil
                    last;
                }
                $twigil = $ch;
                $pos--;
            }
            elsif $ch ~~ /<[$@%&~#]>/ {
                $sigil = $ch;
                $pos--;
                if $pos > 0 && $before.substr($pos - 1, 1) eq '.' {
                    return Nil;
                }
                return %( sigil => $sigil, twigil => $twigil, partial => $partial );
            }
            else { last; }
        }
        Nil;
    }

    method is-import-at-cursor(Str $before) {
        my $m = $before ~~ /
            ^ .*?
            $<keyword> = [use|need|import|require]  \h+
            $<partial> = \w*  $
        /;
        $m || Nil;
    }

    method is-type-at-cursor(Str $before) {
        my $m = $before ~~ /
            ^ .*?
            $<keyword> = [my|has|our|state]  \h+
            <![$@%&~#]>
            $<partial> = \w*  $
        /;
        $m || Nil;
    }

    method is-identifier-at-cursor(Str $before) {
        my $m = $before ~~ / $<partial> = \w*  $ /;
        $m || Nil;
    }
}

# Advanced completions role — site-aware dispatch.
role REPL::Completions::Advanced {
    has @!completions = CORE::.keys.flatmap({
        /^ "&"? $<word>=[\w* <.lower> \w*] $/ ?? ~$<word> !! []
    }).sort;

    has REPL::Completions::Engine $!engine = REPL::Completions::Engine.new;

    method sorted-set-insert(@values, $value) {
        my $low = 0;
        my $high = @values.end;
        my $insert_pos = 0;
        while $low <= $high {
            my $middle = floor($low + ($high - $low) / 2);
            my $mid = @values[$middle];
            if $middle == @values.end {
                if $value eq $mid { return; }
                elsif $value lt $mid { $high = $middle - 1; }
                else { $insert_pos = +@values; last; }
            } else {
                my $m1 = @values[$middle + 1];
                if $value eq $mid || $value eq $m1 { return; }
                elsif $value lt $mid { $high = $middle - 1; }
                elsif $value gt $m1 { $low = $middle + 1; }
                else { $insert_pos = $middle + 1; last; }
            }
        }
        splice(@values, $insert_pos, 0, $value);
    }

    method update-completions(--> Nil) {
        my $context := self.compiler.context;
        return unless $context;
        my $pad := nqp::ctxlexpad($context);
        my $it := nqp::iterator($pad);
        while $it {
            my $k := nqp::iterkey_s(nqp::shift($it));
            my $m = $k ~~ /^ "&"? $<word>=[\w* <.lower> \w*] $/;
            unless $m { next; }
            self.sorted-set-insert(@!completions, ~$m<word>);
        }
        my $PACKAGE = self.compiler.eval('$?PACKAGE', :outer_ctx($context));
        for $PACKAGE.WHO.keys -> $k {
            self.sorted-set-insert(@!completions, $k);
        }
    }

    method completions-for-line(Str $line, int $cursor-index) {
        my $site = $!engine.parse-at-cursor($line, $cursor-index);
        my $prefix = $site.prefix;

        given $site.kind {
            when REPL::Completions::Engine::SITE-IDENTIFIER {
                return self.complete-identifier($prefix);
            }
            when REPL::Completions::Engine::SITE-SIGILED {
                return self.complete-sigiled($site.sigil, $prefix);
            }
            when REPL::Completions::Engine::SITE-TWIGILED {
                return self.complete-twigiled($site.sigil, $site.twigil, $prefix);
            }
            when REPL::Completions::Engine::SITE-DOT-SUBSCRIPT {
                return self.complete-dot-subscript($site.subject, $site.prefix, $site.metadata);
            }
            when REPL::Completions::Engine::SITE-DOT-METHOD {
                return self.complete-dot-method($site.subject, $site.prefix);
            }
            when REPL::Completions::Engine::SITE-IMPORT {
                return self.complete-import($prefix);
            }
            when REPL::Completions::Engine::SITE-TYPE {
                return self.complete-type($prefix);
            }
            when REPL::Completions::Engine::SITE-COMMENT { return []; }
            when REPL::Completions::Engine::SITE-EOF { return @!completions; }
            default { return self.complete-identifier($prefix); }
        }
    }

    method complete-identifier(Str $prefix) {
        return @!completions unless $prefix;
        gather for @!completions -> $word {
            take $word if $word.starts-with($prefix);
        }
    }

    method complete-sigiled(Str $sigil, Str $partial) {
        gather for @!completions -> $word {
            take $sigil ~ $word if $word.starts-with($partial);
        }
    }

    method complete-twigiled(Str $sigil, Str $twigil, Str $partial) {
        gather for @!completions -> $word {
            take $sigil ~ $twigil ~ $word if $word.starts-with($partial);
        }
    }

    method complete-dot-subscript(Str $subject-expr, Str $prefix, $metadata) {
        my $sigil-kind = $metadata<sigil-kind> // '';
        my $subject = self.try-eval-subject($subject-expr);
        return self.complete-identifier($prefix) unless $subject.defined;

        my $is-pos   = $subject.^can('AT-POS') && $subject.^can('elems');
        my $is-assoc = $subject.^can('AT-KEY') && $subject.^can('keys');
        my $elems = $is-pos ?? $subject.elems !! 0;

        # Sigil-hinted completions as extras
        if $is-pos   { gather for ^$elems -> $i { take '#' ~ $i; } }
        if $is-assoc { gather for $subject.keys -> $k { take '~' ~ $k; } }

        if ($sigil-kind eq '~') && $is-assoc {
            gather for $subject.keys -> $k { take $k if $k.starts-with($prefix); }
        }
        elsif ($sigil-kind eq '#' || $sigil-kind eq 'int') && $is-pos {
            gather for ^$elems -> $i { take $i if $i.Str.starts-with($prefix); }
        }
        else {
            if $is-assoc {
                gather for $subject.keys -> $k { take $k if $k.starts-with($prefix); }
            }
            if $is-pos {
                gather for ^$elems -> $i { take $i if $i.Str.starts-with($prefix); }
            }
        }
    }

    method complete-dot-method(Str $subject-expr, Str $prefix) {
        my $subject = self.try-eval-subject($subject-expr);
        return self.complete-identifier($prefix) unless $subject.defined;
        my @methods;
        try { @methods = $subject.^methods.map(*.name).grep(*.defined); }
        if @methods {
            gather for @methods -> $m { take $m if $m.starts-with($prefix); }
        } else { self.complete-identifier($prefix); }
    }

    method complete-import(Str $prefix) { self.complete-identifier($prefix); }

    method complete-type(Str $prefix) {
        my @types = <Any Array Associative Bool Callable Channel Complex
            DateTime Date Duration Failure Hash IO Int List Map Match Mu
            Nil Numeric Pair Positional Promise Range Rat Rational Real
            Regex Seq Set Str Stringy Sub Supply Type UInt Whatever>;
        gather for @types -> $t { take $t if $t.starts-with($prefix); }
    }

    method try-eval-subject(Str $expr) {
        try {
            my $p = Promise.start({
                self.compiler.eval($expr, :outer_ctx(self.save-ctx()));
            });
            my $t = Promise.in(0.5);
            await Promise.anyof($p, $t);
            return $p.result if $p.status ~~ Kept;
            Mu;
        }
        CATCH { default { Mu } }
    }
}
