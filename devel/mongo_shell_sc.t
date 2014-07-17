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

use lib "devel/lib";
#use MongoDBTest '$testdb', '$conn', '$server_type';

use MongoShellTest;
use Data::Dumper;
use IO::String;
use JSON;

my $ms = MongoDBTest::Shell->new;

subtest "sc attributes"=> sub {
    my $sc = MongoDBTest::TestUtils::ensure_cluster(ms => $ms, kind => 'sc');

    is($sc->exists, 1);
};

subtest "sc methods" => sub {
    my $sc = MongoDBTest::TestUtils::ensure_cluster(ms => $ms, kind => 'sc');

    is($sc->exists, 1);

    my $nodes = $sc->get_nodes;
    print "get_nodes:\n";
    print Dumper($nodes);

    my $as_uri = $sc->as_uri;
    print "as_uri: $as_uri\n";
    is(split(',', $as_uri), 2);
};

subtest "sc restart" => sub {
    my $sc = MongoDBTest::TestUtils::ensure_cluster(ms => $ms, kind => 'sc');

    is($sc->exists, 1);
    my $restart = $sc->restart;
    print Dumper($restart);
};

done_testing;

$ms->stop;

1;

