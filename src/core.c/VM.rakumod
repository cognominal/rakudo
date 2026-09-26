class VM does Systemic {
#COMPILER::if moar
    has $.config         is built(:bind) = nqp::backendconfig;
    has $.prefix         is built(:bind) = $!config<prefix>;
    has $.precomp-ext    is built(:bind) = "moarvm";
    has $.precomp-target is built(:bind) = "mbc";
#COMPILER::endif
    submethod TWEAK(--> Nil) {
#COMPILER::if moar
        # https://github.com/rakudo/rakudo/issues/3436
        nqp::bind($!name,'moar');
        nqp::bind($!desc,'Short for "Metamodel On A Runtime", MoarVM is a modern virtual machine built for the Rakudo compiler and the NQP Compiler Toolchain.');
        nqp::bind($!auth,'The MoarVM Team');
        nqp::bind($!version,Version.new($!config<version> // "unknown"));
#COMPILER::endif
# add new backends here please
    }


    method platform-library-name(IO::Path $library, Version :$version) {
        my int $is-win = Rakudo::Internals.IS-WIN;
        my int $is-darwin = self.osname eq 'darwin';

        my $basename  = $library.basename;
        my int $full-path = $library ne $basename;
        my $dirname   = $library.dirname;

        # OS X needs version before extension
        $basename ~= ".$version" if $is-darwin && $version.defined;

#COMPILER::if moar
        my $dll = self.config<dll>;
        my $platform-name = sprintf($dll, $basename);
#COMPILER::endif
#COMPILER::if !moar
        my $prefix = $is-win ?? '' !! 'lib';
        my $platform-name = "$prefix$basename" ~ ".{self.config<nativecall.so>}";
#COMPILER::endif
        $platform-name ~= '.' ~ $version
            if $version.defined and nqp::iseq_i(nqp::add_i($is-darwin,$is-win),0);

        $full-path
          ?? $dirname.IO.add($platform-name).absolute
          !! $platform-name.IO
    }

    method own-up() {
#COMPILER::if moar
        nqp::syscall("all-thread-bt",1);
#COMPILER::endif
#COMPILER::if !moar
        # Attempy to mimic the MoarVM functionality for now
        CATCH { .note; exit 2 }
        die;
#COMPILER::endif
    }

    proto method osname(|) {*}
    multi method osname(VM:U:) {
        nqp::lc(nqp::atkey(nqp::backendconfig,'osname'))
    }
    multi method osname(VM:D:) {
        nqp::lc($!config<osname>)
    }

    method remote-debugging() {
#COMPILER::if moar
        nqp::syscall("is-debugserver-running")
#COMPILER::endif
#COMPILER::if !moar
        0
#COMPILER::endif
    }

    method request-garbage-collection(--> Nil) {
#COMPILER::if moar
        nqp::force_gc
#COMPILER::endif
#COMPILER::if !moar
        warn "Requesting garbage collection not supported on this backend";
#COMPILER::endif
    }
}

# vim: expandtab shiftwidth=4
