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
use JSON;

sub cat_path {
    my ($base_path, $path) = @_;
    return (defined($path) && $path ne '') ? (($base_path || '') . '/' . $path) : $base_path;
};

sub parse_response {
    my ($response) = @_;
    my $has_json = ($response->{headers}->{'content-length'} ne '0' and $response->{headers}->{'content-type'} eq 'application/json');
    return $has_json ? decode_json($response->{content}) : {};
};

package MongoDBTest::Orchestration::Base;

use Moo;
use Types::Standard -types;
use HTTP::Tiny;
use JSON;
use Data::Dumper;

has debug => (
    is => 'rw',
    default => 0
);

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
    $options->{content} = encode_json($options->{content}) if exists($options->{content});
    $self->method($method);
    $self->abs_path(::cat_path($self->{base_path}, $path));
    my $uri = $self->base_uri . $self->abs_path;
    if ($self->debug) {
        print "$method $uri, options: ";
        print Dumper($options);
    }
    $self->response(HTTP::Tiny->new->request($method, $uri, $options));
    $self->parsed_response(::parse_response($self->response));
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

sub ok {
    my ($self) = @_;
    my $ok = int($self->{response}->{status} / 100) == 2;
    return $ok;
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
use Data::Dumper;

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
    my $request_content = $config->{request_content};
    my $id = $request_content->{id};
    if (!defined($id)) {
        my $http_request = MongoDBTest::Orchestration::Base->new(base_path => '');
        $http_request->post($orchestration, {content => $request_content});
        $id = $http_request->parsed_response->{id};
    }
    my $class = 'MongoDBTest::Orchestration::' . ORCHESTRATION_CLASS->{$orchestration};
    my $base_path = "/$orchestration/$id";
    my $cluster = $class->new(base_path => $base_path, request_content => $request_content, id => $id);
    return $cluster;
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

sub host { # reroute (ex. member) to a host resource
    my ($self) = @_;
    my $id = $self->{object}->{_id};
    my $base_path = "/hosts/$id";
    my $host = MongoDBTest::Orchestration::Hosts->new(base_path => $base_path, id => $id);
    $host->status;
    return $host;
};

package MongoDBTest::Orchestration::Cluster;

use Moo;
use Types::Standard -types;
use JSON;

extends 'MongoDBTest::Orchestration::Base';

has request_content => (
    is => 'rw',
    default => sub { return {}; }
);

has id => (
    is => 'rw',
    default => ''
);

sub BUILD {
    my ($self) = @_;
};

sub status {
    my ($self) = @_;
    $self->get;
    if ($self->{response}->{status} eq '200') {
        $self->object($self->{parsed_response});
        $self->id($self->{object}->{id});
    }
    return $self;
};

sub start {
    my ($self) = @_;
    if (!$self->status->ok) {
        $self->put('', {content => $self->request_content});
        if ($self->{response}->{status} eq '200') {
            $self->object($self->parsed_response);
            $self->id($self->{object}->{id});
        }
    }
    else {
        #$self->put;
    }
    return $self;
};

sub stop {
    my ($self) = @_;
    if ($self->status->ok) {
        $self->delete;
        if ($self->{response}->{status} eq '204') {
            #$self->object({});
        }
    }
    return $self;
};

sub host {
    my ($self, $resource, $host_info, $id_key) = @_;
    my $base_path = (($resource =~ qr{^/}) ? '' : "$self->{base_path}/") . "$resource/$host_info->{$id_key}";
    return MongoDBTest::Orchestration::Host->new(base_path => $base_path, object => $host_info);
};

sub hosts {
    my ($self, $get, $resource, $id_key) = @_;
    my $base_path = "$self->{base_path}/$get";
    my $http_request = MongoDBTest::Orchestration::Base->new(base_path => $base_path);
    $http_request->get;
    if ($http_request->ok) {
        return map { $self->host($resource, $_, $id_key) } @{$http_request->parsed_response};
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
    my $base_path = $self->{base_path};
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
    my $base_path = "$self->{base_path}/primary";
    my $http_request = MongoDBTest::Orchestration::Base->new(base_path => $base_path);
    $http_request->get;
    if ($http_request->ok) {
        return MongoDBTest::Orchestration::Host->new(base_path => $base_path, object => $http_request->parsed_response)
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
    return $self->hosts('configservers', '/hosts', 'id');
}

sub routers {
    my ($self) = @_;
    return $self->hosts('routers', '/hosts', 'id');
}

1;
