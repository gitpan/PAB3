package PAB3::Session;
# =============================================================================
# Perl Application Builder
# Module: PAB3::Session
# Use "perldoc PAB3::Session" for documenation
# =============================================================================
use vars qw($VERSION $SID %_SESSION %Config $Auto_Start $SavePath);

$VERSION = '1.0.4';

use Digest::MD5 ();
use Storable ();
use Carp ();

use strict;
no strict 'refs';

require Exporter;
*import = \&Exporter::import;
our @EXPORT_OK = ();
our @EXPORT = qw($SID %_SESSION);
#our @EXPORT_FNC = qw(start destroy gc write);

BEGIN {
	if( ! $GLOBAL::MODPERL ) {
		$GLOBAL::MODPERL = 0;
		$GLOBAL::MODPERL = 2 if exists $ENV{'MOD_PERL_API_VERSION'}
			&& $ENV{'MOD_PERL_API_VERSION'} == 2;
		$GLOBAL::MODPERL = 1 if ! $GLOBAL::MODPERL && defined $modperl::VERSION
			&& $modperl::VERSION > 1 && $modperl::VERSION < 1.99;
	}
	if( $GLOBAL::MODPERL == 2 ) {
		require mod_perl2;
		require Apache2::Module;
		require Apache2::ServerUtil;
		require APR::Pool;
		require APR::Table;
	}
	elsif( $GLOBAL::MODPERL == 1 ) {
		require Apache;
		require Apache::Log;
	}
	if( $^O eq 'MSWin32' ) {
		$SavePath = Win32::GetLongPathName(
			$ENV{'TEMP'}
			# CSIDL_WINDOWS (0x0024)
			|| Win32::GetFolderPath( 0x0024 ) . "\\Temp"
		);
	}
	else {
		$SavePath = '/tmp';
	}
}

END {
	if( ! $GLOBAL::MODPERL ) {
		&cleanup;
	}
}

1;

sub _import {
	my $pkg = shift;
	my $callpkg = caller();
	if( $_[0] and $pkg eq __PACKAGE__ and $_[0] eq 'import' ) {
		*{$callpkg . '::import'} = \&import;
		return;
	}
	# export symbols
	*{$callpkg . '::SID'} = \${$pkg . '::SID'};
	*{$callpkg . '::_SESSION'} = \%{$pkg . '::_SESSION'};
	*{$callpkg . '::session_' . $_} = \&{$pkg . '::' . $_} foreach @EXPORT_FNC;
}

sub cleanup {
	&write();
	undef %_SESSION;
	undef $SID;
}

sub start {
	my( $hr, $file, $index, $len );
	$len = scalar( @_ );
	%Config = (
		'save_path' => $SavePath,
		'name' => 'PABSESSID',
		'gc_max_lifetime' => 1440,
		'gc_probality' => 1,
		'gc_divisor' => 100,
		'use_cookies' => 1,
		'use_only_cookies' => 0,
		'cookie_path' => '',
		'cookie_domain' => '',
		'cookie_lifetime' => 0,
		'cookie_secure' => 0,
	);
	for( $index = 0; $index < $len; $index += 2 ) {
		$Config{ $_[ $index ] } = $_[ $index + 1 ];
	}
	if( $GLOBAL::MODPERL == 2 ) {
    	my $r = Apache2::RequestUtil->request;
    	$r->pool->cleanup_register( \&cleanup );
    }
    elsif( $GLOBAL::MODPERL == 1 ) {
    	my $r = Apache->request;
    	$r->register_cleanup( \&cleanup );
	}
	elsif( $PAB3::CGI::VERSION ) {
		&PAB3::CGI::cleanup_register( \&cleanup );
	}
	%_SESSION = ();
	if( $Config{'gc_probality'} / $Config{'gc_divisor'}
		>= rand() * $Config{'gc_divisor'} + 1
	) {
		&gc();
	}
	if( $Config{'id'} ) {
		$SID = $Config{'id'};
	}
	elsif( $PAB3::CGI::VERSION ) {
		if( ! $Config{'use_only_cookies'}
			&& $PAB3::CGI::_REQUEST{$Config{'name'}}
		) {
			$SID = $PAB3::CGI::_REQUEST{$Config{'name'}};
		}
		elsif( $Config{'use_cookies'} ) {
			$SID = $PAB3::CGI::_COOKIE{$Config{'name'}};
		}
	}
	if( ! $SID ) {
		while( 1 ) {
			$SID = &Digest::MD5::md5_hex( $ENV{'REMOTE_ADDR'} . time . rand( time ) );
			$file = $Config{'save_path'} . '/pses_' . $SID;
			last if ! -e $file;
		}
	}
	if( $PAB3::CGI::VERSION && $Config{'use_cookies'} ) {
		&PAB3::CGI::setCookie(
			$Config{'name'},
			$SID,
			$Config{'cookie_lifetime'}
				? time + $Config{'cookie_lifetime'}
				: undef,
			$Config{'cookie_path'},
			$Config{'cookie_domain'},
			$Config{'cookie_secure'},
		) or return 0;
	}
	&read() or return 0;
	return 1;
}

