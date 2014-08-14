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

use lib "devel/lib";

use Data::Dumper;
use IO::String;
use JSON;
use MongoOrchestration;

subtest "Base http_request method" => sub {
    my $base = MongoDBTest::Orchestration::Base->new;
    $base->get;
    is($base->{response}->{status}, '200');
    is($base->{parsed_response}->{service}, 'mongo-orchestration');
};

subtest "Base get method" => sub {
    my $base = MongoDBTest::Orchestration::Base->new;
    $base->get;
    is($base->{response}->{status}, '200');
    is($base->{parsed_response}->{service}, 'mongo-orchestration');
    is($base->{response}->{reason}, 'OK');
    like($base->result_message, qr/^GET .* OK, .* JSON:/, 'Base result_message')
};

my $standalone_config = {
    orchestration => "hosts",
    post_data => {
        id => "standalone",
        name => "mongod",
        procParams => {
            journal => 1
        }
    }
};

subtest "Service" => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    is($service->{parsed_response}->{version}, '0.9');
};

subtest "Cluster/Hosts" => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($standalone_config);
    ok($cluster->isa('MongoDBTest::Orchestration::Hosts'));
};

subtest "Cluster/Hosts start, status, and stop methods" => sub {
    my $service = MongoDBTest::Orchestration::Service->new;
    my $cluster = $service->configure($standalone_config);
    ok($cluster->isa('MongoDBTest::Orchestration::Hosts'));

    $cluster->stop; # force stop

    $cluster->start;
    is($cluster->{method}, 'post');
    is($cluster->{response}->{status}, '200');
    like($cluster->result_message, qr{^POST /hosts, 200 OK, response JSON: });
    is($cluster->{object}->{id}, 'standalone');

    $cluster->start;
    is($cluster->{method}, 'get');
    is($cluster->{response}->{status}, '200');
    like($cluster->result_message, qr{GET /hosts/standalone, 200 OK, response JSON: });
    is($cluster->{object}->{id}, 'standalone');

    $cluster->status;
    is($cluster->{method}, 'get');
    is($cluster->request, '/hosts/standalone');
    is($cluster->{response}->{status}, '200');
    like($cluster->result_message, qr{GET /hosts/standalone, 200 OK, response JSON: });

    #print "uri: $cluster->{object}->{uri}\n";

    $cluster->stop;
    is($cluster->{method}, 'delete');
    is($cluster->request, '/hosts/standalone');
    is($cluster->{response}->{status}, '204');
    is($cluster->result_message, 'DELETE /hosts/standalone, 204 No Content');

    $cluster->stop;
    is($cluster->{method}, 'get');
    is($cluster->request, '/hosts/standalone');
    is($cluster->{response}->{status}, '404');
    is($cluster->result_message, 'GET /hosts/standalone, 404 Not Found');

    $cluster->status;
    is($cluster->{method}, 'get');
    is($cluster->request, '/hosts/standalone');
    is($cluster->{response}->{status}, '404');
    is($cluster->result_message, 'GET /hosts/standalone, 404 Not Found');

    #print "@{[$cluster->result_message]}\n";
};

done_testing;

1;
