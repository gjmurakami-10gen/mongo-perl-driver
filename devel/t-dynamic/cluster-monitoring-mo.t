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

use lib "t/lib";
use lib "devel/lib";

use lib 'devel/lib';
use MongoOrchestration;
use MongoDB;
use Try::Tiny;
use Data::Dumper;

# This is an investigation of the cluster monitoring test spec, it may be discarded for something leaner.

my $orch = MongoDBTest::Orchestration::Service->new;

subtest 'Mongo orchestration service required' => sub {
    is($orch->{response}->{status}, '200', "mongo-orchestration service at $orch->{base_uri}") or done_testing, exit;
};

my $standalone_config = { orchestration => 'hosts', request_content => { preset => 'basic.json', id => 'standalone_cmt'} };
my $standalone = $orch->configure($standalone_config);

subtest 'Connect to standalone' => sub {
    SKIP: {
        like($standalone->message_summary, qr{^POST /hosts, 200 OK, response JSON: }) or skip 'no standalone server', 1;
        # 1. Client is configured with seed A.
        my $seed_a = $standalone->{object}->{uri};
        my $seed = "mongodb://$seed_a";
        my $client = MongoDB::MongoClient->new(host => $seed);
        # 2. A responds: { ok: 1, ismaster: true }
        # 3. Expected: A is ServerType Standalone. ClusterType is Single.
        isa_ok($client, 'MongoDB::MongoClient');
        is($client->{server_type}, 'standalone', 'Expected: A is ServerType Standalone');
        is($client->{cluster_type}, 'single', 'Expected: ClusterType is Single');
    }
};

subtest 'Handle a not-ok ismaster response' => sub {
    # skip - cannot generate as servers do not currently respond "ok: 0" under any known circumstance.
    # 1. Client is configured with seed A.
    # 2. A responds: { ok: 1, ismaster: true }
    # 3. A responds again: { ok: 0, ismaster: true }
    # 4. Expected: A is ServerType Unknown. ClusterType is Single.
    ok(1, 'not applicable');
};

$standalone->stop;

subtest 'Cluster unavailable' => sub {
    # A MongoClient can be constructed without an exception, even with all seeds unavailable.
    my $seed = "mongodb://$standalone->{object}->{uri}";
    TODO: {
        local $TODO = 'not implemented';
        try {
            lives_and { MongoDB::MongoClient->new(host => $seed) };
        }
        catch {
            print "    caught unexpected exception: $_\n";
        }
    }
    ok(0, 'implementation or test incomplete');
};

$standalone->start;

subtest 'Standalone removed from multi-server cluster' => sub {
    # 1. A is a standalone.
    # 2. Client is configured with seeds A and B.
    my $seed_a = "$standalone->{object}->{uri}";
    my $seed_b = "localhost:12345";
    my $seed = "mongodb://$seed_a,$seed_b";
    my $client = MongoDB::MongoClient->new(host => $seed);
    # 3. Initial ClusterType is Unknown, if the driver supports it, otherwise Sharded.
    $client->{cluster_type} = 'implementation pending';
    ok(($client->{cluster_type} eq 'unknown' || $client->{cluster_type} eq 'sharded'), 'Initial ClusterType is Unknown, if the driver supports it, otherwise Sharded');
    # 4. A responds: { ok: 1, ismaster: true }
    TODO: {
        # Expected: A is removed from ClusterDescription.
        my @cluster_description = ($seed_a);
        $client->{cluster_description} = \@cluster_description;
        my @g = grep($seed_a, $client->{cluster_description});
        ok(@g == 0, 'Expected: A is removed from ClusterDescription');
        ok(0, 'implementation or test incomplete');
    }
};

$standalone->stop;

# Sharded scenarios


my $sharded_replica_set_configuration = {
    orchestration => "sh",
    request_content => {
        id => "shard_cluster_2",
        configsvrs => [
            {
            }
        ],
        members => [
            {
                id => "sh1",
                shardParams => {
                    members => [{},{},{}]
                }
            },
            {
                id => "sh2",
                shardParams => {
                    members => [{},{},{}]
                }
            }
        ],
        routers => [
            {
            },
            {
            }
        ]
    }
};