sub read {
	my( $file, $data );
	$file = $Config{'save_path'} . '/pses_' . $SID;
	return 1 if ! -e $file;
	eval {
		local( $SIG{'__DIE__'}, $SIG{'__WARN__'} );
		$data = &Storable::lock_retrieve( $file );
	};
	if( $@ ) {
		&Carp::croak( $@ );
	}
	%_SESSION = %$data;
	return 1;
}

sub write {
	my( $file );
	return 1 if ! $SID;
	if( ! %_SESSION ) {
		return &destroy();
	}
	$file = $Config{'save_path'} . '/pses_' . $SID;
	eval {
		local( $SIG{'__DIE__'}, $SIG{'__WARN__'} );
		&Storable::lock_store( \%_SESSION, $file );
	};
	if( $@ ) {
		&Carp::croak( $@ );
	}
	chmod 0600, $file;
	return 1;
}

sub gc {
	my( @files, $mtime, $time );
	opendir( DIR, $Config{'save_path'} );
	@files = grep { /^pses_\w+/ } readdir( DIR );
	closedir( DIR );
	$time = time;
	foreach( @files ) {
		$mtime = ( stat( $Config{'save_path'} . '/' . $_ ) )[9];
		if( $time > $mtime + $Config{'gc_max_lifetime'} ) {
			unlink $Config{'save_path'} . '/' . $_;
		}
	}
	return 1;
}

sub destroy {
	my( $file );
	%_SESSION = ();
	return 1 if ! $SID;
	$file = $Config{'save_path'} . '/pses_' . $SID;
	unlink $file;
	if( -e $file ) {
		return 0;
	}
	$SID = undef;
	return 1;
}

__END__

=head1 NAME

PAB3::Session - PAB3 session handler

=head1 SYNOPSIS

with PAB3::CGI module

  use PAB3::CGI;
  use PAB3::Session;
  
  &PAB3::CGI::init();
  &PAB3::Session::start();

without PAB3::CGI module

  use PAB3::Session;
  
  &PAB3::Session::start(
      'id' => 'mysessionid'
  );

=head1 DESCRIPTION

PAB3::Session provides an interace to Session Handling Functions in PAB3.

=head1 EXAMPLE

  use PAB3::CGI;
  use PAB3::Session;
  use PAB3::Utils;
  
  &PAB3::Session::start();
  
  if( ! $_SESSION{'time_start'} ) {
      $_SESSION{'hits'} = 1;
      $_SESSION{'time_start'} = time;
      print "you are first time here.";
  }
  else {
      $_SESSION{'hits'} ++;
      print
          "you are here since ",
          &PAB3::Utils::strftime(
              '%h hours, %m min, %s sec',
              time - $_SESSION{'time_start'}
          )
      ;
  }

=head1 METHODS

=over 4

=item start ( [%ARG] )

start() creates a session or resumes the current one based on the current
session id that's being passed via a request, such as GET, POST, or a cookie.

Available arguments are:

  save_path       => path to save the session files
                     default is '/tmp'
  name            => name of the session id in %_REQUEST or %_COOKIE
                     default is PABSESSID
  id              => id of session if PAB3::CGI is not used
  use_cookies     => store session id in a cookie, default is TRUE
  use_only_cookie => use cookies only, default is FALSE
  cookie_path     => path on the server in which the cookie will be
                     available on, default is ''
  cookie_domain   => defines the domain that the cookie is available
                     default is ''
  cookie_lifetime => defines the time the cookie expires,
                     default is 0
  cookie_secure   => indicates that the cookie should only be
                     transmitted over a secure HTTPS connection,
                     default is FALSE
  gc_max_lifetime => specifies the number of seconds after which data
                     will be seen as 'garbage' and cleaned up
                     default 1440 (24 min)
  gc_probality    => gc_probability in conjunction with gc_divisor
                     is used to manage probability that the gc
                     (garbage collection) routine is started.
                     default is 1.
  gc_divisor      => gc_divisor coupled with gc_probability defines
                     the probability that the gc (garbage collection)
                     process is started on every session initialization.
                     The probability is calculated by using
                     gc_probability/gc_divisor, e.g. 1/100 means there
                     is a 1% chance that the GC process starts on each
                     request. gc_divisor defaults to 100.

Example:

  &PAB3::Session::start(
      'save_path'    => '/path/to/session/',
  );


=item write ()

Store session data.

write() is called internally at the END block or inside ModPerl as cleanup
callback at the end of each request. If you use PAB3::CGI, it will be
registered as callback by
L<PAB3::CGI::cleanup_register|PAB3::CGI/item_cleanup_register>.
In other environments, like PerlEx or FastCGI, that do not support cleanup
mechanism you need to call it by yourself.


=item destroy ()

Destroys all data registered to a session.

=item gc ()

Runs the session garbage collector.

=back

=head1 VARIABLES

=over

=item $SID

Contains the session id

=item %_SESSION

Store your session data in the %_SESSION hash.

=back

=head1 EXPORTS

By default the variables $SID and %_SESSION are exported.

=head1 AUTHORS

Christian Mueller <christian_at_hbr1.com>

=head1 COPYRIGHT

The PAB3::Session module is free software. You may distribute under
the terms of either the GNU General Public License or the Artistic
License, as specified in the Perl README file.

=cut
