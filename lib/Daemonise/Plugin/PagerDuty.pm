package Daemonise::Plugin::PagerDuty;

use Mouse::Role;

# ABSTRACT: Daemonise PagerDuty plugin

use WebService::PagerDuty;
use Carp;

=head1 SYNOPSIS

This plugin conflicts with other plugins that provide caching, like the Redis plugin.

    use Daemonise;
    
    my $d = Daemonise->new();
    $d->debug(1);
    $d->foreground(1) if $d->debug;
    $d->config_file('/path/to/some.conf');
    
    $d->load_plugin('PagerDuty');
    
    $d->configure;
    
    # trigger an event/alert
    $d->alert("incident_key", "description", );
    
    # set a key and expire (see WebService::PagerDuty module for more info)
    $d->pagerduty->incidents(...);
    $d->pagerduty->schedules(...);
    $d->pagerduty->event(...);


=head1 ATTRIBUTES

=head2 pagerduty_api_key

=cut

has 'pagerduty_api_key' => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

=head2 pagerduty_subdomain

=cut

has 'pagerduty_subdomain' => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

=head2 pagerduty_service_key

=cut

has 'pagerduty_service_key' => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

=head2 pagerduty

=cut

has 'pagerduty' => (
    is  => 'rw',
    isa => 'WebService::PagerDuty',
);

=head1 SUBROUTINES/METHODS provided

=head2 configure

=cut

after 'configure' => sub {
    my ($self, $reconfig) = @_;

    $self->log("configuring PagerDuty plugin") if $self->debug;

    if (    ref($self->config->{api}) eq 'HASH'
        and ref($self->config->{api}->{pagerduty}) eq 'HASH')
    {
        foreach my $conf_key ('api_key', 'subdomain', 'service_key') {
            my $attr = "pagerduty_" . $conf_key;
            $self->$attr($self->config->{api}->{pagerduty}->{$conf_key})
                if defined $self->config->{api}->{pagerduty}->{$conf_key};
        }
    }

    $self->pagerduty(
        WebService::PagerDuty->new(
            api_key   => $self->pagerduty_api_key,
            subdomain => $self->pagerduty_subdomain,
        ));

    return;
};

=head2 alert

shortcut for most common used case, to trigger an alert in pagerduty

=cut

sub alert {
    my ($self, $incident, $description, $details) = @_;

    unless (ref \$incident eq 'SCALAR'
        and $incident
        and ref \$description eq 'SCALAR'
        and $description)
    {
        carp 'missing or wrong type of mandatory arguments! '
            . 'usage: $d->alert("$incident", "$description", \%details)';
        return;
    }

    # $self->async and return;

    # force $details to be a hash
    unless (ref $details eq 'HASH') {
        $details = {};
    }

    # check if we have JobQueue stuff loaded and use it
    eval { exists $self->job->{message}->{meta}->{command} };
    unless ($@) {
        $details->{workflow} = $self->job->{message}->{data}->{command}
            if exists $self->job->{message}->{data}->{command};
        $details->{workflow} = $self->job->{message}->{meta}->{workflow}
            if exists $self->job->{message}->{meta}->{workflow};
    }

    my $service = join('.', $self->name, $incident);

    # graph that we had an incident if we can
    if ($self->can('graph')) {
        $self->graph("incidents.$service", 'error', 1, $description);
    }

    # and notify hipchat if we can
    if ($self->can('notify')) {
        $self->notify("$service: $description", delete $details->{room});
    }

    $self->pagerduty->event(
        service_key  => $self->pagerduty_service_key,
        incident_key => $incident,
        description  => $self->hostname . " $service: $description",
        details      => {%$details},
        )->trigger
        unless $self->debug;

    # exit; # async
    return;
}

1;
