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
    like($base->message_summary, qr/^GET .* OK, .* JSON:/)
};

my $standalone_config = {
    orchestration => 'hosts',
    request_content => {
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
    like($cluster->message_summary, qr{PUT /hosts/[-\w]+, 200 OK, response JSON: });
    like($cluster->{object}->{id}, qr{[-\w]+});

    $cluster->start; # start for already started
    like($cluster->message_summary, qr{GET /hosts/[-\w]+, 200 OK, response JSON: });
    like($cluster->{object}->{id}, qr{[-\w]+});

    $cluster->status; # status for started
    like($cluster->message_summary, qr{GET /hosts/[-\w]+, 200 OK, response JSON: });

    #print "uri: $cluster->{object}->{uri}\n";

    $cluster->stop;
    like($cluster->message_summary, qr{DELETE /hosts/[-\w]+, 204 No Content});

    $cluster->stop; # stop for already stopped
    like($cluster->message_summary, qr{GET /hosts/[-\w]+, 404 Not Found});

    $cluster->status; # status for stopped
    like($cluster->message_summary, qr{GET /hosts/[-\w]+, 404 Not Found});

    #print "@{[$cluster->message_summary]}\n";
};

subtest 'Cluster/Hosts host method object with status, start, stop and restart methods' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($standalone_config);

    my $host = $cluster->host;
    ok($host->isa('MongoDBTest::Orchestration::Host'));
    like($host->base_path, qr{/hosts/[-\w]+});
    like($host->{object}->{id}, qr{[-\w]+});

    $host->status;
    like($host->message_summary, qr{GET /hosts/[-\w]+, 200 OK, response JSON: });
    like($host->{object}->{id}, qr{[-\w]+});

    $host->stop;
    like($host->message_summary, qr{PUT /hosts/[-\w]+/stop, 200 OK});

    $host->status; # TODO - need status for no process
    like($host->message_summary, qr{GET /hosts/[-\w]+, 200 OK, response JSON: });

    $host->start;
    like($host->message_summary, qr{PUT /hosts/[-\w]+/start, 200 OK});

    $host->restart;
    like($host->message_summary, qr{PUT /hosts/[-\w]+/restart, 200 OK});

    $cluster->stop;
};

my $replicaset_config = {
    orchestration => "rs",
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

subtest 'Cluster/RS with members, primary, secondaries, arbiters and hidden' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($replicaset_config);
    ok($cluster->isa('MongoDBTest::Orchestration::RS'));

    my @servers;
    @servers = $cluster->members;
    is(scalar(@servers), 3);
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
    is(scalar(@servers), 2);
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{base_path}, qr{^/rs/repl0/members/});
        ok(exists($_->{object}->{host_id}));
    }

    @servers = $cluster->arbiters;
    is(scalar(@servers), 0);
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{base_path}, qr{^/rs/repl0/members/});
        ok(exists($_->{object}->{host_id}));
    }

    @servers = $cluster->hidden;
    is(scalar(@servers), 0);
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{base_path}, qr{^/rs/repl0/members/});
        ok(exists($_->{object}->{host_id}));
    }

    $cluster->stop;
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

subtest 'Cluster/SH with members, configservers, routers' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($sharded_configuration);
    ok($cluster->isa('MongoDBTest::Orchestration::SH'));

    my @servers;
    @servers = $cluster->members;
    is(scalar(@servers), 2);
    foreach (@servers) {
        ok($_->isa('MongoDBTest::Orchestration::Host'));
        like($_->{base_path}, qr{^/sh/shard_cluster_1/members/sh});
        ok(exists($_->{object}->{id}));
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

    $cluster->stop;
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

    $cluster->stop;
};

my $hosts_preset_config = {
    orchestration => 'hosts',
    request_content => {
        preset => 'basic.json',
    }
};

my $rs_preset_config = {
    orchestration => 'rs',
    request_content => {
        preset => 'basic.json',
    }
};

my $sh_preset_config = {
    orchestration => 'sh',
    request_content => {
        preset => 'basic.json',
    }
};

subtest 'Service configure preset Cluster' => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my @preset_configs = ($hosts_preset_config, $rs_preset_config, $sh_preset_config);
    foreach (@preset_configs) {
        my $cluster = $service->configure($_);
        ok(defined($cluster->id));
        is($cluster->{object}->{orchestration}, $_->{orchestration});
        #print "preset $cluster->{object}->{orchestration}/$_->{request_content}->{preset}, id: $cluster->{id}\n";
        $cluster->stop;
    }
};

done_testing;

1;
