#!/usr/bin/perl -Ilib

package Daemonise::Plugin::RabbitMQ;

use Mouse::Role;
use Net::RabbitMQ;

has 'rabbit_host' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'localhost',
);

has 'rabbit_port' => (
    is      => 'rw',
    isa     => 'Int',
    default => 5672,
);

has 'rabbit_user' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'guest',
);

has 'rabbit_pass' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'guest',
);

has 'rabbit_vhost' => (
    is      => 'rw',
    isa     => 'Str',
    default => '/',
);

has 'rabbit_exchange' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'amq.direct',
);

has 'rabbit_channel' => (
    is      => 'rw',
    isa     => 'Int',
    default =>  1,
);

has 'rabbit_last_response' => (
    is      => 'rw',
    default =>  '',
);

has 'mq' => (
    is      => 'rw',
    isa     => 'Net::RabbitMQ',
    default => sub { },
);

after 'queue_bind' => sub {
    my ( $self, $queue ) = @_;

    if ($queue) {
        $self->_amqp();
        eval { $self->mq->consume( $self->rabbit_channel, $queue ); };
        if ($@) {
            $self->_consume_queue($queue);
        }
        print STDERR "Bound to queue '$queue' using channel ".$self->rabbit_channel."\n";
        return $self->rabbit_channel;
    }
    else {
        confess "You have to provide a queue to bind to!";
    }
    return;
};

after 'msg_pub' => sub {
    my ( $self, $msg, $queue ) = @_;
    my $rep;
    if ($msg) {
        $self->_get_channel;
        eval{$self->mq->channel_open($self->rabbit_channel);};
        if($@){
            $self->_amqp();
        }
        eval{$rep = $self->mq->publish( $self->rabbit_channel, $queue, $msg);};
        if($@){
            confess "Could not send message: $@\n";
        }
        $self->mq->channel_close($self->rabbit_channel);
    }
    else {
        confess "You have to provide a message to send!";
    }
    print STDERR "Sent message to queue '$queue' with channel ".$self->rabbit_channel." ($rep)\n";
    return;
};

after 'msg_rpc' => sub {
    my ( $self, $msg, $queue, $reply_queue ) = @_;
    my $rep;
    if ($msg) {
        $self->_consume_queue($reply_queue, 'temp');
        my $rep_chan = $self->_get_channel;
        eval{$self->mq->channel_open($self->rabbit_channel);};
        eval{$rep = $self->mq->publish( $self->rabbit_channel, $queue, $msg);};
        if($@){
            confess "Could not send message: $@\n";
        }
        $self->mq->channel_close($self->rabbit_channel);
        my $reply = $self->mq->recv();
        #$self->mq->channel_close($rep_chan);
        print STDERR "Got reply on queue $reply_queue\n";
        $self->rabbit_last_response($reply->{body});
    }
    else {
        confess "You have to provide a message to send!";
    }
    print STDERR "Sent message to queue '$queue' with channel ".$self->rabbit_channel." ($rep)\n";
    return $self->rabbit_last_response;
};

sub _amqp {
    my $self = shift;

    my $amqp = Net::RabbitMQ->new();
    eval {
        $amqp->connect(
            $self->rabbit_host,
            {
                user     => $self->rabbit_user,
                password => $self->rabbit_pass,
                port     => $self->rabbit_port,
                vhost    => $self->rabbit_vhost,
            }
        );
    };
    if ($@) {
        confess "Could not connect to the RabbitMQ server! $@\n";
    }
    $self->_get_channel;
    print STDERR "Trying to open channel: ".$self->rabbit_channel."\n";
    $amqp->channel_open( $self->rabbit_channel );
    print STDERR "Declaring exchange: ".$self->rabbit_exchange."\n";
    eval { $amqp->exchange_declare( $self->rabbit_channel, $self->rabbit_exchange, { durable => 1, auto_delete => 0 } ); };
    if ($@) {
        print "Exchange " . $self->rabbit_exchange . " already defined: $@\n";
    }
    print STDERR "Initialized connection successfully\n";
    $self->mq($amqp);
    return $amqp;
}

sub _consume_queue {
    my ($self, $queue, $temp) = @_;
    $self->_get_channel;
    eval { $self->mq->channel_open( $self->rabbit_channel ); };
    if($@){
        $self->_amqp();
    }
    if($temp){
        eval { $self->mq->queue_declare( $self->rabbit_channel, $queue, { durable => 0, auto_delete => 1 } ); };
        eval { $self->mq->consume( $self->rabbit_channel, $queue ); };
    } else {
        eval { $self->mq->queue_declare( $self->rabbit_channel, $queue, { durable => 1, auto_delete => 0 } ); };
        eval { $self->mq->exchange_declare( $self->rabbit_channel, $self->rabbit_exchange, { durable => 1, auto_delete => 0 } ); };
        eval { $self->mq->queue_bind( $self->rabbit_channel, $queue, $self->rabbit_exchange, $queue ); };
        eval { $self->mq->consume( $self->rabbit_channel, $queue ); };
    }
    if ($@) {
        confess "Could not setup the listening queue: $@\n";
    }
    return;
}

sub _get_channel {
    my $self = shift;
    my $num = $self->rabbit_channel;
    $num++;
    $num = 1 if($num > 64000);
    $self->rabbit_channel($num);
    return $num;
}

1;
