package PAB3::HashMapCache;
# =============================================================================
# Perl Application Builder
# Module: PAB3::HashMapCache
# Use "perldoc PAB3::HashMapCache" for documentation
# =============================================================================
use strict;
no strict 'subs';
no strict 'refs';
use warnings;

use Storable ();
use Carp ();

use vars qw($VERSION $MODPERL);

our $HMC_DATA			= 0;
our $HMC_PATH_CACHE		= 1;
our $HMC_CACHE_FILE		= 2;
our $HMC_CACHE_FILE_MT	= 3;
our $HMC_DATA_CHANGED	= 4;
our $HMC_LOGGER			= 5;
our $HMC_CLEANUP		= 6;

BEGIN {
	$VERSION = '2.0.0';
	$MODPERL = 0;
	$MODPERL = 2 if exists $ENV{'MOD_PERL_API_VERSION'}
		&& $ENV{'MOD_PERL_API_VERSION'} == 2;
	$MODPERL = 1 if ! $MODPERL && exists $ENV{'MOD_PERL'}
		&& $Apache::VERSION > 1 && $Apache::VERSION < 1.99;
	if( $MODPERL == 2 ) {
		require mod_perl2;
		require Apache2::Module;
		require Apache2::ServerUtil;
	}
	elsif( $MODPERL == 1 ) {
		require Apache;
	}
}

1;

sub DESTROY {
	local( $SIG{'__DIE__'}, $SIG{'__WARN__'} );
	my $this = shift;
	$this->save();
}

sub new {
	my $proto = shift;
	my $class = ref( $proto ) || $proto;
	my $this  = [];
	bless( $this, $class );
	$this->[$HMC_CACHE_FILE_MT] = 0;
	$this->[$HMC_DATA_CHANGED] = 0;
	$this->[$HMC_DATA] = {};
	if( $^O eq 'MSWin32' ) {
		$this->[$HMC_PATH_CACHE] = $ENV{'TEMP'} . "\\"
			# CSIDL_WINDOWS (0x0024)
			|| Win32::GetLongPathName( Win32::GetFolderPath( 0x0024 ) ) . "\\Temp\\"
		;
	}
	else {
		$this->[$HMC_PATH_CACHE] = '/tmp/';
	}
	$this->[$HMC_CACHE_FILE] = unpack( '%32C*', $0 ) . '.hashmap.cache';
	$this->init( @_ );
	return $this;
}

sub cleanup {
	my $this = shift;
	$this->save( 1 );
	$this->[$HMC_CLEANUP] = 0;
}

sub init {
	my( $this ) = @_;
	my( $i, $l, $tmp );
	$l = $#_;
	$i = 0;
	while( $i <= $l ) {
		if( $_[$i] eq 'path_cache' ) {
			$tmp = $_[$i += 1];
			$tmp .= '/' if $tmp && substr( $tmp, -1 ) ne '/';
			$this->[$HMC_PATH_CACHE] = $tmp;
		}
		elsif( $_[$i] eq 'cache_file' ) {
			$this->[$HMC_CACHE_FILE] = $_[$i += 1];
		}
		elsif( $_[$i] eq 'logger' ) {
			$this->[$HMC_LOGGER] = $_[$i += 1];
		}
		$i ++;
	}
	if( ! $this->[$HMC_CLEANUP] ) {
		if( $MODPERL == 2 ) {
	    	my $r = Apache2::RequestUtil->request;
	    	$r->pool->cleanup_register( \&cleanup, $this );
	    }
		elsif( $MODPERL == 1 ) {
	    	my $r = Apache->request;
	    	$r->register_cleanup( sub { &cleanup( $this ); } );
	    }
	    elsif( $PAB3::CGI::VERSION ) {
    		&PAB3::CGI::cleanup_register( \&cleanup, $this );
    	}
		$this->[$HMC_CLEANUP] = 1;
    }
	if( -e $this->[$HMC_PATH_CACHE] . $this->[$HMC_CACHE_FILE] ) {
		return $this->load();
	}
	return 1;
}

sub get {
	my $this = shift;
	#my( $loop, $hashname, $fm ) = @_;
	my( $id );
	$id = $_[0] . '_' . $_[1];
	if( $this->[$HMC_DATA]->{$id} ) {
		if( $_[2] && %{$_[2]} ) {
			if( join( '', keys %{ $_[2] } )
				ne join( '', keys %{ $this->[$HMC_DATA]->{$id} } )
			) {
				return undef;
			}
		}
		return $this->[$HMC_DATA]->{$id};
	}
	return undef;
}

