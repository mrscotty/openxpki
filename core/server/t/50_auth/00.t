use strict;
use warnings;
use English;
use Template;
use Test::More;
use Cwd;

plan skip_all => 'No LDAP configured'; 

use utf8;
use Digest::MD5;
use Digest::SHA1;

use Net::LDAP;
use Net::LDAP::Util qw( ldap_error_text
		        ldap_error_name
		        ldap_error_desc
		    );
use File::Spec;

#--- detect DIRECTORY
my $test_directory = getcwd;
my $test_group           = '50_auth'; 

#--- we use the directory of this test group to borrow ldap-schema files
#    at the moment it is the same...	
my $auxiliary_test_group = '50_auth';
my $auxiliary_test_directory = File::Spec->catfile(
				    $test_directory,
				    't',
				    $auxiliary_test_group 
			       );
$test_directory = File::Spec->catfile($test_directory,'t',$test_group );

my $test_directory_certs   = File::Spec->catfile(
				$test_directory,
   				'ldap_certs',
				'',
		     ); 
my $test_directory_keys   = File::Spec->catfile(
				$test_directory,
    				'ldap_keys',
				'',
			     ); 

#------------------ ENUMERATE TASKS TO CALC TEST NUMBER
my @test_tasks = (
		    '1  check environment variables',
		    '2  check if ldap server is already running',
		    '3  create directories',
 		    '4  create keys and certs for TLS',
		    '5  create server configuration',
		    '6  launch ldap server',
		    '7  try connect to ldap server',
		    '8  try simple bind to ldap server',
		    '9  add the top node to ldap tree',
		    '10 add node o=Security for authentication',
		    '11 create semaphore file to enable server tests',
		);    
my $test_number = scalar @test_tasks;
plan tests =>  $test_number;


#------------------- $index will store the number of performed tests.
my $index=0;

diag "Ldap server initialization\n" if $ENV{VERBOSE};


