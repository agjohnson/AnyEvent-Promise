package AnyEvent::Promise;

use 5.010;
use strict;
use warnings FATAL => 'all';

use Try::Tiny qw//;
use Carp;

=head1 NAME

AnyEvent::Promise - Evented promises

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

Avoid the evented pyramid of doom!

    use AnyEvent::Promise;
    use AnyEvent::Redis;

    our $Redis = AnyEvent::Redis->new();

    my $p = promise(sub {
        $Redis->get('test');
    })->then(sub {
        $Redis->set('test', shift);
    })->then(sub {
        $Redis->get('test');
    })->then(sub {
        say shift;
    })->fulfill;

=head1 EXPORT

=head2 promise()

=cut

sub promise { AnyEvent::Promise->new(@_) }

sub new {
    my ($class, $fulfill) = @_;

    my $self = bless {
        guard => undef,
        fulfill => undef,
        reject => undef,
        rejected => 0
    }, $class;

    $self->{guard} = AnyEvent->condvar;

    my $reject = AnyEvent->condvar;
    $reject->cb(sub {
        carp shift->recv;
        $self->{guard}->send;
    });
    $self->{reject} = $reject;

    $self->try_fn($fulfill);

    return $self;
}

sub try_fn {
    my ($self, $fn) = @_;
    Try::Tiny::try {
        my $cv = $fn->();
        $self->{fulfill} = $cv;
    }
    Try::Tiny::catch {
        $self->{rejected} = 1;
        $self->{reject}->send(@_);
    }
}

sub then {
    my ($self, $fn) = @_;

    return $self
      if ($self->{rejected});

    $self->{guard}->begin;
    my $cvin = $self->{fulfill};
    my $cvout = AnyEvent->condvar;
    $cvin->cb(sub {
        my $thenret = shift;
        Try::Tiny::try {
            my $ret = $thenret->recv;
            my $cvret = $fn->($ret);
            if ($cvret and ref $cvret eq 'AnyEvent::CondVar') {
                $cvret->cb(sub {
                    my $ret = shift;
                    Try::Tiny::try {
                        $cvout->send($ret->recv);
                        $self->{guard}->end;
                    }
                    Try::Tiny::catch {
                        $self->{rejected} = 1;
                        $self->{reject}->send(@_);
                    }
                });
            }
            else {
                $cvout->send($cvret);
                $self->{guard}->end;
            }
        }
        Try::Tiny::catch {
            $self->{rejected} = 1;
            $self->{reject}->send(@_);
        }
    });
    $self->{fulfill} = $cvout;

    return $self;
}

sub catch {
    my ($self, $fn) = @_;

    $self->{reject}->cb(sub {
        my @err = shift->recv;
        $fn->(@err);
        $self->{guard}->send;
    });

    return $self;
}

sub fulfill {
    my $self = shift;
    $self->{guard}->recv;
    return $self;
}

=head1 AUTHOR

Anthony Johnson, C<< <aj at ohess.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Anthony Johnson.

This program is distributed under the MIT (X11) License:
L<http://www.opensource.org/licenses/mit-license.php>

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

=cut

1;
