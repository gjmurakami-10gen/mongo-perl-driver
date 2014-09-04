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

subtest 'Base http_request method' => sub {
    my $base = MongoDBTest::Orchestration::Base->new;
    $base->get;
    is($base->{response}->{status}, '200', "mongo-orchestration service at $base->{base_uri}") or done_testing, exit;
    ok($base->ok);
};

subtest 'Base get method' => sub {
    my $base = MongoDBTest::Orchestration::Base->new;
    $base->get;
    is($base->{response}->{status}, '200');
    is($base->{parsed_response}->{service}, 'mongo-orchestration');
    is($base->{response}->{reason}, 'OK');
    like($base->message_summary, qr/^GET .* OK, .* JSON:/);
    ok($base->ok);
};

subtest 'Resource initialization sets object' => sub {
    my $resource = MongoDBTest::Orchestration::Resource->new;
    ok($resource->ok);
    ok($resource->object);
};

subtest 'Service initialization and check' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    is($service->{parsed_response}->{service}, 'mongo-orchestration');
    is($service->{parsed_response}->{version}, '0.9');
};

my $standalone_config = {
    orchestration => 'servers',
    request_content => {
        id => 'standalone',
        name => 'mongod',
        procParams => {
            journal => 1
        }
    }
};

subtest 'Cluster/Server init, status, stop, start, restart and destroy methods' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($standalone_config);

    $cluster->destroy; # force destroy

    $cluster->init;
    like($cluster->message_summary, qr{PUT /servers/[-\w]+, 200 OK, response JSON: });
    like($cluster->{object}->{id}, qr{[-\w]+});

    $cluster->init; # init for already init'ed
    like($cluster->message_summary, qr{GET /servers/[-\w]+, 200 OK, response JSON: });
    like($cluster->{object}->{id}, qr{[-\w]+});

    $cluster->status; # status for init'ed
    like($cluster->message_summary, qr{GET /servers/[-\w]+, 200 OK, response JSON: });

    like($cluster->object->{mongodb_uri}, qr{:});
    my $mongodb_uri = $cluster->object->{mongodb_uri};
    # add client connection to $mongodb_uri

    $cluster->stop;
    like($cluster->message_summary, qr{POST /servers/[-\w]+, 200 OK});

    $cluster->start;
    like($cluster->message_summary, qr{POST /servers/[-\w]+, 200 OK});

    $cluster->restart;
    like($cluster->message_summary, qr{POST /servers/[-\w]+, 200 OK});

    $cluster->destroy;
    like($cluster->message_summary, qr{DELETE /servers/[-\w]+, 204 No Content});

    $cluster->destroy; # destroy for already destroyed
    like($cluster->message_summary, qr{GET /servers/[-\w]+, 404 Not Found});

    $cluster->status; # status for destroyed
    like($cluster->message_summary, qr{GET /servers/[-\w]+, 404 Not Found});

    #print "@{[$cluster->message_summary]}\n";
};

subtest 'Service configure Cluster/Server' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($standalone_config);
    ok($cluster->isa('MongoDBTest::Orchestration::Server'));
    like($cluster->object->{mongodb_uri}, qr{:});
    ok(exists($cluster->object->{procInfo}));
};

my $replicaset_config = {
    orchestration => "replica_sets",
    request_content => {
        id => "repl0",
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

subtest 'Cluster/ReplicaSet with members, primary, secondaries, arbiters and hidden' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($replicaset_config);
    ok($cluster->isa('MongoDBTest::Orchestration::ReplicaSet'));

    my @servers;
    @servers = $cluster->member_resources;
    is(scalar(@servers), 3);
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Resource'));
        like($_->{base_path}, qr{^/replica_sets/repl0/members/});
    }

    my $primary = $cluster->primary;
    ok($primary->isa('MongoDBTest::Orchestration::Server'));
    like($primary->{base_path}, qr{^/servers/});
    is($primary->{object}->{orchestration}, 'servers');
    like($primary->{object}->{mongodb_uri}, qr{:});
    ok(exists($primary->{object}->{procInfo}));

    @servers = $cluster->members;
    is(scalar(@servers), 3);
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Server'));
        like($_->{base_path}, qr{^/servers/});
        is($_->{object}->{orchestration}, 'servers');
        like($_->{object}->{mongodb_uri}, qr{:});
        ok(exists($_->{object}->{procInfo}));
    }

    @servers = $cluster->secondaries;
    is(scalar(@servers), 2);
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Server'));
        like($_->{base_path}, qr{^/servers/});
        is($_->{object}->{orchestration}, 'servers');
        like($_->{object}->{mongodb_uri}, qr{:});
        ok(exists($_->{object}->{procInfo}));
    }

    @servers = $cluster->arbiters;
    is(scalar(@servers), 0);
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Server'));
        like($_->{base_path}, qr{^/servers/});
        is($_->{object}->{orchestration}, 'servers');
        like($_->{object}->{mongodb_uri}, qr{:});
        ok(exists($_->{object}->{procInfo}));
    }

    @servers = $cluster->hidden;
    is(scalar(@servers), 0);
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Server'));
        like($_->{base_path}, qr{^/servers/});
        is($_->{object}->{orchestration}, 'servers');
        like($_->{object}->{mongodb_uri}, qr{:});
        ok(exists($_->{object}->{procInfo}));;
    }

    $cluster->destroy;
};

