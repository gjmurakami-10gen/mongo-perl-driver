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

sub cat_uri {
    my ($uri, $path) = @_;
    return (defined($path) && $path ne '') ? (($uri || '') . '/' . $path) : $uri;
};

package MongoDBTest::Orchestration::Base;

use Moo;
use Types::Standard -types;
use HTTP::Tiny;
use JSON;
use File::Spec::Functions;
use Data::Dumper;

has base_uri => (
    is => 'rw',
    isa => Str,
    default => 'http://localhost:8889'
);

has uri => (
    is => 'rw',
    isa => Str,
    default => '/'
);

has method => (
    is => 'rw',
    isa => Str,
    default => 'get'
);

has request => (
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
    $self->request(::cat_uri($self->{uri}, $path));
    my $request = $self->base_uri . $self->request;
    $self->response(HTTP::Tiny->new->request($method, $request, $options));
    #print Dumper($self->response);
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

sub get {
    my ($self, $path, $options) = @_;
    return $self->http_request('get', $path, $options);
}

sub post {
    my ($self, $path, $options) = @_;
    return $self->http_request('post', $path, $options);
}

sub delete {
    my ($self, $path, $options) = @_;
    return $self->http_request('delete', $path, $options);
}

sub result_message {
    my ($self) = @_;
    my $msg = "@{[uc($self->{method})]} $self->{request}";
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
use Types::Standard -types;
use HTTP::Tiny;
use JSON;
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
    my $uri = "/$orchestration";
    my $class = 'MongoDBTest::Orchestration::' . ORCHESTRATION_CLASS->{$orchestration};
    return $class->new(uri => $uri, config => $config);
};

package MongoDBTest::Orchestration::Cluster;

use Moo;
use Types::Standard -types;
use HTTP::Tiny;
use JSON;
use Data::Dumper;

extends 'MongoDBTest::Orchestration::Base';

has post_data => (
    is => 'rw',
    default => sub { return {}; }
);

has id => (
    is => 'rw',
    isa => Str,
    default => ''
);

sub BUILD {
    my ($self) = @_;
    $self->post_data($self->{config}->{post_data});
    $self->id($self->{post_data}->{id});
    #print "Cluster::BUILD uri: $self->{uri}, id: $self->{id}";
};

sub status {
    my ($self) = @_;
    $self->get($self->id);
    $self->object($self->parsed_response) if $self->{response}->{status} eq '200';
    return $self;
};

sub start {
    my ($self) = @_;
    $self->status;
    if ($self->{response}->{status} ne '200') {
        $self->post('', {content => encode_json($self->post_data)});
        if ($self->{response}->{status} eq '200') {
            $self->object($self->parsed_response);
        }
    }
    else {
        #$self->put($sefl->id);
    }
    return $self;
};

sub stop {
    my ($self) = @_;
    $self->status;
    if ($self->{response}->{status} eq '200') {
        $self->delete($self->id);
        if ($self->{response}->{status} eq '204') {
            #$self->object({});
        }
    }
    return $self;
};

package MongoDBTest::Orchestration::Hosts;

use Moo;
use Types::Standard -types;
use HTTP::Tiny;
use JSON;
use Data::Dumper;

extends 'MongoDBTest::Orchestration::Cluster';

1;
