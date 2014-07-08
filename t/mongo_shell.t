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
use Tie::IxHash;

use lib "t/lib";
#use MongoDBTest '$testdb', '$conn', '$server_type';

use MongoShellTest;
use Data::Dumper;
use IO::String;
use JSON;

subtest "mongo shell" => sub {

    my $ms = MongoDB::Shell->new;

    my $rs = MongoDB::ReplSetTest->new(ms => $ms);
    my $output;
    $output = $rs->start;
    $output = $rs->status;
    print "output: $output\n";
    $output = $rs->restart;
    $output = $rs->stop;

    $ms->stop;

    is(1, 1);
};

done_testing;