#### START of SKIP block - we skip the rest if something goes wrong
##
SKIP: {


#### 1) CHECK ENVIRONMENT
if( not exists $ENV{OPENXPKI_LDAP_MODULE_PATH} or
    not exists $ENV{OPENXPKI_LDAP_DAEMON_PATH} )
{
    diag("\n No OPENXPKI_LDAP environment variables found," .
         "\n skipping ldap server related tests \n"
    );
    skip '',$test_number - $index;  	     
};

ok(1, "Looking for environment variables");
my $module_path    = $ENV{OPENXPKI_LDAP_MODULE_PATH};
my $daemon_path    = $ENV{OPENXPKI_LDAP_DAEMON_PATH};
$index++;

#### 2) CHECK IF LDAP SERVER IS ALREADY RUNNING ON LOCALHOST
##
my $noldap_check = Net::LDAP->new("localhost:60389");
if( defined $noldap_check ) {
    $noldap_check->unbind;
    diag("\n Some LDAP server is running!" . 
         "\n Stop it to run ldap sever tests..." .
	 "\n Test will launch it in a proper configuration\n" .
         "\n Skipping ldap server related tests \n"
    );
   skip '', $test_number - $index;  	     
};
ok(1, "Ldap server is not running");
$index++;

#### 3) CREATE DIRS
foreach my $dir (
    	    	    "ldap_db",
    	            "ldap_var",
 		    "ldap_keys",
 		    "ldap_certs",
		 ) {
    my $ldap_dir = File::Spec->catfile($test_directory, $dir);		 
    if ( not -d $ldap_dir ){
	system("mkdir -p $ldap_dir");
    };
    if (not -d $ldap_dir) {
        diag("\n Cannot create directory for ldap-server files $dir" . 
             "\n skipping ldap server related tests \n"
        );
	skip '', $test_number - $index;
    };
};
ok(1,"Creating directories for ldap server");
$index++;


#### 4) CREATE KEYS AND CERTS
my $crypto_gen  = File::Spec->catfile(
		    $test_directory,
 		    'create_certs.pl',
 		  );
require $crypto_gen;
ok(1,"Creating certificates for TLS connections");
$index++;


#### 5) CREATE LDAP-SERVER CONFIGURATION
my $test_directory_schema  = File::Spec->catfile(
					$auxiliary_test_directory,
    					'ldap_schema',
					'',
			     ); 
my $test_directory_var	   = File::Spec->catfile(
					$test_directory,
    					'ldap_var',
					'',
			     ); 
my $test_directory_db	   = File::Spec->catfile(
					$test_directory,
    					'ldap_db',
			     ); 
my $tt_path      	   = File::Spec->catfile(
					$test_directory,
    					'ldap_conf',
			     );
my $tt_processor = Template->new( 
				  INCLUDE_PATH => $tt_path,
			           OUTPUT_PATH => $tt_path,
	           );
my $slapd_template = 'test_slapd_conf.template';
my $slapd_config   = 'slapd.conf';
my %slapd_data 	   = ( 
			'test_directory_certs'  => $test_directory_certs,
			'test_directory_keys'   => $test_directory_keys,
			'test_directory_schema' => $test_directory_schema,
			'test_directory_var'    => $test_directory_var,
			'test_directory_db'     => $test_directory_db,
        		'module_path'           => $module_path,
		     );
if( !$tt_processor->process( $slapd_template, \%slapd_data, $slapd_config) ) {
    diag("Cannot create ldap server configuration" .
         "\n skipping ldap server related tests \n"
    );
    skip '', $test_number - $index;    
};
$slapd_config   = File::Spec->catfile($test_directory,
    					'ldap_conf',
					$slapd_config,
		  );
ok(1,"Creating ldap server configuration");
$index++;

#### 6) START SERVER
my ($pwname) = getpwuid($EUID);
my ($grname) = getgrgid($EUID);

my $ldap_starter = 
    $daemon_path . " -f " . $slapd_config . 
		   " -u $pwname "         . 
		   " -g $grname "         .
		   ' -h "ldap://127.0.0.1:60389/ ldaps://127.0.0.1:60636/"'  ;
my $fail_to_start = system("$ldap_starter");
if( $fail_to_start  ) {
    diag("Could not start LDAP server" .
         "\n skipping ldap server related tests \n"
    );
    skip '', $test_number - $index;
};
ok(1, "Starting LDAP server");
$index++;

#### 7) CONNECT TO STARTED SERVER
my $testldap = Net::LDAP->new("localhost:60389");
if( !defined $testldap) {
   diag("Cannot connect to running server (strange), check logs..." .
         "\n skipping ldap server related tests \n"
   );
   skip '', $test_number - $index;
};	

ok(1,"Connect to LDAP server");
$index++;

#### 8) SIMPLE BIND TO LDAP SERVER 
my $msg = $testldap->bind ("cn=Manager,dc=OpenXPKI,dc=org",
                        	password => "secret",
                        	version => 3 );
if ( $msg->is_error()) {
    my $strange_error = "\nCODE => " . $msg->code() . 
    		       "\nERROR => " . $msg->error() .
	                "\nNAME => " . ldap_error_name($msg) .
                        "\nTEXT => " . ldap_error_text($msg) .
                 "\nDESCRIPTION => " . ldap_error_desc($msg) . "\n";
    diag("Cannot bind to running server (strange), check logs..." .
         "\n skipping ldap server related tests \n"
    );
    if( $ENV{DEBUG} ) {
        diag($strange_error);
    };
    skip '', $test_number - $index;
};

ok(1,"Simple bind to LDAP server");
$index++;

#### 9) ADDING TOP NODE
$msg = $testldap->add( 'dc=OpenXPKI,dc=org',
                	    attr => [  'o'   => 'OpenXPKI',
                    		      'dc'   => 'OpenXPKI',
                    	       'objectclass' => [
				    'top', 
		            	    'organization',
				    'dcObject',
			       ],
			    ],
	);
if ( $msg->is_error() ) {
    my $strange_error =    "\n CODE => " . $msg->code() . 
    	    		   "\nERROR => " . $msg->error() .
    	                    "\nNAME => " . ldap_error_name($msg) .
                    	    "\nTEXT => " . ldap_error_text($msg) .
                     "\nDESCRIPTION => " . ldap_error_desc($msg);
    diag("Cannot work with running server (strange), check logs..." . 
         "\n skipping ldap server related tests \n"
    );
    if( $ENV{DEBUG} ) {
        diag($strange_error);
    };
    skip '', $test_number - $index;
};

ok(1,"Add top node to LDAP server");
$index++;

#### 10) ADDING NODE o=Security FOR AUTHENTICATION
## Here we create one additional node to test LDAP authentication method
my $entry_dn    = 'o=Security,dc=openxpki,dc=org'; 
my $entry_array =  [
		              'o' => 'Security',
                    'objectclass' => [ 
			    'organization',
 	                ],
		   ];     
$msg = $testldap->add( $entry_dn, attr => $entry_array);
if ( $msg->is_error() ) {
    my $strange_error =    "\n CODE => " . $msg->code() . 
    	    		   "\nERROR => " . $msg->error() .
    	                    "\nNAME => " . ldap_error_name($msg) .
                    	    "\nTEXT => " . ldap_error_text($msg) .
                     "\nDESCRIPTION => " . ldap_error_desc($msg);
    diag("Cannot work with running server (strange), check logs..." . 
         "\n skipping ldap server related tests \n"
    );
    if( $ENV{DEBUG} ) {
        diag($strange_error);
    };
    skip '', $test_number - $index;
};

ok(1,"Add additional node for authentication");
$index++;

$testldap->unbind;

#### 11) CREATING SEMAPHORE FILE 
my $semaphore_file = File::Spec->catfile($test_directory,
                                         'enable_talk_to_server',
		     );
open(MYSEMAPHORE,">",$semaphore_file);
print MYSEMAPHORE 'OPENXPKILDAPTEST';
close(MYSEMAPHORE);
ok ( -f $semaphore_file ,"LDAP server tests enabled");

};  
#----- end of SKIP BLOCK

