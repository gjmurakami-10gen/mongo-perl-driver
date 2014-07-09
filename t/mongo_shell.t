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
use Tie::IxHash;

use lib "t/lib";
#use MongoDBTest '$testdb', '$conn', '$server_type';

use MongoShellTest;
use Data::Dumper;
use IO::String;
use JSON;
use String::Util 'trim';

sub parse_psuedo_array {
    my ($s) = @_;
    $s =~ s/^\[(.*)\]$/$1/m;
    return [ map { trim $_ } split(/,/, $s) ];
};

subtest "mongo shell" => sub {
    my $result;

    $result = '[ connection to scherzo.local:31001, connection to scherzo.local:31002 ]';
    $result = parse_psuedo_array($result);
    print Dumper($result);
    die;

    my $ms = MongoDB::Shell->new;

    my $rs = MongoDB::ReplSetTest->new(ms => $ms);
    my $output;
    $output = $rs->start;
    $output = $rs->status;
    print "output: $output\n";
    $output = $rs->restart;
    print "rs->exists: @{[$rs->exists]}\n";

    print "nodes:\n";
    print Dumper($rs->nodes);
    print "startPort:\n";
    print Dumper($rs->startPort);

    $result = $rs->x_s("@{[$rs->var]}.nodes;");
    print "nodes: $result\n";

    print "primary:\n";
    print Dumper($rs->primary);

    print "secondaries:\n";
    $result = $rs->x_s("@{[$rs->var]}.getSecondaries();");
    print Dumper($result);

    $output = $rs->stop;
    $ms->stop;
    is(1, 1);
};

done_testing;
