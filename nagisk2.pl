=pod

=head1 NAME

A modern plugin for checking asterisk

=head1 SYNOPSIS

    ./nagisk2.pl <cmd> [-args]

=head1 DESCRIPTION

This file aims to be a ready to use template for implementing various asterisk checks for usage in a nagios-compatible
monitoring service.

=head1 EXAMPLES

    # check template
    sub check_your_method(@input_args){

        # the <cmd> is already stripped at this point and therefore your first arg has index 0
        my $input_arg_p = retrieve_arg(\@input_args, <index>, '-p');

        # connect to ami
        my $socket = connect_and_login();

        # prepare ami command
        my $ami_command = "Action: SomeAction\r\n\r\n";

        # send ami command
        my $result = run_ami_command($socket, $ami_command);

        # Your check logic with $result (string)
        ...

        # return statement
        return [OK|WARNING|CRITICAL|UNKNOWN], "Some helpful message";
    }

=head1 METHODS

=cut
#!/usr/bin/perl
use v5.22;
use strict;
use warnings FATAL => 'all';
use experimental 'signatures';

our $VERSION = '0.0.1';

use IO::Socket;
use Data::Dumper;


# you may change these
use constant R_PORT => 5038;
use constant IP_ADDR => 'localhost';
use constant AMI_USER => 'nagios';
use constant AMI_PASS => '<your_ami_password>';

# do not change anything below here
use constant OK => 0;
use constant WARNING => 1;
use constant CRITICAL => 2;
use constant UNKNOWN => 3;

my $state = UNKNOWN;
my $message = 'Unknown error';

# route input args
my ($cmd, @cmd_args) = @ARGV;
if (!defined $cmd) {
    show_help();
}

# add your command here
for ($cmd) {
    /^pjsip_outbound_registry$/ && do {
        ($state, $message) = check_pjsip_outbound_registry(@cmd_args);
        last;
    };
    /^help$/ && do {
        show_help();
    };
    # /^an_other_command$/ && do {
    #     ($state, $message) = check_other_command(@cmd_args);
    # };
    show_help();
}

sub show_help() {
    print "A modern nagios plugin for monitoring asterisk using AMI\n"
        . "Version: $VERSION, Tobias Bossert<tobias.bossert\@fastpath.ch\n"
        . "Usage: nagisk.pl <cmd> [cmd_args]\n"
        . "Possible cmds: \n"
        . "  pjsip_outbound_registry -p <trunk_name> #Checks a pjsip outbound trunk.\n"
        . "  help #Shows this help\n";
    exit UNKNOWN;
}

sub check_pjsip_outbound_registry(@input_args) {
    my $trunk_name = retrieve_arg(\@input_args, 0, '-p');
    my $socket = connect_and_login();
    my $ami_command = "Action: PJSIPShowRegistrationsOutbound\r\n\r\n";
    my $result = run_ami_command($socket, $ami_command);
    my $found = undef;
    for my $block (split "\r\n\r\n", $result) {
        my %block = parse_block($block);
        if (get_if_exist('ObjectType', \%block) eq 'registration' && get_if_exist('Endpoint', \%block) eq $trunk_name) {
            $found = 1;
            if (get_if_exist('Status', \%block) eq 'Registered') {
                return OK, "Registered at: " . get_if_exist('ServerUri', \%block);
            }
        }
    }
    if (defined $found) {
        return CRITICAL, "Outbound Trunk `$trunk_name` is not in state `Registered`";
    }
    return CRITICAL, "Outbound Trunk `$trunk_name` not found";
}

sub run_ami_command($socket, $command) {
    print $socket $command;
    return _read_from_socket($socket);
}

=head3 parse_block($block)

Parses an AMI I<event> block into a hash.

B<Parameters>

=over 1

=item

C<$block> An AMI I<event> in form of a string containing key:value-pairs and have C<\r\n> as newline characters.

=back

B<Returns>

A hash containing the key:value pairs

=cut
sub parse_block($block) {
    my %result;
    map {my ($key, $value) = _split_and_trim($_, ':');
        $result{$key} = $value;} split "\r\n", $block;
    return %result;
}

=head3 connect_and_login()

Tries to login to AMI using the settings provided at the beginning of this file.
If an error occurs, the program exits here with state C<UNKNOWN>.

B<Returns>

If login was successful, a L<IO::Socket::INET> instance;

=cut
#@returns IO::Socket::INET
sub connect_and_login() {
    my $socket = IO::Socket::INET->new(PeerAddr => IP_ADDR,
        PeerPort                                => R_PORT,
        Proto                                   => "tcp",
        Type                                    => IO::Socket::SOCK_STREAM)
        or do {
        $state = UNKNOWN;
        $message = "Couldn't connect to AMI using " . IP_ADDR . ":" . R_PORT;
        show_check_result();
    };

    my $login_str = "Action: Login\r\n"
        . "Username: " . AMI_USER . "\r\n"
        . "Secret: " . AMI_PASS . "\r\n"
        . "ActionId: 0001\r\n"
        . "\r\n";
    my $result = run_ami_command($socket, $login_str);
    if ($result =~ /Error/) {
        $state = UNKNOWN;
        $message = "Could not login to AMI with user: `" . AMI_USER . "`";
        close($socket);
        show_check_result();
    }
    return $socket;
}
=head3 retrieve_arg($ref_arg_list, $index, $parameter_name)

Tries to get the value for an commandline arg at index.

B<Parameters>

=over 1

=item

C<$ref_arg_list> Reference to the input arguments list

=item

C<$index> Expected position of arg

=item

C<$parameter_name> Expected parameter name (e.g '-p')

=back

B<Returns>

If the parameter name at C<$index> matches C<$parameter_name>, the value of C<$index+1> is returned.
Help is shown otherwise an the program exists with state unknown.

=cut
sub retrieve_arg($ref_arg_list, $index, $parameter_name) {
    my @args = @{$ref_arg_list};
    if ($index + 1 > @args) {
        die show_help();
    }
    if ($parameter_name eq $args[$index]) {
        return $args[$index + 1];
    }
    else {
        die show_help();
    }
}

sub get_if_exist($hash_key, $ref_hash) {
    my %hash = %{$ref_hash};
    if (exists($hash{$hash_key})) {
        return $hash{$hash_key};
    }
    else {
        return '';
    }
}

sub _read_from_socket($socket) {
    my $out;
    # sleep for one second to give asterisk some time to write the output..
    sleep 1;
    while (sysread $socket, my $buf, 4096) {
        $out .= $buf;
        last if ($buf =~ /\r\n\r\n\z/);
    }
    return $out;
}

sub _split_and_trim($line, $separator) {
    return map {s/^\s+|\s+$//g;
        $_} split $separator, $line, 2;
}

# this has to be at the end of this file!
sub show_check_result() {
    print $message;
    exit $state;
}
show_check_result();
