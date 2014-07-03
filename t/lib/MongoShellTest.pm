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

package MongoDB::Shell;

use Moo;
use IO::Socket;
use Data::Dumper;

$SIG{CHLD} = 'IGNORE';

sub BUILDARGS {
   my ( $class, @args ) = @_;
   print "BUILDARGS\n";
   unshift @args, "attr1" if @args % 2 == 1;

   return { @args };
};

sub spawn {
    my $pid;
    unless ($pid = fork) {
        exec('../mongo/mongo', '--nodb', '--shell', '--listen', '30001');
        exit(0);
    }
};

sub connect {
    my $retries = 10;
    for (my $i = 0; $i < $retries; $i++) {
        my $sock = IO::Socket::INET->new("localhost:30001");
        return if defined $sock;
        spawn;
        sleep(1);
    }
    die "Error on connect to mongo shell after $retries retries\n";
};

1;
