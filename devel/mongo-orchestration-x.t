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
#

use strict;
use warnings;
use Test::More 0.96;
use Test::Fatal;
use Test::Warn;

use lib 'devel/lib';
use MongoOrchestration;
use MongoDB;
use Data::Dumper;

my $orch = MongoDBTest::Orchestration::Service->new;
$orch->get;

subtest 'Mongo orchestration service required' => sub {
    is($orch->{response}->{status}, '200', "mongo-orchestration service at $orch->{base_uri}") or done_testing, exit;
};

my $standalone_config = {
    orchestration => 'hosts',
    request_content => {
        id => 'standalone_1',
        name => 'mongod',
        procParams => {
            journal => 1
        }
    }
};

my $replicaset_config = {
    orchestration => "rs",
    request_content => {
        id => "replica_set_1",
        members => [
            {
                procParams => {
                    nohttpinterface => 1,
                    journal => 1,
                    noprealloc => 1,
                    nssize => 1,
                    oplogSize => 150,
                    smallfiles => 1
                },
                rsParams => {
                    priority => 99
                }
            },
            {
                procParams => {
                    nohttpinterface => 1,
                    journal => 1,
                    noprealloc => 1,
                    nssize => 1,
                    oplogSize => 150,
                    smallfiles => 1
                },
                rsParams => {
                    priority => 1.1
                }
            },
            {
                procParams => {
                    nohttpinterface => 1,
                    journal => 1,
                    noprealloc => 1,
                    nssize => 1,
                    oplogSize => 150,
                    smallfiles => 1
                }
            }
        ]
    }
};

my $sharded_configuration = {
    orchestration => "sh",
    request_content => {
        id => "shard_cluster_1",
        configsvrs => [
            {
            }
        ],
        members => [
            {
                id => "sh1",
                shardParams => {
                    procParams => {
                    }
                }
            },
            {
                id => "sh2",
                shardParams => {
                    procParams => {
                    }
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


my $hosts_preset_config = {
    orchestration => 'hosts',
    request_content => {
        id => 'host_preset_1',
        preset => 'basic.json',
    }
};

my $rs_preset_config = {
    orchestration => 'rs',
    request_content => {
        id => 'rs_preset_1',
        preset => 'basic.json',
    }
};

my $sh_preset_config = {
    orchestration => 'sh',
    request_content => {
        id => 'sh_preset_1',
        preset => 'basic.json',
    }
};

subtest 'Service configure preset Cluster' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my @preset_configs = ($hosts_preset_config, $rs_preset_config, $sh_preset_config);
    foreach (@preset_configs) {
        my $cluster = $service->configure($_);
        #print $cluster->message_summary;
        ok($cluster->ok);
        is($cluster->{object}->{orchestration}, $_->{orchestration});
        #print "preset $cluster->{object}->{orchestration}/$_->{request_content}->{preset}, id: $cluster->{id}\n";
        $cluster->stop;
    }

    # repeat with id deleted
    foreach (@preset_configs) {
        delete($_->{request_content}->{id});
        my $cluster = $service->configure($_);
        #print $cluster->message_summary;
        ok($cluster->ok);
        is($cluster->{object}->{orchestration}, $_->{orchestration});
        #print "preset $cluster->{object}->{orchestration}/$_->{request_content}->{preset}, id: $cluster->{id}\n";
        $cluster->stop;
    }
};

done_testing, exit;

my $sharded_cluster = $orch->configure($sharded_replica_set_configuration);

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

done_testing;

1;
