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

sub cat_path {
    my ($base_path, $path) = @_;
    return (defined($path) && $path ne '') ? (($base_path || '') . '/' . $path) : $base_path;
};

package MongoDBTest::Orchestration::Base;

use Moo;
use Types::Standard -types;
use HTTP::Tiny;
use JSON;

has base_uri => (
    is => 'rw',
    isa => Str,
    default => 'http://localhost:8889'
);

has base_path => (
    is => 'rw',
    isa => Str,
    default => '/'
);

has method => (
    is => 'rw',
    isa => Str,
    default => 'get'
);

has abs_path => (
    is => 'rw',
    isa => Str,
    default => ''
);

has response => (
    is => 'rw'
);

has parsed_response => (
    is => 'rw'
);

has config => (
    is => 'rw',
    default => sub { return {}; }
);

has object => (
    is => 'rw',
    default => sub { return {}; }
);

sub http_request {
    my ($self, $method, $path, $options) = @_;
    $options ||= {};
    $self->method($method);
    $self->abs_path(::cat_path($self->{base_path}, $path));
    my $uri = $self->base_uri . $self->abs_path;
    $self->response(HTTP::Tiny->new->request($method, $uri, $options));
    if ($self->{response}->{headers}->{'content-length'} ne '0' and
            length($self->{response}->{content}) > 0 and
            $self->{response}->{headers}->{'content-type'} eq 'application/json') {
        $self->parsed_response(decode_json($self->{response}->{content}));
    }
    else {
        $self->parsed_response({});
    }
    return $self->response;
};

sub post {
    my ($self, $path, $options) = @_;
    return $self->http_request('post', $path, $options);
}

sub get {
    my ($self, $path, $options) = @_;
    return $self->http_request('get', $path, $options);
}

sub put {
    my ($self, $path, $options) = @_;
    return $self->http_request('put', $path, $options);
}

sub delete {
    my ($self, $path, $options) = @_;
    return $self->http_request('delete', $path, $options);
}

sub message_summary {
    my ($self) = @_;
    my $msg = "@{[uc($self->{method})]} $self->{abs_path}";
    $msg .= ", $self->{response}->{status} $self->{response}->{reason}";
    return $msg if $self->{response}->{headers}->{'content-length'} eq "0";
    if ($self->{response}->{headers}->{'content-type'} eq 'application/json') {
        $msg .= ", response JSON: @{[encode_json($self->{parsed_response})]}";
    }
    else {
        $msg .= ", response: $self->{response}->{content}";
    }
    return $msg;
};

package MongoDBTest::Orchestration::Service;

use Moo;

extends 'MongoDBTest::Orchestration::Base';

use constant {
    VERSION_REQUIRED => '0.9',
    ORCHESTRATION_CLASS => { 'hosts' => 'Hosts', 'rs' => 'RS', 'sh' => 'SH' }
};

sub BUILD {
    my ($self) = @_;
    $self->get;
    $self->check_service;
}

sub check_service {
    my ($self) = @_;
    die "mongo-orchestration version is $self->{parsed_response}->{version}, version {VERSION_REQUIRED} is required" if $self->{parsed_response}->{version} lt VERSION_REQUIRED;
    return $self;
};

sub configure {
    my ($self, $config) = @_;
    my $orchestration = $config->{orchestration};
    my $base_path = "/$orchestration";
    my $class = 'MongoDBTest::Orchestration::' . ORCHESTRATION_CLASS->{$orchestration};
    return $class->new(base_path => $base_path, config => $config);
};

package MongoDBTest::Orchestration::Host;

use Moo;

extends 'MongoDBTest::Orchestration::Base';

sub status {
    my ($self) = @_;
    $self->get;
    $self->object($self->parsed_response) if $self->response->{status} eq '200';
    return $self;
};

sub start {
    my ($self) = @_;
    $self->put('start');
    return $self;
};

sub stop {
    my ($self) = @_;
    $self->put('stop');
    return $self;
};