my $sharded_cluster = $orch->configure($sharded_replica_set_configuration);

subtest 'Multiple mongoses' => sub {
    # 1. A and B are mongoses.
    # 2. Client is configured with seeds A and B.
    my ($seed_a, $seed_b) = split(/,/, $sharded_cluster->{object}->{uri});
    my $seed = "mongodb://$seed_a,$seed_b";
    my $client = MongoDB::MongoClient->new(host => $seed);
    # 3. A, then B, respond: { ok: 1, ismaster: true, msg: 'isdbgrid' }
    # Expected: ClusterType is Sharded, A and B are both ServerType Mongos.
    $client->{server} = {$seed_a => {cluster_type => 'implementation pending'}, $seed_b => {cluster_type => 'implementation pending'}};
    is($client->{cluster_type}, 'sharded', 'Expected: ClusterType is Sharded');
    is($client->{server}->{$seed_a}->{cluster_type}, 'sharded', 'Expected: A is ServerType Mongos');
    is($client->{server}->{$seed_b}->{cluster_type}, 'sharded', 'Expected: B is ServerType Mongos');
    ok(0, 'implementation or test incomplete');
};

subtest 'Non-mongos is removed' => sub {
    # 1. A is a mongos, B is primary.
    my ($seed_a, $seed_c) = split(/,/, $sharded_cluster->{object}->{uri});
    my @shards = $sharded_cluster->shards;
    my $primary = $shards[0]->primary;
    my $seed_b = $primary->object->{uri};

    # 2. Client is configured with seeds A and B.
    my $seed = "mongodb://$seed_a,$seed_b";
    print "seed: $seed\n";
    my $client = MongoDB::MongoClient->new(host => $seed);

    # 3. Initial ClusterType is Unknown or Sharded, depending on the driver.
    # 4. First ismaster response is from A: { ok: 1, ismaster: true, msg: 'isdbgrid' }
    # 5. Second response is from B: { ok: 1, ismaster: true, hosts: ['B:27017'], setName: 'rs' }
    # Expected: client knows A is ServerType Mongos, B is removed. ClusterType is Sharded.
    $client->{server} = {$seed_a => {cluster_type => 'implementation pending'}, $seed_b => {cluster_type => 'implementation pending'}};
    is($client->{cluster_type}, 'sharded', 'Expected: ClusterType is Sharded');
    is($client->{server}->{$seed_a}->{server_type}, 'mongos', 'Expected: client knows A is ServerType Mongos');
    is($client->{server}->{$seed_b}->{cluster_type}, undef, 'Expected: B is removed');
    ok(0, 'implementation or test incomplete');
};

$sharded_cluster->stop;

done_testing, exit;

# Replica set scenarios

my $replica_set_config = { orchestration => 'rs', request_content => { preset => 'basic.json', id => 'replica_set_cmt' } };
my $replica_set = $orch->configure($replica_set_config);

subtest 'RSGhost' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'Replica set discovery from primary' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'Replica set discovery from secondary' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest "Secondary's host list is not authoritative" => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'Member brought up as standalone' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'Ghost discovered' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'RSOther discovered' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'Discover passives' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'Discover arbiters' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'Wrong setName' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'Unexpected mongos' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'Member removed by reconfig' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'New primary' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'Host list differs from seeds' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'Response from removed server' => sub {
    ok(0, 'implementation or test incomplete');
};

# Parsing "not master" and "node is recovering" errors

subtest 'getLastError' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'Write command' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'Query with slaveOk bit' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'Query without slaveOk bit' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'Count with slaveOk bit' => sub {
    ok(0, 'implementation or test incomplete');
};

subtest 'Count without slaveOk bit' => sub {
    ok(0, 'implementation or test incomplete');
};

$replica_set->stop;

done_testing;

1;
