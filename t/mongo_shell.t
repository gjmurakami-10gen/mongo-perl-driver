#
#  Copyright 2009-2013 MongoDB, Inc.
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
#


use strict;
use warnings;
use Test::More 0.96;
use Test::Fatal;
use Test::Warn;

use MongoDB;

use lib "t/lib";
#use MongoDBTest '$testdb', '$conn', '$server_type';

use MongoShellTest;
use Data::Dumper;
use IO::String;
use JSON;

subtest "mongo shell" => sub {

#    my $result = "[
#                 	\"connection to osprey.local:31000\",
#                 	\"connection to osprey.local:31001\",
#                 	\"connection to osprey.local:31002\"
#]
#> ";
#    my $prompt = MongoDB::Shell::PROMPT;
#    $result =~ s/$prompt//m;
#    my @result = decode_json $result; #parse_psuedo_array($result);
#    print Dumper(@result);
#    my @a = map { uc $_ } @result;
#    print Dumper(@a);
#    my $numbers = [1, 2, 3, 4]; #(1, 2, 3); #(1..4); #
#    print Dumper($numbers);
#    my @squares = map { $_ * $_ } @$numbers;
#    print Dumper(@squares);
#    my @names = qw(bob anne frank jill);
#    print Dumper(@names);
#    my @capitalised_names = map { ucfirst $_ } @names;
#    print Dumper(@capitalised_names);
#    die;

    my $ms = MongoDB::Shell->new;

    my $rs = MongoDB::ReplSetTest->new(ms => $ms);
    my $output;
    $output = $rs->start;
    #$output = $rs->status;
    #print "output: $output\n";
    $output = $rs->restart;
    print "rs->exists: @{[$rs->exists]}\n";

    print "nodes:\n";
    print Dumper($rs->nodes);
    print "startPort:\n";
    print Dumper($rs->startPort);

    my $nodes = $rs->get_nodes;
    print "get_nodes:\n";
    print Dumper($nodes);

    my $primary = $rs->primary;
    print "primary:\n";
    print Dumper($primary);
    is($primary->var, 'rs');
    is($primary->host_port, join(':', $primary->host, $primary->port));

    print "secondaries:\n";
    print Dumper($rs->secondaries);

    $output = $rs->stop;
    $ms->stop;
    is(1, 1);
};

done_testing;