sub restart {
    my ($self) = @_;
    $self->put('restart');
    return $self;
};

package MongoDBTest::Orchestration::Cluster;

use Moo;
use Types::Standard -types;
use JSON;

extends 'MongoDBTest::Orchestration::Base';

has post_data => (
    is => 'rw',
    default => sub { return {}; }
);

has id => (
    is => 'rw',
    default => ''
);

sub BUILD {
    my ($self) = @_;
    $self->post_data($self->{config}->{post_data});
    $self->id($self->{post_data}->{id});
};

sub status {
    my ($self) = @_;
    if (defined($self->id) && $self->id ne '') {
        $self->get($self->id);
        if ($self->{response}->{status} eq '200') {
            $self->object($self->parsed_response);
            $self->id($self->{object}->{id});
            return 1;
        }
    }
    return 0;
};

sub start {
    my ($self) = @_;
    if (!$self->status) {
        $self->post('', {content => encode_json($self->post_data)});
        if ($self->{response}->{status} eq '200') {
            $self->object($self->parsed_response);
            $self->id($self->{object}->{id});
        }
    }
    else {
        #$self->put($self->id);
    }
    return $self;
};

sub stop {
    my ($self) = @_;
    if ($self->status) {
        $self->delete($self->id);
        if ($self->{response}->{status} eq '204') {
            #$self->object({});
        }
    }
    return $self;
};

sub host {
    my ($self, $resource, $host_info, $id_key) = @_;
    my $base_path = "$self->{base_path}/$self->{id}/$resource/$host_info->{$id_key}";
    return MongoDBTest::Orchestration::Host->new(base_path => $base_path, object => $host_info);
};

sub hosts {
    my ($self, $get, $resource, $id_key) = @_;
    my $uri = "$self->{base_uri}$self->{base_path}/$self->{id}/$get";
    my $response = HTTP::Tiny->new->get($uri);
    if ($response->{status} eq '200') {
        my $content = decode_json($response->{content});
        return map { $self->host($resource, $_, $id_key) } @$content;
    }
    else {
        my @empty;
        return @empty;
    }
};

package MongoDBTest::Orchestration::Hosts;

use Moo;

extends 'MongoDBTest::Orchestration::Cluster';

sub host {
    my ($self) = @_;
    my $base_path = ::cat_path($self->{base_path}, $self->id);
    return MongoDBTest::Orchestration::Host->new(base_path => $base_path, object => $self->object);
};

package MongoDBTest::Orchestration::RS;

use Moo;
use HTTP::Tiny;
use JSON;

extends 'MongoDBTest::Orchestration::Cluster';

sub members {
    my ($self) = @_;
    return $self->hosts('members', 'members', '_id'); # host_id
}

sub primary {
    my ($self) = @_;
    my $uri = "$self->{base_uri}$self->{base_path}/$self->{id}/primary";
    my $response = HTTP::Tiny->new->get($uri);
    if ($response->{status} eq '200') {
        my $content = decode_json($response->{content});
        my $base_path = "$self->{base_path}/$self->{id}/primary";
        return MongoDBTest::Orchestration::Host->new(base_path => $base_path, object => $content);
    }
    else {
        return undef;
    }
};

sub secondaries {
    my ($self) = @_;
    return $self->hosts('secondaries', 'members', '_id'); # host_id
};

sub arbiters {
    my ($self) = @_;
    return $self->hosts('arbiters', 'members', '_id'); # host_id
};

sub hidden {
    my ($self) = @_;
    return $self->hosts('hidden', 'members', '_id'); # host_id
};

package MongoDBTest::Orchestration::SH;

use Moo;

extends 'MongoDBTest::Orchestration::Cluster';

sub members {
    my ($self) = @_;
    return $self->hosts('members', 'members', 'id');
}

sub configservers {
    my ($self) = @_;
    return $self->hosts('configservers', 'hosts', 'id');
}

sub routers {
    my ($self) = @_;
    return $self->hosts('routers', 'hosts', 'id');
}

1;
