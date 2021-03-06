# OpenXPKI::Server::Workflow::Activity::SCEPv2::EvaluateSignerTrust
# Written by Scott Hardin for the OpenXPKI Project 2012
# Copyright (c) 2012 by The OpenXPKI Project

package OpenXPKI::Server::Workflow::Activity::SCEPv2::EvaluateSignerTrust;

=head1 NAME

OpenXPKI::Server::Workflow::Activity::SCEPv2::EvaluateSignerTrust

=head1 SYNOPSIS

    <action name="do_something">
        <condition name="scep_signer_trusted"
            class="OpenXPKI::Server::Workflow::Activity::SCEPv2::EvaluateSignerTrust">
        </condition>
    </action>

=head1 DESCRIPTION

Evaluate the trust status of the signer. The result are two status flags,
I<signer_trusted> if the certificate can be validated using the PKI 
(complete chain available and not revoked) and I<signer_on_behalf>
if the signer is authorized to perform request on behalf.
If the chain can not be validated, the authorization check is skipped. 

=head1 Configuration

The check for authorization uses a list of rules configured at 
I<scep.$server.authorized_signer_on_behalf>. 
The list is a hash of hashes, were each entry is a combination of one or more 
matching rules. The name of the rule is just used for logging purpose:

  rule1:
    subject: CN=scep-signer.*,dc=OpenXPKI,dc=org
    identifier: AhElV5GzgFhKalmF_yQq-b1TnWg
    profile: I18N_OPENXPKI_PROFILE_SCEP_SIGNER    

The subject is evaluated as a regexp, therefore any characters with a special meaning in 
perl regexp need to be escaped! Identifier and profile are matched as is. The rules in one
entry are ANDed together. If you want to provide alternatives, add multiple list items.

=cut

use strict;
use warnings;

use base qw( OpenXPKI::Server::Workflow::Activity );
use OpenXPKI::Server::Context qw( CTX );
use OpenXPKI::Debug;
use OpenXPKI::Exception;
use English;

sub execute {
    ##! 16: 'start'
    my ( $self, $workflow ) = @_;

    my $context = $workflow->context();
    my $config = CTX('config');
    my $server = $context->param('server');

    my $default_token = CTX('api')->get_default_token();
    
    my $signer_cert = $context->param('signer_cert'); 
    my $x509 = OpenXPKI::Crypto::X509->new(
        DATA  => $signer_cert,        
        TOKEN => $default_token
    );       
       
    # Check the chain       
    my $cert_identifier = $x509->get_identifier();    
    my $i = 10; # Max Chain Depth - TODO Trusthandling / configuration
    my $cert_db;    
    do {
        $cert_db = CTX('dbi_backend')->first(
            TABLE    => 'CERTIFICATE',
            COLUMNS  => ['ISSUER_IDENTIFIER','PKI_REALM'],
            DYNAMIC  => {
                'IDENTIFIER' => {VALUE => $cert_identifier},
                'STATUS'     => {VALUE => 'ISSUED'},
            }            
        );
        if (!$cert_db || $i-- < 0) {
            $context->param('signer_trusted' => 0);
            $context->param('signer_on_behalf' => 0);                        
            return 1;
        }        
        $cert_identifier = $cert_db->{'ISSUER_IDENTIFIER'};        
    } while($cert_db->{PKI_REALM});
    
    # TODO: Trusthandling
    
    CTX('log')->log(
        MESSAGE => "SCEP Signer validated - trusted root is $cert_identifier", 
        PRIORITY => 'info',
        FACILITY => ['audit','system']
    );       
    
    $context->param('signer_trusted' => 1);

    # End chain validation, now check the authorization

    my $signer_subject = $x509->get_parsed('BODY', 'SUBJECT');
    my $signer_identifier = $x509->get_identifier();
    ##! 32: 'Check signer '.$signer_subject.' against trustlist' 
    
    my @rules = $config->get_keys("scep.$server.authorized_signer_on_behalf");
    
    my $matched = 0;
    
    TRUST_RULE:
    foreach my $rule (@rules) {        
        my $trustrule = $config->get_hash("scep.$server.authorized_signer_on_behalf.$rule");
        $matched = 0;
        foreach my $key (keys %{$trustrule}) {
            my $match = $trustrule->{$key};
            if ($key eq 'subject') {            
                ##! 64: 'Check subject rule '.$rule 
                $matched = ($signer_subject =~ /^$match$/i);
            } elsif ($key eq 'identifier') {
                ##! 64: 'Check identifier '.$rule 
                $matched = ($signer_identifier eq $match);  
            #} elsif ($key eq 'profile') {
            # TODO - implement!                    
                
            } else {                
                CTX('log')->log(
                    MESSAGE => "SCEP Signer Authorization unknown ruleset $key:$match",
                    PRIORITY => 'error',
                    FACILITY => 'system',
                );
                $matched = 0;
            }
            next TRUST_RULE if (!$matched);

            ##! 32: 'Matched '.$match
        }
        
        if ($matched) {
            ##! 16: 'Passed validation rule #'.$rule,
            CTX('log')->log(
                MESSAGE => "SCEP Signer Authorization matched rule $rule",
                PRIORITY => 'info',
                FACILITY => ['audit','system'],
            );            
            $context->param('signer_on_behalf' => 1);
            return 1;
        }       
    }
     
    CTX('log')->log(
        MESSAGE => "SCEP Signer not found in trust list.",
        PRIORITY => 'info',
        FACILITY => ['system','audit']
    );

    $context->param('signer_on_behalf' => 0);
    return 1;
}

1;
