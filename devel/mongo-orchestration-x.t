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

subtest 'Cluster/SH with replica-set members, configservers, routers' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($sharded_replica_set_configuration);
    ok($cluster->isa('MongoDBTest::Orchestration::SH'));

    my @servers;
    @servers = $cluster->members;
    is(scalar(@servers), 2);
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{base_path}, qr{^/sh/shard_cluster_2/members/sh});
        ok(exists($_->{object}->{id}));
        ok($_->{object}->{isReplicaSet});
        print Dumper($_);
        my $rs = $_->rs;
        print Dumper($rs);
    }

    @servers = $cluster->configservers;
    is(scalar(@servers), 1);
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{base_path}, qr{^/hosts/});
        ok(exists($_->{object}->{id}));
    }

    @servers = $cluster->routers;
    is(scalar(@servers), 2);
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{base_path}, qr{^/hosts/});
        ok(exists($_->{object}->{id}));
    }

    #$cluster->stop;
};

done_testing, exit;

#my $sharded_cluster_config = { orchestration => 'sh', post_data => { preset => 'basic.json', id => 'sharded_cluster_cmt' } };
#my $sharded_cluster = $orch->configure($sharded_cluster_config);
my $sharded_cluster = $orch->configure($sharded_configuration);

subtest 'Non-mongos is removed' => sub {
    # 1. A is a mongos, B is primary.
    my ($seed_a, $seed_c) = split(/,/, $sharded_cluster->{object}->{uri});
    my @members = $sharded_cluster->members;
    is(scalar(@members), 2);
    print Dumper($members[0]);
    my $host = $members[0]->host;
    print Dumper($host);
    my $seed_b = $host->{object}->{uri};
    print "seed_b: $seed_b\n";

    # 2. Client is configured with seeds A and B.
    my $seed = "mongodb://$seed_a,$seed_b";
    print "seed: $seed\n";
    my $client = MongoDB::MongoClient->new(host => $seed);

    # 3. Initial ClusterType is Unknown or Sharded, depending on the driver.
    # 4. First ismaster response is from A: { ok: 1, ismaster: true, msg: 'isdbgrid' }
    # 5. Second response is from B: { ok: 1, ismaster: true, hosts: ['B:27017'], setName: 'rs' }

    # Expected: client knows A is ServerType Mongos, B is removed. ClusterType is Sharded.
    ok(0, 'implementation or test incomplete');
};

#$sharded_cluster->stop;

done_testing;

1;
