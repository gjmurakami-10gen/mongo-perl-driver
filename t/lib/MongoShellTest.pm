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
use List::Flatten;
use IO::String;
tie *IO, 'IO::String';

use constant {
    MONGO_SHELL             => '../mongo/mongo',
    MONGO_SHELL_ARGS        => ['--nodb', '--shell', '--listen'],
    MONGO_PORT              => 30001,
    MONGO_TEST_FRAMEWORK_JS => 'devel/cluster_test.js',
    PROMPT                  => qr/>\ /m,
    BYE                     => qr/^bye\n$/m,
};

open(my $MONGO_LOG, '>', 'mongo_shell.log');

$SIG{CHLD} = 'IGNORE';

has port => (
    is      => 'rw',
    default => MONGO_PORT,
);

has pid => (
    is      => 'rw',
    default => -1,
);

has sock => (
    is      => 'rw',
    default => -1,
);

sub BUILD {
   my ($self) = @_;
   $self->connect;
   $self->read; # blocking read for prompt
};

sub spawn {
    my ($self) = @_;
    unless ($self->pid( fork )) {
        open STDOUT, '>&', $MONGO_LOG;
        open STDERR, '>&', $MONGO_LOG;
        my $mongo_shell = $ENV{'MONGO_SHELL'} || MONGO_SHELL;
        my @argv = flat($mongo_shell, MONGO_SHELL_ARGS, $self->port, MONGO_TEST_FRAMEWORK_JS);
        exec(@argv);
        exit(0);
    }
};

sub connect {
    my ($self) = @_;
    my $retries = 10;
    for (my $i = 0; $i < $retries; $i++) {
        $self->sock( IO::Socket::INET->new("localhost:30001") );
        return if defined $self->sock;
        $self->spawn;
        sleep(1);
    }
    die "Error on connect to mongo shell after $retries retries\n";
};

sub read {
    my ($self, $prompt) = @_;
    $prompt ||= PROMPT;
    my @result;
    my $buffer;
    do {
        $self->sock->recv($buffer, 1024);
        push(@result, $buffer);
    } until (!$buffer || $buffer =~ $prompt);
    return join('', @result);
};

sub puts {
    my ($self, $s) = @_;
    $s .= "n" unless substr($s, -1);
    $self->sock->send($s);
    return $self;
};

sub stop {
    my ($self) = @_;
    $self->puts("exit")->read(BYE);
    $self->sock->shutdown(2);
    $self->sock->close;
    waitpid($self->pid, 0);
    return $self;
};

sub x {
    my ($self, $s, $prompt) = @_;
    $prompt ||= PROMPT;
    my $result = $self->puts($s)->read($prompt);
    return $result;
};

sub x_s {
    my ($self, $s, $prompt) = @_;
    $prompt ||= PROMPT;
    my $result = $self->x($s, $prompt);
    $result =~ s/$prompt//;
    chomp($result);
    return $result;
};

sub sh {
     my ($self, $s, $out) = @_;
     $out ||= *STDOUT;
     my @lines = split(/\n/, $s);
     foreach (@lines) {
         $_ .= "\n";
         print $out $_;
         print $out $self->x($_);
     }
};

1;
