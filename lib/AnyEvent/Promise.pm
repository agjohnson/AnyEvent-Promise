package AnyEvent::Promise;

use 5.008;
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
    })->catch(sub {
        say 'I failed!';
        say @_;
    })->fulfill;

=head1 DESCRIPTION

L<AnyEvent::Promise> allows evented interfaces to be chained, taking away some
of the redundancy of layering L<AnyEvent> condition variable callbacks.

A promise is created using C<AnyEvent::Promise::new> or the exported C<promise>
helper function. These will both return a promise instance and add the callback
function as the start of the promise chain. Each call to C<then> on the promise
instance will add a callback to the callback chain, and calling C<fulfill> on
the instance will finally start the callback chain.

# TODO will it block?

Errors in the callbacks can be caught by setting an exception handler via the
C<catch> method on the promise instance. This method will catch exceptions
raised from L<AnyEvent> objects and exceptions raised in block provided to
C<then>. If an error is encountered in the chain, an exception will be thrown
and the rest of the chain will be skipped, jumping straight to the catch
callback.

=head1 EXPORT

=head2 promise($cb)

Start promise chain with closure C<$cb>. This is a shortcut to
C<AnyEvent::Promise::new>, and returns a promise object with callback attached.

=cut
sub promise { AnyEvent::Promise->new(@_) }

=head1 METHODS

=head2 new($cv)
=cut
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

    $self->_try_fn($fulfill);

    return $self;
}

sub _try_fn {
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

=head2 then($cb)

Wrap the top-most promise callback

=cut

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

=head2 catch($cb)

Catch raised errors in the callback chain

=cut
sub catch {
    my ($self, $fn) = @_;

    $self->{reject}->cb(sub {
        my @err = shift->recv;
        $fn->(@err);
        $self->{guard}->send;
    });

    return $self;
}

=head2 fulfill()

Start callback chain

=cut
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
