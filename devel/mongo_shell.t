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

subtest "rs attributes"=> sub {
    my $rs = MongoDBTest::TestUtils::ensure_cluster(ms => $ms, kind => 'rs');

    is($rs->exists, 1);
    is($rs->nodes, 3);
    is($rs->startPort, 31000);
};

subtest "rs methods" => sub {
    my $rs = MongoDBTest::TestUtils::ensure_cluster(ms => $ms, kind => 'rs');

    is($rs->exists, 1);

    my $status = $rs->status;
    print "status: $status\n";

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

    my $seeds = $rs->seeds;
    print "seeds: $seeds\n";
    is(split(',', $seeds), 3);
};

subtest "rs restart" => sub {
    my $rs = MongoDBTest::TestUtils::ensure_cluster(ms => $ms, kind => 'rs');

    is($rs->exists, 1);
    my $restart = $rs->restart;
    print Dumper($restart);
};

done_testing;

print "stopping cluster...\n";
my $rs = MongoDBTest::TestUtils::ensure_cluster(ms => $ms, kind => 'rs');
$rs->stop;
print "cluster stopped.\n";

print "stopping mongo shell...\n";
$ms->stop;
print "end of mongo_shell.t\n";
