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

use Data::Dumper;
use MongoOrchestration;

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
    like($base->result_message, qr/^GET .* OK, .* JSON:/, 'Base result_message')
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
    like($cluster->result_message, qr{^POST /hosts, 200 OK, response JSON: });
    is($cluster->{object}->{id}, 'standalone');

    $cluster->start; # start for already started
    like($cluster->result_message, qr{GET /hosts/standalone, 200 OK, response JSON: });
    is($cluster->{object}->{id}, 'standalone');

    $cluster->status; # status for started
    like($cluster->result_message, qr{GET /hosts/standalone, 200 OK, response JSON: });

    #print "uri: $cluster->{object}->{uri}\n";

    $cluster->stop;
    is($cluster->result_message, 'DELETE /hosts/standalone, 204 No Content');

    $cluster->stop; # stop for already stopped
    is($cluster->result_message, 'GET /hosts/standalone, 404 Not Found');

    $cluster->status; # status for stopped
    is($cluster->result_message, 'GET /hosts/standalone, 404 Not Found');

    #print "@{[$cluster->result_message]}\n";
};

subtest 'Cluster/Hosts host method object with status, start, stop and restart methods' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($standalone_config);

    $cluster->start;
    my $host = $cluster->host;
    ok($host->isa('MongoDBTest::Orchestration::Host'));
    is($host->uri, '/hosts/standalone');
    is($host->{object}->{id}, 'standalone');

    $host->status;
    like($host->result_message, qr{GET /hosts/standalone, 200 OK, response JSON: });
    is($host->{object}->{id}, 'standalone');

    $host->stop;
    is($host->result_message, 'PUT /hosts/standalone/stop, 200 OK');

    $host->status; # TODO - need status for no process
    like($host->result_message, qr{GET /hosts/standalone, 200 OK, response JSON: });

    $host->start;
    is($host->result_message, 'PUT /hosts/standalone/start, 200 OK');

    $host->restart;
    is($host->result_message, 'PUT /hosts/standalone/restart, 200 OK');

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
        like($_->{uri}, qr{^/rs/repl0/members/});
        ok(exists($_->{object}->{host_id}));
    }

    my $primary = $cluster->primary;
    ok($primary->isa('MongoDBTest::Orchestration::Host'));
    like($primary->{uri}, qr{^/rs/repl0/members/});
    ok(exists($primary->{object}->{host_id}));
    ok(exists($primary->{object}->{uri}));

    @servers = $cluster->secondaries;
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{uri}, qr{^/rs/repl0/members/});
        ok(exists($_->{object}->{host_id}));
    }

    @servers = $cluster->arbiters;
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{uri}, qr{^/rs/repl0/members/});
        ok(exists($_->{object}->{host_id}));
    }

    @servers = $cluster->hidden;
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{uri}, qr{^/rs/repl0/members/});
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
        like($_->{uri}, qr{^/sh/shard_cluster_1/members/sh});
        ok(exists($_->{object}->{id}));
    }

    @servers = $cluster->configservers;
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{uri}, qr{^/sh/shard_cluster_1/hosts/});
        ok(exists($_->{object}->{id}));
    }

    @servers = $cluster->routers;
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{uri}, qr{^/sh/shard_cluster_1/hosts/});
        ok(exists($_->{object}->{id}));
    }

    $cluster->stop;
};

done_testing;

1;
