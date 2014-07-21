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

my $orch = MongoDBTest::ShellOrchestrator->new( config => { type => 'single' } );

subtest "md attributes"=> sub {
    my $md = $orch->ensure_cluster;

    is($md->exists, 1);
    print "dataPath: ${\$md->dataPath}\n";
};

subtest "md methods" => sub {
    my $md = $orch->ensure_cluster;

    is($md->exists, 1);

    my $as_uri = $md->as_uri;
    print "as_uri: $as_uri\n";
};

subtest "md restart" => sub {
    my $md = $orch->ensure_cluster;

    is($md->exists, 1);
    my $stop = $md->stop;

    my $restart = $md->restart;
    print Dumper($restart);
};

done_testing;

1;

