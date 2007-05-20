package PAB3::System;
# =============================================================================
# Perl Application Builder
# Module: PAB3::System
# System functions for PAB, please do not use directly
# =============================================================================

use vars qw($VERSION);

use Carp ();

BEGIN {
	$VERSION = $PAB3::VERSION;
	if( ! $PAB3::VERSION ) {
		&Carp::croak( '>> Please do not use PAB3::System directly, use PAB3 instead <<' );
	}
}

package PAB3;

use strict;
no strict 'refs';
use warnings;
no warnings 'redefine';

use Symbol ();

use vars qw(%RequireCache $PAB_LOGGER $FILENAME);

BEGIN {
	%RequireCache = ();
	if( ! $PAB3::CGI::VERSION ) {
		$SIG{'__DIE__'} = \&_die_handler;
		$SIG{'__WARN__'} = \&_warn_handler;
	}
}

sub require {
	my $this = shift if ref( $_[0] ) eq 'PAB3';
	my( $file, $package, $inject_code, $args ) = @_;
	my( $fid, $mtime, $cache, $content, $fh, $fs );
	$package ||= ( caller )[0];
	$fid = $file . '_' . $package;
	$fid =~ s/\W/_/go;
	if( $package eq $fid ) {
		die "Script requires itself";
	}
	$mtime = ( stat( $file ) )[9];
	$cache = $RequireCache{ $fid };
	if( ! $cache || $cache != $mtime ) {
		if( $cache ) {
			if( $this && $this->[$PAB_LOGGER] ) {
				$this->[$PAB_LOGGER]->debug( "Unloading PAB3::SC::${fid}" );
			}
			&Symbol::delete_package( "PAB3::SC::${fid}" );
		}
		if( $this && $this->[$PAB_LOGGER] ) {
			$this->[$PAB_LOGGER]->debug( "Compile $file" );
		}
		$fs = ( stat( $file ) )[7];
		open( $fh, $file ) or &Carp::croak( "Unable to open '$file': $!" );
		flock( $fh, 2 );
		read( $fh, $content, $fs );
		flock( $fh, 8 );
		close( $fh );
		&_create_script_cache( \$content, $fid, $package, $file, $inject_code );
		$RequireCache{ $fid } = $mtime;
		if( $this && $this->[$PAB_LOGGER] ) {
			$this->[$PAB_LOGGER]->debug( "Run PAB3::SC::${fid}::handler" );
		}
		my $of = $0;
		$FILENAME = $file;
		*0 = \$FILENAME;
		&{"PAB3::SC::${fid}::handler"}( ref( $args ) eq 'ARRAY' ? @$args : $args );
		$FILENAME = $of;
		*0 = \$FILENAME;
		return 1;
	}
	return 1;
}

sub require_and_run {
	my $this = shift if ref( $_[0] ) eq 'PAB3';
	my( $file, $package, $inject_code, $args ) = @_;
	my( $fid, $mtime, $cache, $content, $fh, $fs, $of );
	$package ||= ( caller )[0];
	$fid = $file . '_' . $package;
	$fid =~ s/\W/_/go;
	if( $package eq $fid ) {
		&Carp::croak( "Script requires itself" );
	}
	$mtime = ( stat( $file ) )[9];
	$cache = $RequireCache{ $fid };
	if( ! $cache || $cache != $mtime ) {
		if( $cache ) {
			if( $this && $this->[$PAB_LOGGER] ) {
				$this->[$PAB_LOGGER]->debug( "Unloading PAB3::SC::${fid}" );
			}
			&Symbol::delete_package( "PAB3::SC::${fid}" );
		}
		if( $this && $this->[$PAB_LOGGER] ) {
			$this->[$PAB_LOGGER]->debug( "Compile $file" );
		}
		$fs = ( stat( $file ) )[7];
		open( $fh, $file ) or &Carp::croak( "Unable to open '$file': $!" );
		flock( $fh, 2 );
		read( $fh, $content, $fs );
		flock( $fh, 8 );
		close( $fh );
		&_create_script_cache( \$content, $fid, $package, $file, $inject_code );
		$RequireCache{ $fid } = $mtime;
	}
	if( $this && $this->[$PAB_LOGGER] ) {
		$this->[$PAB_LOGGER]->debug( "Run PAB3::SC::${fid}::handler" );
	}
	$of = $0;
	*0 = \$file;
	&{"PAB3::SC::${fid}::handler"}( ref( $args ) eq 'ARRAY' ? @$args : $args );
	*0 = \$of;
	return 1;
}

sub _create_script_cache {
	my( $content, $pkg_require, $pkg_caller, $filename, $inject_code ) = @_;
	my( $hr, $data, $end );
	if( ref( $content ) ) {
		$content = $$content;
	}
	$content =~ s!\r!!gso;
	if( $content =~ s/(\n__DATA__\n.*$)//s ) {
		$data = $1;
	}
	else {
		$data = '';
	}
	if( $content =~ s/(\n__END__\n.*$)//s ) {
		$end = $1;
	}
	else {
		$end = '';
	}
	$filename ||= $0;
	$inject_code ||= '';
	$content = <<EORAR01;
package PAB3::SC::$pkg_require;
our \$VERSION = 1;
*handler = sub {
package $pkg_caller;
$inject_code
#line 1 $filename
$content
};
1;
$data
$end
EORAR01
	if( $GLOBAL::DEBUG ) {
		$PAB3::CGI::VERSION
			? &PAB3::CGI::print_code( $content, $filename )
			: &PAB3::print_code( $content, $filename )
		;
	}	
    {
        no strict;
        no warnings FATAL => 'all';
        local( $SIG{'__DIE__'}, $SIG{'__WARN__'} );
        eval $content;
    }
	if( $@ ) {
		if( ! $GLOBAL::DEBUG ) {
			$PAB3::CGI::VERSION
				? &PAB3::CGI::print_code( $content, $filename )
				: &PAB3::print_code( $content, $filename )
			;
		}
		&Carp::croak( $@ );
	};
}

sub print_code {
	my( $t, $l, $p );
	foreach $t( @_ ) {
		$t =~ s!\r!!gso;
		if( defined $t ) {
			print "\n";
			$p = 1;
			foreach $l( split( /\n/, $t ) ) {
				print $p . "\t" . $l . "\n";
				$p ++;
			}
			print "\n";
		}
	}
}

sub _die_handler {
	my $str = shift;
	my( @c, $step );
	print "\nFatal: $str\n\n";
	@c = caller();
	print $c[0] . ' raised the exception at ' . $c[1] . ' line ' . $c[2] . "\n";
	$step = 1;
	while( @c = caller( $step ) ) {
		print $c[0] . ' called ' . $c[3] . ' at ' . $c[1] . ' line ' . $c[2] . "\n";
		$step ++;
	}
	print "\n";
	exit( 0 );
}

sub _warn_handler {
	my $str = shift;
	print "\nWarning: $str\n";
}

1;

__END__

sub find_package {
	my( $this, $package ) = @_;
	my( $i );
	$package =~ s!\:\:!\/!g;
	$package = '/' . $package . '.pm';
	for $i( 0 .. $#INC ) {
		if( -f $INC[$i] . $package ) {
			return $INC[$i] . $package;
		}
	}
	return undef;
}