sub set {
	my $this = shift;
	#my( $loop, $hashname, $hashmap );
	my( $id );
	$id = $_[0] . '_' . $_[1];
	$this->[$HMC_DATA]->{$id} = $_[2];
	$this->[$HMC_DATA_CHANGED] = 1;
	return 1;
}

sub load {
	my $this = shift;
	my( $file, $mtime, $data );
	$file = $this->[$HMC_PATH_CACHE] . $this->[$HMC_CACHE_FILE];
	return 1 if ! -e $file;
	$mtime = ( stat( $file ) )[9];
	return 1 if $mtime == $this->[$HMC_CACHE_FILE_MT];
	if( $this->[$HMC_LOGGER] ) {
		$this->[$HMC_LOGGER]->debug( "Load hashmap cache from $file" );
	}
	eval {
		local( $SIG{'__DIE__'}, $SIG{'__WARN__'} );
		$data = &Storable::lock_retrieve( $file );
	};
	if( $@ ) {
		&Carp::carp( "Could not load hashmap file: $@" );
		return 0;		
	}
	$this->[$HMC_DATA] = $data;
	$this->[$HMC_CACHE_FILE_MT] = $mtime;
	$this->[$HMC_DATA_CHANGED] = 0;
	return 1;
}

sub save {
	my $this = shift;
	my( $file, $mtime, $data );
	$file = $this->[$HMC_PATH_CACHE] . $this->[$HMC_CACHE_FILE];
	return 1 if ! $this->[$HMC_DATA_CHANGED] && -e $file;
	if( $this->[$HMC_LOGGER] ) {
		$this->[$HMC_LOGGER]->debug( "Save hashmap cache to $file" );
	}
	eval {
		local( $SIG{'__DIE__'}, $SIG{'__WARN__'} );
		&Storable::lock_store( $this->[$HMC_DATA], $file );
	};
	if( $@ ) {
		&Carp::carp( "Could not save hashmap file: $@" );
	}
	chmod 0664, $file;
	$this->[$HMC_CACHE_FILE_MT] = ( stat( $file ) )[9];
	$this->[$HMC_DATA_CHANGED] = 0;
	return 1;
}


__END__

=head1 NAME

PAB3::HashMapCache - Cache handler for hashmaps in PAB

=head1 SYNOPSIS

  use PAB3;
  use PAB3::HashMapCache;
  
  $pab = PAB3->new(
      'hashmap_cache' => PAB3::HashMapCache->new(),
  );

=head1 DESCRIPTION

C<PAB3::HashMapCache> provides an interface to cache hashes that maps to arrays.
One time it is added to the PAB class, it will be internally used by it.

=head1 METHODS

=over

=item new ( [%arg] )

Creates a new class of PAB3::HashMapCache and loads the hashmap cache from file
if it exists.

posible arguments are:

  path_cache     => path to folder where cache can be saved
                    default value is "/tmp"
  cache_file     => the name of the cache file
                    default value is the crc32 of calling filename
                    plus '.hashmap.cache'

Example:

  $hmc = PAB3::HashMapCache->new(
      'path_cache'     => '/path/to/cache',
      'cache_file'     => 'hashmap.cache',
  );
  $pab = PAB3->new(
      'hashmap_cache'  =>  $hmc,
  );


See also L<PAB-E<gt>add_hashmap|PAB/item_add_hashmap>


=item load ()

Loads the hashmap cache from file. Is called internally by L<new()> or
L<PAB3-E<gt>reset|PAB3/item_reset>.


=item save ()

Write the hashmap cache to disk.

save() is called internally when the class gets destroyed or inside ModPerl as
cleanup callback at the end of each request. If you use PAB3::CGI, it will
be registered as callback by
L<PAB3::CGI::cleanup_register|PAB3::CGI/item_cleanup_register>.
In other environments, like PerlEx or FastCGI, that do not support cleanup
mechanism you need to call it by yourself.

=back

=head1 AUTHORS

Christian Mueller <christian_at_hbr1.com>

=head1 COPYRIGHT

The PAB3::HashMapCache module is free software. You may distribute under the
terms of either the GNU General Public License or the Artistic License, as
specified in the Perl README file.

=cut
