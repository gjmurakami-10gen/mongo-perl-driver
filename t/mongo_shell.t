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
tie *IO, 'IO::String';

subtest "mongo shell" => sub {
    my $ms = MongoDB::Shell->new;
    my $result = $ms->x_s("1+1;");
    print "result: $result\n";
    is("2", $result);
    $ms->sh("2+2;");
    my $sio = IO::String->new;
    $sio->print("Hello sio\n");
    my $line;
    read($sio, $line, 100);
    #$line = <$sio>;
    print "line: $line\n";
    $ms->sh("4+4;", $sio);
    $ms->stop;
};

done_testing;
