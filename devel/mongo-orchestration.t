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

use MongoDB;

use lib 'devel/lib';
use MongoOrchestration;
use Data::Dumper;

subtest 'Base http_request method' => sub {
    my $base = MongoDBTest::Orchestration::Base->new;
    $base->get;
    is($base->{response}->{status}, '200');
    is($base->{parsed_response}->{service}, 'mongo-orchestration');
};

subtest 'Base get method' => sub {
    my $base = MongoDBTest::Orchestration::Base->new;
    $base->get;
    is($base->{response}->{status}, '200');
    is($base->{parsed_response}->{service}, 'mongo-orchestration');
    is($base->{response}->{reason}, 'OK');
    like($base->message_summary, qr/^GET .* OK, .* JSON:/, 'Base message_summary')
};

my $standalone_config = {
    orchestration => 'hosts',
    post_data => {
        id => 'standalone',
        name => 'mongod',
        procParams => {
            journal => 1
        }
    }
};

subtest 'Service initialization and check' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    is($service->{parsed_response}->{service}, 'mongo-orchestration');
    is($service->{parsed_response}->{version}, '0.9');
};

subtest 'Service configure Cluster/Hosts' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($standalone_config);
    ok($cluster->isa('MongoDBTest::Orchestration::Hosts'));
};

subtest 'Cluster/Hosts start, status and stop methods' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($standalone_config);
    ok($cluster->isa('MongoDBTest::Orchestration::Hosts'));

    $cluster->stop; # force stop

    $cluster->start;
    like($cluster->message_summary, qr{^POST /hosts, 200 OK, response JSON: });
    is($cluster->{object}->{id}, 'standalone');

    $cluster->start; # start for already started
    like($cluster->message_summary, qr{GET /hosts/standalone, 200 OK, response JSON: });
    is($cluster->{object}->{id}, 'standalone');

    $cluster->status; # status for started
    like($cluster->message_summary, qr{GET /hosts/standalone, 200 OK, response JSON: });

    #print "uri: $cluster->{object}->{uri}\n";

    $cluster->stop;
    is($cluster->message_summary, 'DELETE /hosts/standalone, 204 No Content');

    $cluster->stop; # stop for already stopped
    is($cluster->message_summary, 'GET /hosts/standalone, 404 Not Found');

    $cluster->status; # status for stopped
    is($cluster->message_summary, 'GET /hosts/standalone, 404 Not Found');

    #print "@{[$cluster->message_summary]}\n";
};

subtest 'Cluster/Hosts host method object with status, start, stop and restart methods' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($standalone_config);

    $cluster->start;
    my $host = $cluster->host;
    ok($host->isa('MongoDBTest::Orchestration::Host'));
    is($host->base_path, '/hosts/standalone');
    is($host->{object}->{id}, 'standalone');

    $host->status;
    like($host->message_summary, qr{GET /hosts/standalone, 200 OK, response JSON: });
    is($host->{object}->{id}, 'standalone');

    $host->stop;
    is($host->message_summary, 'PUT /hosts/standalone/stop, 200 OK');

    $host->status; # TODO - need status for no process
    like($host->message_summary, qr{GET /hosts/standalone, 200 OK, response JSON: });

    $host->start;
    is($host->message_summary, 'PUT /hosts/standalone/start, 200 OK');

    $host->restart;
    is($host->message_summary, 'PUT /hosts/standalone/restart, 200 OK');

    $cluster->stop;
};

my $replicaset_config = {
    orchestration => "rs",
    post_data => {
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

subtest 'Cluster/RS with members, primary, secondaries, arbiters and hidden' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($replicaset_config);
    ok($cluster->isa('MongoDBTest::Orchestration::RS'));

    $cluster->start;

    my @servers;
    @servers = $cluster->members;
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{base_path}, qr{^/rs/repl0/members/});
        ok(exists($_->{object}->{host_id}));
    }

    my $primary = $cluster->primary;
    ok($primary->isa('MongoDBTest::Orchestration::Host'));
    like($primary->{base_path}, qr{^/rs/repl0/primary});
    ok(exists($primary->{object}->{host_id}));
    ok(exists($primary->{object}->{uri}));

    @servers = $cluster->secondaries;
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{base_path}, qr{^/rs/repl0/members/});
        ok(exists($_->{object}->{host_id}));
    }

    @servers = $cluster->arbiters;
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{base_path}, qr{^/rs/repl0/members/});
        ok(exists($_->{object}->{host_id}));
    }

    @servers = $cluster->hidden;
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{base_path}, qr{^/rs/repl0/members/});
        ok(exists($_->{object}->{host_id}));
    }

    $cluster->stop;
};


my $sharded_configuration = {
    orchestration => "sh",
    post_data => {
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

subtest 'Cluster/SH with members, configservers, routers' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($sharded_configuration);
    ok($cluster->isa('MongoDBTest::Orchestration::SH'));

    $cluster->start;

    my @servers;
    @servers = $cluster->members;
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{base_path}, qr{^/sh/shard_cluster_1/members/sh});
        ok(exists($_->{object}->{id}));
    }

    @servers = $cluster->configservers;
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{base_path}, qr{^/sh/shard_cluster_1/hosts/});
        ok(exists($_->{object}->{id}));
    }

    @servers = $cluster->routers;
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{base_path}, qr{^/sh/shard_cluster_1/hosts/});
        ok(exists($_->{object}->{id}));
    }

    $cluster->stop;
};

my $hosts_preset_config = {
    orchestration => 'hosts',
    post_data => {
        preset => 'basic.json',
    }
};

my $rs_preset_config = {
    orchestration => 'rs',
    post_data => {
        preset => 'basic.json',
    }
};

my $sh_preset_config = {
    orchestration => 'sh',
    post_data => {
        preset => 'basic.json',
    }
};

subtest 'Service configure preset Cluster' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my @preset_configs = ($hosts_preset_config, $rs_preset_config, $sh_preset_config);
    foreach (@preset_configs) {
        my $cluster = $service->configure($_);
        $cluster->status;
        ok(!defined($cluster->id));
        $cluster->start;
        ok(defined($cluster->id));
        is($cluster->{object}->{orchestration}, $_->{orchestration});
        print "preset $cluster->{object}->{orchestration}/$_->{preset}, id: $cluster->{id}\n";
        $cluster->stop;
    }
};

done_testing;

1;
