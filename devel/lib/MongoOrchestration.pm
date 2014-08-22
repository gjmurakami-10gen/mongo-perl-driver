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
    isa => Bool,
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
    return $self;
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

package MongoDBTest::Orchestration::Resource;

use Moo;

extends 'MongoDBTest::Orchestration::Base';

has object => (
    is => 'rw',
    default => sub { return {}; }
);

sub BUILD {
    my ($self, $path, $options) = @_;
    $self->get;
};

sub get {
    my ($self, $path, $options) = @_;
    $self->SUPER::get($path, $options);
    $self->object($self->parsed_response) if $self->ok;
    return $self;
}

sub sub_resource {
    my ($self, $sub_class, $path) = @_;
    my $base_path = ::cat_path($self->base_path, $path);
    my $class = 'MongoDBTest::Orchestration::' . $sub_class;
    my $resource = $class->new(base_path => $base_path);
    return $resource->get;
};

package MongoDBTest::Orchestration::Service;

use Moo;

extends 'MongoDBTest::Orchestration::Resource';

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
    return $cluster->start;
};

package MongoDBTest::Orchestration::Host;

use Moo;

extends 'MongoDBTest::Orchestration::Resource';

sub status {
    my ($self) = @_;
    $self->get;
    return $self;
};

sub start {
    my ($self) = @_;
    return $self->put('start'); # return $self->put('', { content => { action => 'start' } });
};

sub stop {
    my ($self) = @_;
    return $self->put('stop'); # return $self->put('', { content => { action => 'start' } });
};

sub restart {
    my ($self) = @_;
    return $self->put('restart'); # return $self->put('', { content => { action => 'restart' } });
};

sub host { # reroute (ex. member) to a host resource
    my ($self) = @_;
    my $id = $self->{object}->{_id};
    my $base_path = "/hosts/$id";
    my $host = MongoDBTest::Orchestration::Hosts->new(base_path => $base_path, id => $id);
    return $host->status;
};

sub rs { # reroute (ex. member) to a rs resource
    my ($self) = @_;
    my $id = $self->{object}->{_id};
    my $base_path = "/rs/$id";
    my $rs = MongoDBTest::Orchestration::RS->new(base_path => $base_path, id => $id);
    return $rs->status;
};

package MongoDBTest::Orchestration::Cluster;

use Moo;

extends 'MongoDBTest::Orchestration::Resource';

has request_content => (
    is => 'rw',
    default => sub { return {}; }
);

has id => (
    is => 'rw',
    default => ''
);

sub status {
    my ($self) = @_;
    $self->get;
    if ($self->ok) {
        $self->object($self->{parsed_response});
        $self->id($self->{object}->{id});
    }
    return $self;
};

sub start {
    my ($self) = @_;
    if (!$self->status->ok) {
        $self->put('', {content => $self->request_content});
        if ($self->ok) {
            $self->object($self->{parsed_response});
            $self->id($self->{object}->{id});
        }
    }
    return $self;
};

sub stop {
    my ($self) = @_;
    if ($self->status->ok) {
        $self->delete;
        if ($self->ok) {
            #$self->object({});
        }
    }
    return $self;
};

sub component {
    my ($self, $sub_class, $path, $object, $id_key) = @_;
    my $base_path = (($path =~ qr{^/}) ? '' : "$self->{base_path}/") . "$path/$object->{$id_key}";
    my $class = 'MongoDBTest::Orchestration::' . $sub_class;
    return $class->new(base_path => $base_path, object => $object);
};

sub components {
    my ($self, $get, $sub_class, $path, $id_key) = @_;
    my $sub_resource = $self->sub_resource('Resource', $get);
    my @empty;
    return ($sub_resource->ok) ?
        map { $self->component($sub_class, $path, $_, $id_key) } @{$sub_resource->object} :
        @empty;
};

package MongoDBTest::Orchestration::Hosts;

use Moo;

extends 'MongoDBTest::Orchestration::Cluster';

sub host {
    my ($self) = @_;
    return MongoDBTest::Orchestration::Host->new(base_path => $self->base_path, object => $self->object);
};

package MongoDBTest::Orchestration::RS;

use Moo;

extends 'MongoDBTest::Orchestration::Cluster';

sub members {
    my ($self) = @_;
    return $self->components('members', 'Host', 'members', '_id'); # host_id
}

sub primary {
    my ($self) = @_;
    my $sub_resource = $self->sub_resource('Resource', 'primary');
    return ($sub_resource->ok) ?
        $self->component('Host', 'members', $sub_resource->object, '_id') :
        undef;
};

sub secondaries {
    my ($self) = @_;
    return $self->components('secondaries', 'Host', 'members', '_id'); # host_id
};

sub arbiters {
    my ($self) = @_;
    return $self->components('arbiters', 'Host', 'members', '_id'); # host_id
};

sub hidden {
    my ($self) = @_;
    return $self->components('hidden', 'Host', 'members', '_id'); # host_id
};

package MongoDBTest::Orchestration::SH;

use Moo;

extends 'MongoDBTest::Orchestration::Cluster';

sub members {
    my ($self) = @_;
    return $self->components('members', 'Host', 'members', 'id');
}

sub configservers {
    my ($self) = @_;
    return $self->components('configservers', 'Host', '/hosts', 'id');
}

sub routers {
    my ($self) = @_;
    return $self->components('routers', 'Host', '/hosts', 'id');
}

1;
