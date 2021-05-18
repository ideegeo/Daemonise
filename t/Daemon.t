#!/usr/bin/env perl
use warnings;
use strict;

#use Data::Dump;
use FindBin;

BEGIN {
    use lib "$FindBin::Bin/../lib";
}
use Daemonise;

package Daemonise {

    # Daemonise's stop() does an exit(), so our call to start() below never completes and we never
    # get to set the exit code.
    no warnings;
    sub stop { }
};

use Test::More;

# 16GB is considered "infinite" as far as these limits go.
my %default_opts = (exit_size => 16e9, abort_size => 16e9);

my $variant = shift;
if (not defined $variant) {
    run_test();
} elsif ($variant eq 'no_fail') {
    run_daemon(%default_opts);
} elsif ($variant eq 'exit_size') {
    run_daemon(%default_opts, exit_size => 200e6);
} elsif ($variant eq 'abort_size') {
    run_daemon(%default_opts, abort_size => 200e6);
} else {
    die "Unknown run mode $variant";
}

my $step = 0;
my $leaked;

sub start {

    # dd(scalar BSD::Resource::getrlimit(&BSD::Resource::RLIMIT_VMEM));
    $step += 1;
    if ($step == 1) {

        #warn "-- no-op run --\n";
    } elsif ($step == 2) {

        #warn "-- large run --\n";

        # This contrived code is to stop perl from just inlining a huge string in the binary and
        # causing the test to fail on the first iteration because the program *starts* with the
        # string already built.

        my $zero  = '0';
        my $count = 300e6;
        $leaked = $zero x $count;
    } else {
        warn "Ran too many times";
        exit 64;
    }
}

sub run_daemon {
    my %opts = @_;

    my $d = Daemonise->new();
    $d->debug(1);
    $d->foreground(1);
    $d->load_plugin('Daemon');
    $d->config({ daemon => \%opts });
    $d->configure();

    #dd($d);
    #warn "starting?";
    $d->start(\&start);

    #warn "exiting?";
    exit(32 + $step);
}

sub run_test {
    my $script = "$FindBin::Bin/$FindBin::Script";
    my @args;

    @args = ($script, "no_fail");

    # "exit 64" above when it falls through after success
    is(system(@args), 64 << 8, "@args");

    @args = ($script, "exit_size");

    # 34 indicates $step was 2 above.
    is(system(@args), 34 << 8, "@args");

    @args = ($script, "abort_size");

    # failure via OOM abort gives exit code 1.
    is(system(@args), 1 << 8, "@args");

    done_testing();
}