my $sharded_configuration = {
    orchestration => "sharded_clusters",
    request_content => {
        id => "shard_cluster_1",
        configsvrs => [
            {
            }
        ],
        shards => [
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

subtest 'Cluster/ShardedCluster with host shards, configsvrs, routers' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($sharded_configuration);
    ok($cluster->isa('MongoDBTest::Orchestration::ShardedCluster'));

    my @servers;
    @servers = $cluster->shard_resources;
    is(scalar(@servers), 2);
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Resource'));
        like($_->{base_path}, qr{^/sharded_clusters/shard_cluster_1/shards/});
        ok(exists($_->{object}->{isServer}));
    }

    my @shards = $cluster->shards;
    is(scalar(@shards), 2);
    foreach (@shards) {
        ok($_->isa('MongoDBTest::Orchestration::Server'));
        like($_->{base_path}, qr{^/servers/});
        is($_->{object}->{orchestration}, 'servers');
        ok(exists($_->{object}->{mongodb_uri}));
        ok(exists($_->{object}->{procInfo}));
    }

    @servers = $cluster->configsvrs;
    is(scalar(@servers), 1);
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Server'));
        like($_->{base_path}, qr{^/servers/});
        is($_->{object}->{orchestration}, 'servers');
        ok(exists($_->{object}->{mongodb_uri}));
        ok(exists($_->{object}->{procInfo}));;
    }

    @servers = $cluster->routers;
    is(scalar(@servers), 2);
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Server'));
        like($_->{base_path}, qr{^/servers/});
        is($_->{object}->{orchestration}, 'servers');
        ok(exists($_->{object}->{mongodb_uri}));
        ok(exists($_->{object}->{procInfo}));;
    }

    $cluster->destroy;
};

my $sharded_replica_set_configuration = {
    orchestration => "sharded_clusters",
    request_content => {
        id => "shard_cluster_2",
        configsvrs => [
            {
            }
        ],
        shards => [
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

subtest 'Cluster/ShardedCluster with replica-set shards' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($sharded_replica_set_configuration);
    ok($cluster->isa('MongoDBTest::Orchestration::ShardedCluster'));

    my @servers;
    @servers = $cluster->shard_resources;
    is(scalar(@servers), 2);
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Resource'));
        like($_->{base_path}, qr{^/sharded_clusters/shard_cluster_2/shards/});
        ok(exists($_->{object}->{isReplicaSet}));
    }

    my @shards = $cluster->shards;
    is(scalar(@shards), 2);
    foreach (@shards) {
        ok($_->isa('MongoDBTest::Orchestration::ReplicaSet'));
        like($_->{base_path}, qr{^/replica_sets/});
        is($_->{object}->{orchestration}, 'replica_sets');
        ok(exists($_->{object}->{mongodb_uri}));
        ok(exists($_->{object}->{members}));
    }

    $cluster->destroy;
};

my $hosts_preset_config = {
    orchestration => 'servers',
    request_content => {
        id => 'host_preset_1',
        preset => 'basic.json'
    }
};

my $rs_preset_config = {
    orchestration => 'replica_sets',
    request_content => {
        id => 'rs_preset_1',
        preset => 'basic.json'
    }
};

my $sh_preset_config = {
    orchestration => 'sharded_clusters',
    request_content => {
        id => 'sh_preset_1',
        preset => 'basic.json'
    }
};

subtest 'Service configure preset Cluster' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my @preset_configs = ($hosts_preset_config, $rs_preset_config, $sh_preset_config);
    foreach (@preset_configs) {
        my $cluster = $service->configure($_);
        is($cluster->{object}->{orchestration}, $_->{orchestration});
        #print "preset $cluster->{object}->{orchestration}/$_->{request_content}->{preset}, id: $cluster->{id}\n";
        $cluster->destroy;
    }

    # repeat with id deleted
    foreach (@preset_configs) {
        delete($_->{request_content}->{id});
        my $cluster = $service->configure($_);
        is($cluster->{object}->{orchestration}, $_->{orchestration});
        #print "preset $cluster->{object}->{orchestration}/$_->{request_content}->{preset}, id: $cluster->{id}\n";
        $cluster->destroy;
    }
};

done_testing;

1;
