use strict;
use warnings;
use 5.006;

package Test::Reporter::HTTPGateway;

=head1 NAME

Test::Reporter::HTTPGateway - relay CPAN Testers reports received via HTTP

=head1 DESCRIPTION

The CPAN Testers report submission system is difficult for some clients to use,
because it is not available via HTTP, which is often one of the only protocols
allowed through firewalls.

Test::Reporter::HTTPGateway is a very simple HTTP request handler that relays
HTTP requests to the CPAN Testers.

=cut

use CGI ();
use Email::Send ();
use Email::Simple;
use Email::Simple::Creator;

our $VERSION = '0.001';

=head1 METHODS

=head2 mailer

=head2 default_mailer

The C<mailer> method returns the Email::Send mailer to use.  If no
C<TEST_REPORTER_HTTPGATEWAY_MAILER> environment variable is set, it falls back
to the result of the C<default_mailer> method, which defaults to SMTP.

=cut

sub default_mailer { 'SMTP' }
sub mailer { $ENV{TEST_REPORTER_HTTPGATEWAY_MAILER} || $_[0]->default_mailer }

=head2 destination

=head2 default_destination

These act like the mailer methods, above.  The default destination is the
cpan-testers address.

=cut

sub default_destination { 'cpan-testers@perl.org' }

sub destination {
  $ENV{TEST_REPORTER_HTTPGATEWAY_ADDRESS} || $_[0]->default_destination;
}

=head2 key_allowed

  if ($gateway->key_allowed($key)) { ... }

This method returns true if the user key given in the HTTP request is
acceptable for posting a report.

Users wishing to operate a secure gateway should override this method.

=cut

sub key_allowed { 1 };

=head2 handle

This method handles a request to post a report.  It may be handed a CGI
request, and will instantiate a new one if none is given.

The request is expected to be a POST request with the following form values:

  from    - the email address of the user filing the report
  key     - the user key of the user filing the report
  subject - the subject of the report (generated by Test::Reporter)
  via     - the generator of the test report
  report  - the content of the report itself (the "comments")

In general, these reports will be filed by Test::Reporter or CPAN::Reporter.

=cut

sub handle {
  my ($self, $q) = @_;
  $q ||= CGI->new;

  my %post = (
    from    => scalar $q->param('from'),
    subject => scalar $q->param('subject'),
    via     => scalar $q->param('via'),
    report  => scalar $q->param('report'),
    key     => scalar $q->param('key'),
  );

  eval {
    # This was causing "cgi died ?" under lighttpd.  Eh. -- rjbs, 2008-04-05
    # die [ 405 => undef ] unless $q->request_method eq 'POST';

    for (qw(from subject via report)) {
      die [ 500 => "missing $_ field" ]
        unless defined $post{$_} and length $post{$_};

      next if $_ eq 'report';
      die [ 500 => "invalid $_ field" ] if $post{$_} =~ /[\r\n]/;
    }

    die [ 403 => "unknown user key" ] unless $self->key_allowed($post{key});

    my $via = $self->via;

    my $email = Email::Simple->create(
      body   => $post{report},
      header => [
        To      => $self->destination,
        From    => $post{from},
        Subject => $post{subject},
        'X-Reported-Via' => "$via $VERSION relayed from $post{via}",
      ],
    );

    my $rv = Email::Send->new({ mailer => $self->mailer })->send($email);
    die "$rv" unless $rv; # I hate you, Return::Value -- rjbs, 2008-04-05
  };

  if (my $error = $@) {
    my ($status, $msg);

    if (ref $error eq 'ARRAY') {
      ($status, $msg) = @$error;
    } else {
      warn $error;
    }

    $status = 500 unless $status and $status =~ /\A\d{3}\z/;
    $msg  ||= 'internal error';

    $self->_respond($status, "Report not sent: $msg");
    return;
  } else {
    $self->_respond(200, 'Report sent.');
    return;
  }
}

sub _respond {
  my ($self, $code, $msg) = @_;

  print "Status: $code\n";
  print "Content-type: text/plain\n\n";
  print "$msg\n";
}

=head2 via

This method returns the name to be used when identifying relay.  By default it
returns the relay's class.

=cut

sub via {
  my ($self) = @_;
  return ref $self ? ref $self : $self;
}

=head1 COPYRIGHT AND AUTHOR

This distribution was written by Ricardo Signes, E<lt>rjbs@cpan.orgE<gt>.

Copyright 2008.  This is free software, released under the same terms as perl
itself.

=cut

1;
