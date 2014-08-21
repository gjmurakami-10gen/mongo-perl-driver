#!/usr/bin/env perl
#
#  Copyright 2009-2014 MongoDB, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

use v5.10;
use strict;
use warnings;

use lib 'devel/lib';
use MongoOrchestration;
use Data::Dumper;

use Getopt::Long;
use Log::Any::Adapter 'Null';

my %opts;
GetOptions(
    \%opts,
    'verbose|v'
);

if ( $opts{verbose} ) {
    Log::Any::Adapter->set('Stderr');
}

my ($cluster_type, $preset, @command) = @ARGV;

unless ( $cluster_type && $preset && @command ) {
    print "usage: $0 <hosts|rs|sh> <preset> <command> [args ...]\nexample: $0 hosts basic.json make test";
    exit 1;
}

my $configuration = {
    orchestration => $cluster_type,
    request_content => {
        preset => $preset
    }
};

my $orch = MongoDBTest::Orchestration::Service->new;
my $cluster = $orch->configure($configuration);
$cluster->start;

die "cluster start error - @{[$cluster->message_summary]}\n" if $cluster->{response}->{status} ne '200';

$ENV{MONGOD} = "mongodb://$cluster->{object}->{uri}";
say "MONGOD=".$ENV{MONGOD};

say "@command";
my $exit_val = system(@command);
my $signal = $exit_val & 127;
$exit_val = $exit_val >> 8;

$cluster->stop;

exit( $signal || $exit_val );

__END__

=head1 NAME

harness-mo.pl - run a command under a given cluster definition

=head1 USAGE

    harness-mo.pl <config-file> <command> [args...]

This command will instantiate a cluster from a YAML config file
and run the command with arguments.

The C<MONGOD> environment variable will be set to a MongoDB connection
URI appropriate to the cluster.

=cut

# vim: ts=4 sts=4 sw=4 et:
