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

package MongoDBTest::TestUtils;

use String::Util 'trim';

sub parse_psuedo_array {
    my ($s) = @_;
    $s =~ s/^\[(.*)\]$/$1/sm;
    return map { trim $_ } split(/,/, $s);
};

sub ensure_cluster {
    my (%args) = @_;
    if  ($args{kind} eq 'rs') {
        my $rs = MongoDBTest::ReplSetTest->new(ms => $args{ms});
        return $rs->ensure_cluster;
    }
    elsif ($args{kind} eq 'sc') {
        my $sc = MongoDBTest::ShardingTest->new(ms => $args{ms});
        return $sc->ensure_cluster;
    }
    return undef;
};

package MongoDBTest::Shell;

use Moo;
use Types::Standard -types;
use IO::Socket;
use List::Flatten;
use IO::String;
use JSON;
use POSIX 'setsid';

use constant {
    MONGO_SHELL => '../mongo/mongo',
    MONGO_SHELL_ARGS => ['--nodb', '--shell', '--listen'],
    MONGO_PORT => 30001,
    MONGO_TEST_FRAMEWORK_JS => 'devel/cluster_test.js',
    MONGO_LOG => 'mongo_shell.log',
    RETRIES => 10,
    PROMPT => '> ',
    BYE => qr/^bye\n$/m,
};

open(my $MONGO_LOG, '>', MONGO_LOG);

$SIG{CHLD} = 'IGNORE';

has port => (
    is => 'rw',
    isa => Num,
    default => MONGO_PORT,
    coerce => sub { $_[0] + 0 },
);

has pid => (
    is => 'rwp',
    isa => Num,
    default => -1,
);

has sock => (
    is => 'rwp',
    #isa => InstanceOf['IO::Socket::INET'],
    default => undef,
);

sub BUILD {
   my ($self) = @_;
   $self->connect;
   $self->read; # blocking read for prompt
};

sub spawn {
    my ($self) = @_;
    unless ($self->_set_pid( fork )) {
        open STDOUT, '>&', $MONGO_LOG;
        open STDERR, '>&', $MONGO_LOG;
        open STDIN, '</dev/null';
        setsid;
        unless ($self->_set_pid( fork )) {
            my $mongo_shell = $ENV{'MONGO_SHELL'} || MONGO_SHELL;
            my @argv = flat($mongo_shell, MONGO_SHELL_ARGS, $self->port, MONGO_TEST_FRAMEWORK_JS);
            exec(@argv);
            exit(0);
        }
        exit(0);
    }
};

sub connect {
    my ($self) = @_;
    for (my $i = 0; $i < RETRIES; $i++) {
        $self->_set_sock( IO::Socket::INET->new("localhost:30001") );
        return if defined $self->sock;
        $self->spawn;
        sleep(1);
    }
    die "Error on connect to mongo shell after @{[RETRIES]} retries\n";
};

sub read {
    my ($self, $prompt) = @_;
    $prompt ||= PROMPT;
    my @result;
    my $buffer;
    do {
        $self->sock->recv($buffer, 1024);
        push(@result, $buffer);
    } until (!$buffer || $buffer =~ /$prompt/m);
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
    $result =~ s/$prompt$//m;
    chomp($result);
    return $result;
};

sub x_json {
    my ($self, $s, $prompt) = @_;
    $prompt ||= PROMPT;
    return decode_json($self->x_s($s, $prompt));
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

package MongoDBTest::Node;

use Moo;
use Types::Standard -types;

has cluster => (
    is => 'rw',
    isa => InstanceOf['MongoDBTest::ClusterTest'],
    required => 1,
);

has conn => (
    is => 'rw',
    isa => Str,
    required => 1,
);

has var => (
    is => 'rwp',
    isa => Str,
);

has host_port => (
    is => 'rwp',
    isa => Str,
);

has host => (
    is => 'rwp',
    isa => Str,
);

has port => (
    is => 'rwp',
    isa => Num,
    coerce => sub { $_[0] + 0 },
);

sub BUILD {
    my ($self) = @_;
    $self->_set_var($self->cluster->var);
    my $host_port = $self->conn;
    $host_port =~ s/connection to //;
    $self->_set_host_port($host_port);
    my ($host, $port) = split(/:/, $host_port);
    $self->_set_host($host);
    $self->_set_port($port);
};

package MongoDBTest::ClusterTest;

use Moo;
use Types::Standard -types;

has ms => (
    is => 'rw',
    isa => InstanceOf['MongoDBTest::Shell'],
    required => 1,
);

has var => (
    is => 'rw',
    isa => Str,
    default => 'ct',
);

has kind => (
    is => 'rw',
    isa => Str,
    default => 'ct',
);

sub x_s {
    my ($self, $s, $prompt) = @_;
    $prompt ||= MongoDBTest::Shell::PROMPT;
    return $self->ms->x_s($s, $prompt);
};

sub x_json {
    my ($self, $s, $prompt) = @_;
    $prompt ||= MongoDBTest::Shell::PROMPT;
    return $self->ms->x_json($s, $prompt);
};

sub sh {
    my ($self, $s, $out) = @_;
    $self->ms->sh($s, $out);
};

sub exists {
    my ($self) = @_;
    my $var = $self->var;
    return $self->x_s("typeof $var;") eq "object";
};

sub ensure_cluster {
    my ($self) = @_;
    if ($self->exists) {
        $self->restart;
    }
    else {
        #FileUtils.mkdir_p(@opts[:dataPath])
        $self->start;
    }
    return $self;
};

package MongoDBTest::ReplSetTest;

use Moo;
use Types::Standard -types;
use IO::String;
use JSON;

extends 'MongoDBTest::ClusterTest';

has var => (
    is => 'rw',
    isa => Str,
    default => 'rs',
);

has name => (
    is => 'rw',
    isa => Str,
    default => 'test',
);

has kind => (
    is => 'rw',
    isa => Str,
    default => 'rs',
);

has nodes => (
    is => 'rw',
    isa => Num,
    default => 3,
    coerce => sub { $_[0] + 0 },
);

has startPort => (
    is => 'rw',
    isa => Num,
    default => 31000,
    coerce => sub { $_[0] + 0 },
);

sub BUILD {
    my ($self) = @_;
    print "ReplSetTest::BUILD\n";
    print Dumper($self);
}

sub start {
    my ($self) = @_;
    my $sio = IO::String->new;
    my $var = $self->var;
    my $opts = {
        'var' => $self->var,
        'name' => $self->name,
        'nodes' => $self->nodes,
        'startPort' => $self->startPort,
    };
    my $json_opts = encode_json $opts;
    $self->sh("var $var = new ReplSetTest( $json_opts );", $sio);
    $self->sh("$var.startSet();", $sio);
    die ${$sio->string_ref} unless ${$sio->string_ref} =~ /ReplSetTest Starting/;
    $self->sh("$var.initiate();", $sio);
    die ${$sio->string_ref} unless ${$sio->string_ref} =~ /Config now saved locally.  Should come online in about a minute./;
    $self->sh("$var.awaitReplication();", $sio);
    die ${$sio->string_ref} unless ${$sio->string_ref} =~ /ReplSetTest awaitReplication: finished: all/;
    return ${$sio->string_ref};
};

sub stop {
    my ($self) = @_;
    my $var = $self->var;
    my $sio = IO::String->new;
    $self->sh("$var.stopSet();", $sio);
    die ${$sio->string_ref} unless ${$sio->string_ref} =~ /ReplSetTest stopSet \*\*\* Shut down repl set - test worked \*\*\*/;
    return ${$sio->string_ref};
};

sub restart {
    my ($self) = @_;
    my $var = $self->var;
    my $sio = IO::String->new;
    $self->sh("$var.restartSet();", $sio);
    $self->sh("$var.awaitSecondaryNodes(30000);", $sio);
    $self->sh("$var.awaitReplication(30000);", $sio);
    die ${$sio->string_ref} unless ${$sio->string_ref} =~ /ReplSetTest awaitReplication: finished: all/;
    return ${$sio->string_ref};
};

sub status {
    my ($self) = @_;
    my $var = $self->var;
    return $self->x_s("$var.status();");
};

sub get_nodes {
    my ($self) = @_;
    my $var = $self->var;
    my $nodes = $self->x_json("$var.nodes;");
    return map { MongoDBTest::Node->new(cluster => $self, conn => $_) } @$nodes;
};

sub primary {
    my ($self) = @_;
    my $var = $self->var;
    my $primary = $self->x_s("$var.getPrimary();");
    $primary =~ s/^"(.*)"$/$1/sm;
    return MongoDBTest::Node->new(cluster => $self, conn => $primary);
};

sub secondaries {
    my ($self) = @_;
    my $var = $self->var;
    my $secondaries = $self->x_json("$var.getSecondaries();");
    return map { MongoDBTest::Node->new(cluster => $self, conn => $_) } @$secondaries;
};

sub as_uri {
    my ($self) = @_;
    return "mongodb://" . join(',', map { $_->host_port } $self->get_nodes);
};

package MongoDBTest::ShardingTest;

use Moo;
use Types::Standard -types;
use IO::String;
use JSON;
use Data::Dumper;

extends 'MongoDBTest::ClusterTest';

has var => (
    is => 'rw',
    isa => Str,
    default => 'sc',
);

has name => (
    is => 'rw',
    isa => Str,
    default => 'test',
);

has kind => (
    is => 'rw',
    isa => Str,
    default => 'sc',
);

has shards => (
    is => 'rw',
    isa => Num,
    default => 2,
    coerce => sub { $_[0] + 0 },
);

#has rs => (
#    is => 'rw',
#    isa => HashRef,
#    default => { nodes => 3 },
#);

has mongos => (
    is => 'rw',
    isa => Num,
    default => 2,
    coerce => sub { $_[0] + 0 },
);

#has other => (
#    is => 'rw',
#    isa => HashRef,
#    default => { separateConfig => 1 },
#);

sub BUILD {
    my ($self) = @_;
    print "ShellOrchestrator::BUILD\n";
    print Dumper($self);
}

sub start {
    my ($self) = @_;
    my $sio = IO::String->new;
    my $var = $self->var;
    my $opts = {
        'var' => $self->var,
        'name' => $self->name,
        'shards' => $self->shards,
        'rs' => { nodes => 3 }, #$self->rs,
        'mongos' => $self->mongos,
        'other' => { separateConfig => 1 }, #$self->other,
    };
    my $json_opts = encode_json $opts;
    $self->sh("var $var = new ShardingTest( $json_opts );", $sio);
    return ${$sio->string_ref};
};

sub stop {
    my ($self) = @_;
    my $var = $self->var;
    my $sio = IO::String->new;
    $self->sh("$var.stop();", $sio);
    die ${$sio->string_ref} unless ${$sio->string_ref} =~ /\*\*\* ShardingTest test completed /;
    return ${$sio->string_ref};
};

sub restart {
    my ($self) = @_;
    my $var = $self->var;
    my $sio = IO::String->new;
    $self->sh("$var.restartMongos();", $sio);
    return ${$sio->string_ref};
};

sub get_nodes {
    my ($self) = @_;
    my $var = $self->var;
    my $nodes = $self->x_json("$var._mongos;");
    return map { MongoDBTest::Node->new(cluster => $self, conn => $_) } @$nodes;
};

sub as_uri {
    my ($self) = @_;
    return "mongodb://" . join(',', map { $_->host_port } $self->get_nodes);
};

package MongoDBTest::ShellOrchestrator;

use Moo;
use Types::Standard -types;
use Carp;
use YAML::XS;
use Types::Path::Tiny qw/AbsFile/;
use Data::Dumper;

# Optional

has ms => (
    is => 'rw',
    isa => InstanceOf['MongoDBTest::Shell'],
);

has config_file => (
    is => 'ro',
    isa => Str,
    default => '',
);

# Lazy or default

has config => (
    is => 'lazy',
    isa => HashRef,
);

sub _build_config {
    my ($self) = @_;
    my $config_file = $self->config_file;
    Carp::croak( sprintf( "no readable config file '%s' found", $self->config_file) )
        unless -r $self->config_file;
    my ($config) = YAML::XS::LoadFile($self->config_file);
    return $config;
}

has server_set => (
    is => 'lazy',
    isa => ConsumerOf['MongoDBTest::ClusterTest'],
    #handles => [qw/start stop as_uri as_pairs get_server all_servers/]
);

has type => (
    is => 'lazy',
    isa => Enum[qw/single replica sharded/],
);

sub _build_type {
    my ($self) = @_;
    $self->config->{type};
}

sub is_replica {
    my ($self) = @_;
    return $self->type eq 'replica';
}

sub _build_server_set {
    my ($self) = @_;

    my $class =  "MongoDBTest::" . ($self->is_replica ? "ReplSetTest" : "ShardingTest");
    return $class->new(
        ms => $self->ms,
    );
}

sub BUILD {
    my ($self) = @_;
    $self->ms(MongoDBTest::Shell->new);
}

sub DEMOLISH {
    my ($self) = @_;
    my $mongo_shutdown = $ENV{MONGO_SHUTDOWN};
    if (!defined($mongo_shutdown) || $mongo_shutdown !~ /^(0|false|)$/i) {
        $self->server_set->stop;
        $self->ms->stop;
    }
}

1;
