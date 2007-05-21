package PAB3;
# =============================================================================
# Perl Application Builder
# Module: PAB
# Please see bottom of file for documenation
# =============================================================================
use strict;
no strict 'refs';
use warnings;
no warnings 'uninitialized';

use vars qw($VERSION $_CURRENT);

BEGIN {
	$VERSION = '3.0.1';
}

use Carp ();
use PAB3::System ();

use constant {
	# pab types
	PAB_SCALAR			=> 1,
	PAB_ARRAY			=> 2,
	PAB_HASH			=> 3,
	PAB_FUNC			=> 4,
	PAB_OBJECT			=> 5,
};

# command control fields
our $FIELD_TYPE			= 0;
our $FIELD_PARENT		= 1;
our $FIELD_CHILD		= 2;
our $FIELD_CONTENT		= 3;
our $FIELD_LOOPID		= 3;
our $FIELD_LOOPA1		= 4;
our $FIELD_LOOPA2		= 5;

# command types
our $ITEM_TEXT			= 1;
our $ITEM_PRINT			= 2;
our $ITEM_DO			= 3;
our $ITEM_CON			= 4;
our $ITEM_ELCO			= 5;
our $ITEM_ELSE			= 6;
our $ITEM_ECON			= 7;
our $ITEM_LOOP			= 8;
our $ITEM_ASIS			= 9;
our $ITEM_SUB			= 10;
our $ITEM_COMMENT		= 11;

# loop control fields
our $LOOP_ID			= 0;
our $LOOP_SOURCE		= 1;
our $LOOP_SOURCETYPE	= 2;
our $LOOP_RECORD		= 3;
our $LOOP_RECORDTYPE	= 4;
our $LOOP_OBJECT		= 5;
our $LOOP_FNCARG		= 6;
our $LOOP_ISFIXED		= 7;

# hashmap control fields
our $HASHMAP_LOOPID		= 0;
our $HASHMAP_HASHNAME	= 1;
our $HASHMAP_MAP		= 2;

# pab class control fields
our $PAB_PRGSTART		= 0;
our $PAB_PRGSTARTLEN	= 1;
our $PAB_PRGEND			= 2;
our $PAB_PRGENDLEN		= 3;
our $PAB_CMDSEP			= 4;
our $PAB_DEFRECNAME		= 5;
our $PAB_PATHCACHE		= 6;
our $PAB_PATHTEMPLATE	= 7;
our $PAB_AUTOCACHE		= 8;
our $PAB_OBJECTNAME		= 9;
our $PAB_LOOPDEF		= 10;
our $PAB_HASHMAPDEF		= 11;
our $PAB_PARSED			= 13;
our $PAB_PARENTPARSED	= 14;
our $PAB_SCRIPTCOUNTER	= 15;
our $PAB_ERROR			= 16;
our $PAB_LOGGER			= 17;
our $PAB_HASHMAPCACHE	= 18;
our $PAB_CROAK			= 19;

our @EXPORT_OK = qw(PAB_SCALAR PAB_FUNC PAB_ARRAY PAB_HASH PAB_OBJECT);
our %EXPORT_TAGS = (
	'const' => \@EXPORT_OK,
);
require Exporter;
*import = \&Exporter::import;

1;

sub setenv {
	if( $0 =~ /^(.+\/)(.+?)$/ ) {
		$ENV{'SCRIPT_PATH'} = $1;
		$ENV{'SCRIPT'} = $2;
	}
	else {
		$ENV{'SCRIPT_PATH'} = '';
		$ENV{'SCRIPT'} = $0;
	}
}

sub new {
	my $proto = shift;
	my $class = ref( $proto ) || $proto;
	my $this  = [];
	bless( $this, $class );
	my %arg = @_;
	if( $arg{'prg_start'} ) {
		$this->[$PAB_PRGSTART] = $arg{'prg_start'};
		$this->[$PAB_PRGSTARTLEN] = length( $arg{'prg_start'} );
	}
	else {
		$this->[$PAB_PRGSTART] = '<*';
		$this->[$PAB_PRGSTARTLEN] = 2;
	}
	if( $arg{'prg_end'} ) {
		$this->[$PAB_PRGEND] = $arg{'prg_end'};
		$this->[$PAB_PRGENDLEN] = length( $arg{'prg_end'} );
	}
	else {
		$this->[$PAB_PRGEND] = '*>';
		$this->[$PAB_PRGENDLEN] = 2;
	}
	$this->[$PAB_CROAK] = 2;
	$this->[$PAB_CROAK] -= 2 if defined $arg{'die'} && ! $arg{'die'};
	$this->[$PAB_CROAK] += 1 if $arg{'warn'};
	$this->[$PAB_CMDSEP] = $arg{'cmd_sep'} || ';;';
	$this->[$PAB_PATHCACHE] = $arg{'path_cache'};
	$this->[$PAB_PATHTEMPLATE] = $arg{'path_template'};
	$this->[$PAB_AUTOCACHE] = defined $arg{'auto_cache'} ? $arg{'auto_cache'} : 1;
	$this->[$PAB_OBJECTNAME] = $arg{'class_name'} if $arg{'class_name'};
	$this->[$PAB_DEFRECNAME] = $arg{'record_name'} || '$_';
	$this->[$PAB_LOGGER] = $arg{'logger'};
	$this->[$PAB_HASHMAPCACHE] = $arg{'hashmap_cache'};
	$this->reset();
	return $this;
}

sub reset {
	my( $this ) = @_;
	$this->[$PAB_HASHMAPDEF] = [];
	$this->[$PAB_LOOPDEF] = {
		'ARRAY' => [ 'ARRAY', undef, 0, undef, 0, undef, undef, 1 ],
		'FOR' => [ 'ARRAY', undef, 0, undef, 0, undef, undef, 1 ],
		'HASH' => [ 'HASH', undef, 0, undef, 0, undef, undef, 1 ],
	};
	if( $this->[$PAB_HASHMAPCACHE] ) {
		$this->[$PAB_HASHMAPCACHE]->init();
	}
	return 1;
}

sub make_script {
	my( $this, $file, $cache, $package, $internal ) = @_;
	my( @sf, @sc, $content, $fh );
	if( ! $internal ) {
		$this->_get_filepath( $file, $cache );
	}
	@sf = stat( $file );
	if( $cache && -f $cache ) {
		@sc = stat( $cache );
		return 1 if $sf[9] == $sc[9];
	}
	if( $this->[$PAB_LOGGER] ) {
		$this->[$PAB_LOGGER]->debug( "Generate script from template $file" );
	}
	$this->[$PAB_PARSED] = [];
	$this->[$PAB_PARSED][$FIELD_CHILD] = [];
	$this->[$PAB_PARENTPARSED] = $this->[$PAB_PARSED];
	$this->_parse_file( $file ) or return 0;
	$this->_map_parsed( $this->[$PAB_PARSED] ) or return 0;
	$content = '';
	$this->_build_script( $this->[$PAB_PARSED], $content ) or return 0;
	if( $cache ) {
		$this->_optimize_script( $content ) or return 0;
		open( $fh, '> ' . $cache )
			or return $this->_set_error( "Unable to open '$cache': $!" );
		flock( $fh, 2 );
		print $fh $content;
		flock( $fh, 8 );
		close( $fh );
		utime $sf[9], $sf[9], $cache;
	}
	else {
		$package ||= ( caller )[0];
		$cache = $file;
		$cache =~ s/\W/_/go;
		&_create_script_cache( $content, $cache, $package );
	}
	undef $this->[$PAB_PARSED];
	undef $this->[$PAB_PARENTPARSED];
	return 1;
}

sub run_script {
	my( $this, $file, $cache, $package, $internal ) = @_;
	if( ! $internal ) {
		$this->_get_filepath( $file, $cache );
	}
	$_CURRENT = $this;
	if( $cache ) {
		$package ||= ( caller )[0];
		$this->require_and_run( $cache, $package );
	}
	else {
		$cache = $file;
		$cache =~ s/\W/_/go;
		my $of = $0;
		*0 = \$file;
		&{"PAB3::SC::${cache}::handler"}();
		*0 = \$of;
	}
	return 1;
}

sub make_script_and_run {
	my( $this, $file, $cache, $package ) = @_;
	$package ||= ( caller )[0];
	$this->_get_filepath( $file, $cache );
	$this->make_script( $file, $cache, $package, 1 ) or return 0;
	$this->run_script( $file, $cache, $package, 1 ) or return 0;
	return 1;
}

sub register_loop {
	my( $this, $id, $source, $s_type, $record, $r_type, $object, $arg, $fixed ) = @_;
	my $loop = $this->[$PAB_LOOPDEF]->{$id};
	if( $loop && $loop->[$LOOP_ISFIXED] ) {
		return $this->_set_error( 'Cannot overwrite loop definition of ' . $id );
	}
	$this->[$PAB_LOOPDEF]->{$id} = [
		$id, $source, $s_type, $record, $r_type, $object, $arg, $fixed
	];
	return 1;
}

sub add_hashmap {
	my( $this, $loopid, $hashname, $fieldmap, $tfm ) = @_;
	my( $fm, $s, $fmc );
	$hashname = $this->_var_str( $hashname, PAB_SCALAR );
	if( ref( $fieldmap ) eq 'ARRAY' ) {
		my $ifm = 0;
		$fm = {};
		foreach( @$fieldmap ) {
			$fm->{$_} = $ifm ++;
		}
	}
	else {
		$fm = $fieldmap;
	}
	if( $this->[$PAB_HASHMAPCACHE] ) {
		$fmc = $this->[$PAB_HASHMAPCACHE]->get( $loopid, $hashname, $fm );
	}
	if( ! $fm || ref( $fm ) ne 'HASH' || ! %$fm ) {
		if( $fmc ) {
			$fm = $fmc;
		}
		else {
			return $this->_set_error( 'Got an empty hashmap' );
		}
	}
	if( $this->[$PAB_HASHMAPCACHE] && ! $fmc ) {
		# hashmap changed, rebuild script?
		$this->[$PAB_HASHMAPCACHE]->set( $loopid, $hashname, $fm );
	}
	foreach( @{ $this->[$PAB_HASHMAPDEF] } ) {
		if( $_->[$HASHMAP_HASHNAME] eq $hashname ) {
			$_ = [ $loopid, $hashname, $fm ];
			return 1;
		}
	}
	push @{ $this->[$PAB_HASHMAPDEF] }, [ $loopid, $hashname, $fm ];
	$_[4] = $fm;
	return 1;
}

sub error {
	my( $this ) = @_;
	return $this->[$PAB_ERROR];
}

# internal functions

sub _set_error {
	my $this = shift;
	$this->[$PAB_ERROR] = $_[0];
	&Carp::croak( $_[0] ) if $this->[$PAB_CROAK] > 1;
	&Carp::carp( $_[0] ) if $this->[$PAB_CROAK] > 0;
	return 0;
}

sub _get_filepath {
	my( $this, $file, $cache ) = @_;
	if( $this->[$PAB_PATHCACHE] ) {
		if( $cache ) {
			$_[2] = $this->[$PAB_PATHCACHE] . $cache;
		}
		elsif( $this->[$PAB_AUTOCACHE] ) {
			$cache = '_auto.' . $file . '.pl';
			$cache =~ tr!/!.!;
			$cache =~ tr!\\!.!;
			$_[2] = $this->[$PAB_PATHCACHE] . $cache;
		}
	}
	if( $this->[$PAB_PATHTEMPLATE] ) {
		$_[1] = $this->[$PAB_PATHTEMPLATE] . $file;
	}
}

sub _var_str {
	my( $this, $str, $type ) = @_;
	$type ||= PAB_SCALAR;
	if( $type == PAB_SCALAR ) {
		return substr( $str, 0, 1 ) eq '$' ? $str : '$' . $str;
	}
	elsif( $type == PAB_ARRAY ) {
		my $ch = substr( $str, 0, 1 );
		return $ch eq '@' ? $str : $ch eq '$' ? '@{' . $str . '}' : '@' . $str;
	}
	elsif( $type == PAB_HASH ) {
		my $ch = substr( $str, 0, 1 );
		return $ch eq '%' ? $str : $ch eq '$' ? '%{' . $str . '}' : '%' . $str;
	}
	elsif( $type == PAB_FUNC ) {
		return substr( $str, 0, 1 ) eq '&' ? $str : '&' . $str;
	}
	return $str;
}

sub _build_script {
	my $this = shift;
	$this->[$PAB_SCRIPTCOUNTER] = 0;
	$_[1] .= "{\n";
	$this->_build_script_int( $_[0], $_[1], 1 ) or return 0;
	$_[1] .= "}\n\n1;\n";
	return 1;
}

sub _build_script_int {
	my $this = shift;
	#my( $parsed, $r_out, $level ) = @_;
	my( $loop, $item, $s, $r, $indent, $indent2, $indent3, $lpr, $lpa );
	$indent = "\t" x $_[2];
	$indent2 = "\t" x ( $_[2] + 1 );
	$indent3 = "\t" x ( $_[2] + 2 );
	foreach $item( @{ $_[0]->[$FIELD_CHILD] } ) {
		$this->[$PAB_SCRIPTCOUNTER] ++;
		if( $item->[$FIELD_TYPE] == $ITEM_TEXT ) {
			$s = $item->[$FIELD_CONTENT];
			if( $s ) {
				$s =~ s!\\!\\\\!gso;
				$s =~ s!\{!\\\{!gso;
				$s =~ s!\}!\\\}!gso;
				$s =~ s!\$!\\\$!gso;
				$s =~ s!\@!\\\@!gso;
				$s =~ s!\n!\\n!gso;
				$s =~ s!\n__END__\n!\n\\__END__\n!gso;
				$s =~ s!\n__DATA__\n!\n\\__DATA__\n!gso;
				$_[1] .=
					$indent . 'print qq{' .  $s . "};\n";
			}
		}
		elsif( $item->[$FIELD_TYPE] == $ITEM_PRINT ) {
			$_[1] .= $indent . 'print ' . $item->[$FIELD_CONTENT] . ";\n";
		}
		elsif( $item->[$FIELD_TYPE] == $ITEM_DO ) {
			$_[1] .= $indent . $item->[$FIELD_CONTENT] . ";\n";
		}
		elsif( $item->[$FIELD_TYPE] == $ITEM_ASIS ) {
			$_[1] .= $indent . $item->[$FIELD_CONTENT] . "\n";
		}
		elsif( $item->[$FIELD_TYPE] == $ITEM_CON ) {
			$_[1] .= $indent . 'if( ' . $item->[$FIELD_CONTENT] . " ) {\n";
			$this->_build_script_int( $item, $_[1], $_[2] + 1 ) or return 0;
		}
		elsif( $item->[$FIELD_TYPE] == $ITEM_ELCO ) {
			$_[1] .= $indent . "}\n";
			$_[1] .= $indent . 'elsif( ' . $item->[$FIELD_CONTENT] . " ) {\n";
			$this->_build_script_int( $item, $_[1], $_[2] + 1 ) or return 0;
		}
		elsif( $item->[$FIELD_TYPE] == $ITEM_ELSE ) {
			$_[1] .= $indent . "}\n";
			$_[1] .= $indent . "else {\n";
			$this->_build_script_int( $item, $_[1], $_[2] + 1 ) or return 0;
		}
		elsif( $item->[$FIELD_TYPE] == $ITEM_ECON ) {
			$_[1] .= $indent . "}\n";
		}
		elsif( $item->[$FIELD_TYPE] == $ITEM_LOOP ) {
			my $lid = $item->[$FIELD_LOOPID];
			if( $lid eq 'ARRAY' ) {
				# --> foreach $record( @array ) {
				if( ! $item->[$FIELD_LOOPA1] ) {
					return $this->_set_error( 'Usage <*LOOP ARRAY arrayname [recordname]*>' );
				}
				$s = $this->_var_str( $item->[$FIELD_LOOPA1], PAB_ARRAY );
				if( $item->[$FIELD_LOOPA2] ) {
					$r = $item->[$FIELD_LOOPA2];
				}
				else {
					$r = $this->[$PAB_DEFRECNAME];
				}
				$r = $this->_var_str( $r, PAB_SCALAR );
				$_[1] .= $indent
					. 'foreach ' . $r . '( ' . $s . ' ) {'
					. "\n"
				;
				$this->_build_script_int( $item, $_[1], $_[2] + 1 ) or return 0;
				$_[1] .= $indent . "}\n";
				next;
			}
			elsif( $lid eq 'HASH' ) {
				# --> foreach $record( keys %array ) {
				if( ! $item->[$FIELD_LOOPA1] ) {
					return $this->_set_error( 'Usage <*LOOP HASH hashname [recordname]*>' );
				}
				$s = $this->_var_str( $item->[$FIELD_LOOPA1], PAB_HASH );
				if( $item->[$FIELD_LOOPA2] ) {
					$r =  $item->[$FIELD_LOOPA2];
				}
				else {
					$r = $this->[$PAB_DEFRECNAME];
				}
				$r = $this->_var_str( $r, PAB_SCALAR );
				$_[1] .= $indent
					. 'foreach ' . $r . '( sort keys ' . $s . ' ) {'
					. "\n"
				;
				$this->_build_script_int( $item, $_[1], $_[2] + 1 ) or return 0;
				$_[1] .= $indent . "}\n";
				next;
			}
			if( ! ( $loop = $this->[$PAB_LOOPDEF]->{$lid} ) ) {
				return $this->_set_error( "Unknown loop '$lid'" );
			}
			if( $item->[$FIELD_LOOPA1] ) {
				$r = $item->[$FIELD_LOOPA1];
			}
			elsif( $loop->[$LOOP_RECORD] ) {
				$r = $loop->[$LOOP_RECORD];
			}
			else {
				$r = $this->[$PAB_DEFRECNAME];
			}
			$loop->[$LOOP_RECORDTYPE] ||= PAB_SCALAR;
			my( $o, $a );
			if( $loop->[$LOOP_OBJECT] ) {
				$o = $this->_var_str( $loop->[$LOOP_OBJECT], PAB_SCALAR );
			}
			if( defined $item->[$FIELD_LOOPA2] ) {
				$a = $item->[$FIELD_LOOPA2];
			}
			elsif( $loop->[$LOOP_FNCARG] ) {
				$a = $loop->[$LOOP_FNCARG];
			}
			else {
				$a = '';
			}
			if( $loop->[$LOOP_SOURCETYPE] == PAB_ARRAY ) {
				$s = $this->_var_str( $loop->[$LOOP_SOURCE], PAB_ARRAY );
				if( $loop->[$LOOP_RECORDTYPE] == PAB_SCALAR ) {
					# --> foreach $record( @array ) {
					$r = $this->_var_str( $r, PAB_SCALAR );
					$_[1] .= $indent
						. 'foreach ' . $r . '( ' . $s . ' ) {'
						. "\n"
					;
					$this->_build_script_int( $item, $_[1], $_[2] + 1 )
						or return 0;
					$_[1] .= $indent . "}\n";
				}
				elsif( $loop->[$LOOP_RECORDTYPE] == PAB_FUNC ) {
					if( $loop->[$LOOP_OBJECT] ) {
						# array, func, object
						# --> foreach $__PLR__( @array ) {
						# --> $object->func( $__PLR__ );
						$lpr = '$__RR_' . $this->[$PAB_SCRIPTCOUNTER] . '__';
						$_[1] .= $indent
							. 'foreach my ' . $lpr . '( ' . $s . ' ) {'
							. "\n"
							. $indent2 . $o . '->' . $r . '( ' . $lpr . ' );'
							. "\n"
						;
						$this->_build_script_int( $item, $_[1], $_[2] + 1 )
							or return 0;
						$_[1] .= $indent . "}\n";
					}
					else {
						# --> foreach $__PLR__( @array ) {
						# --> &func( $__PLR__ );
						$r = $this->_var_str( $r, PAB_FUNC );
						$lpr = '$__RR_' . $this->[$PAB_SCRIPTCOUNTER] . '__';
						$_[1] .= $indent
							. 'foreach my ' . $lpr . '( ' . $s . ' ) {'
							. "\n"
							. $indent2 . $r . '( ' . $lpr . ' );'
							. "\n"
						;
						$this->_build_script_int( $item, $_[1], $_[2] + 1 )
							or return 0;
						$_[1] .= $indent . "}\n";
					}
				}
				else {
					return $this->_set_error(
						"Unsupported record type in loop '$lid' (array)"
					);
				}
			}
			elsif( $loop->[$LOOP_SOURCETYPE] == PAB_HASH ) {
				$s = $this->_var_str( $loop->[$LOOP_SOURCE], PAB_HASH );
				if( $loop->[$LOOP_RECORDTYPE] == PAB_SCALAR ) {
					# --> foreach $record( keys %hash ) {
					$r = $this->_var_str( $r, PAB_SCALAR );
					$_[1] .= $indent
						. 'foreach ' . $r . '( keys ' . $s . ' ) {'
						. "\n"
					;
					$this->_build_script_int( $item, $_[1], $_[2] + 1 )
						or return 0;
					$_[1] .= $indent . "}\n";
				}
				elsif( $loop->[$LOOP_RECORDTYPE] == PAB_FUNC ) {
					if( $loop->[$LOOP_OBJECT] ) {
						# --> foreach $__PLR__( keys %hash ) {
						# --> $object->func( $__PLR__ );
						$lpr = '$__RR_' . $this->[$PAB_SCRIPTCOUNTER] . '__';
						$_[1] .= $indent
							. 'foreach my ' . $lpr . '( keys ' . $s . ' ) {'
							. "\n"
							. $indent2 . $o . '->' . $r . '( ' . $lpr . ' );'
							. "\n"
						;
						$this->_build_script_int( $item, $_[1], $_[2] + 1 )
							or return 0;
						$_[1] .= $indent . "}\n";
					}
					else {
						# --> foreach $__PLR__( keys %hash ) {
						# --> &func( $__PLR__ );
						$r = $this->_var_str( $r, PAB_FUNC );
						$lpr = '$__RR_' . $this->[$PAB_SCRIPTCOUNTER] . '__';
						$_[1] .= $indent
							. 'foreach my ' . $lpr . '( keys ' . $s . ' ) {'
							. "\n"
							. $indent2 . $r . '( ' . $lpr . ' );'
							. "\n"
						;
						$this->_build_script_int( $item, $_[1], $_[2] + 1 )
							or return 0;
						$_[1] .= $indent . "}\n";
					}
				}
				else {
					return $this->_set_error(
						"Unsupported record type in loop '$lid' (hash)"
					);
				}
			}
			elsif( $loop->[$LOOP_SOURCETYPE] == PAB_FUNC ) {
				$s = $loop->[$LOOP_SOURCE];
				if( $loop->[$LOOP_RECORDTYPE] == PAB_SCALAR
					|| $loop->[$LOOP_RECORDTYPE] == PAB_ARRAY
					|| $loop->[$LOOP_RECORDTYPE] == PAB_HASH
				) {
					$r = $this->_var_str( $r, $loop->[$LOOP_RECORDTYPE] );
					if( $loop->[$LOOP_OBJECT] ) {
						# --> while( [$@%]record = $object->enum( $arg ) ) {
						$_[1] .= $indent
							. 'while( ' . $r . ' = ' . $o . '->' . $s . '( ' . $a . ' ) ) {'
							. "\n"
						;
						$this->_build_script_int( $item, $_[1], $_[2] + 1 )
							or return 0;
						$_[1] .= $indent . "}\n";
					}
					else {
						# --> while( [$@%]record = &enum( $arg ) ) {
						$s = $this->_var_str( $s, PAB_FUNC );
						$_[1] .= $indent
							. 'while( ' . $r . ' = ' . $s . '( ' . $a . ' ) ) {'
							. "\n"
						;
						$this->_build_script_int( $item, $_[1], $_[2] + 1 )
							or return 0;
						$_[1] .= $indent . "}\n";
					}
				}
				elsif( $loop->[$LOOP_RECORDTYPE] == PAB_FUNC ) {
					$lpr = '$__RR_' . $this->[$PAB_SCRIPTCOUNTER] . '__';
					if( $loop->[$LOOP_OBJECT] ) {
						# --> while( $__RR__ = $object->enum( $arg ) ) {
						# --> func( $__RR__ );
						$r = $this->_var_str( $r, PAB_FUNC );
						$_[1] .= $indent
							. 'while( ' . $lpr . ' = ' . $o . '->' . $s . '( ' . $a . ' ) ) {'
							. "\n"
							. $indent2 . $r . '( ' . $o . ', ' . $lpr . ' );'
							. "\n"
						;
						$this->_build_script_int( $item, $_[1], $_[2] + 1 )
							or return 0;
						$_[1] .= $indent . "}\n";
					}
					else {
						# --> while( $__RR__ = &enum( $arg ) ) {
						# --> func( $__RR__ );
						$s = $this->_var_str( $s, PAB_FUNC );
						$r = $this->_var_str( $r, PAB_FUNC );
						$_[1] .= $indent
							. 'while( ' . $lpr . ' = ' . $s . '( ' . $a . ' ) ) {'
							. "\n"
							. $indent2 . $r . '( ' . $lpr . ' );'
							. "\n"
						;
						$this->_build_script_int( $item, $_[1], $_[2] + 1 )
							or return 0;
						$_[1] .= $indent . "}\n";
					}
				}
				else {
					return $this->_set_error(
						"Unsupported record type in loop '$lid' (function)"
					);
				}
			}
			else {
				return $this->_set_error(
					"Unsupported source type for loop '$lid'"
				);
			}
		}
		elsif( $item->[$FIELD_TYPE] == $ITEM_SUB ) {
			$_[1] .= $indent . $item->[$FIELD_CONTENT] . " = sub {\n";
			$this->_buildScript( $item, $_[1], $_[2] + 1 ) or return 0;
			$_[1] .= $indent . "};\n";
		}
		elsif( $item->[$FIELD_TYPE] == $ITEM_COMMENT ) {
			$_[1] .= $indent . '#' . $item->[$FIELD_CONTENT] . "\n";
		}
		else {
			return $this->_set_error( 'Unknown item type: ' . $item->[$FIELD_TYPE] );
		}
	}
	return 1;
}

sub _optimize_script {
	#my( $script ) = @_;
	my $this = shift;
	my( $out, $outp, $indent, @outp, $s, $t, $c );
	$out = '';
	@outp = ();
	$outp = 0;
	$c = 0;
	for( split( /\n/, $_[0] ) ) {
		if( /^(\s*)print\s*(.+)\s*\;$/ ) {
			next if ! $2 or $2 eq 'qq{}';
			$indent ||= $1;
			$s = $1;
			$t = $2;
			if( $c ) {
				$c = 0;
				push @outp, 2, $s . $t;
			}
			elsif( index( $t, ',' ) >= 0 ) {
				$c = 1;
				push @outp, 2, $s . $t;
			}
			elsif( substr( $t, 0, 3 ) eq 'qq{' ) {
				push @outp, 1, $s . $t;
			}
			elsif( $t =~ m!\s! ) {
				$c = 1;
				push @outp, 2, $s . $t;
			}
			else {
				push @outp, 1, $s . $t;
			}
			$outp += 2;
		}
		else {
			if( $outp ) {
				$t = 0;
				$out .= $indent . "print\n\t";
				while( $t < $outp ) {
					if( $t > 0 ) {
						if( $outp[$t] == 1 ) {
							$out .= "\n\t. " . $outp[$t + 1];
						}
						else {
							$out .= "\n\t, " . $outp[$t + 1];
						}
					}
					else {
						$out .= $outp[$t + 1];
					}
					$t += 2;
				}
				$out .= "\n" . $indent . ";\n";
				@outp = ();
				$outp = 0;
				$indent = '';
			}
			$out .= $_ . "\n";
		}
	}
	if( $outp ) {
		$t = 0;
		$out .= $indent . "print\n\t";
		while( $t < $outp ) {
			if( $t > 0 ) {
				if( $outp[$t] == 1 ) {
					$out .= "\n\t. " . $outp[$t + 1];
				}
				else {
					$out .= "\n\t, " . $outp[$t + 1];
				}
			}
			else {
				$out .= $outp[$t + 1];
			}
			$t += 2;
		}
		$out .= "\n" . $indent . ";\n";
	}
	$_[0] = $out;
	return 1;
}

sub _parse_file {
	my( $this, $file ) = @_;
	my( $fh, $fs, $content );
	$fs = ( stat( $file ) )[7];
	open( $fh, '< ' . $file )
		or return $this->_set_error( "Unable to open '$file': $!" );
	read( $fh, $content, $fs )
		or return $this->_set_error( "Unable to read from '$file': $!" );
	close( $fh );
	$this->_parse_content( $content );
}

sub _parse_content($) {
	my( $this, $content ) = @_;
	my(
		$cmd_start, $cmd_end, $position, $cmdline,
		$text, $length, $item, $parent_con, $record, $rlb,
		$lbs, $lbf, $newpos, $i1, $parent
	);
	$content =~ s!\r!!gso;
	$parent = $this->[$PAB_PARENTPARSED];
	$position = 0;
	do {
  		$cmd_start = index( $content, $this->[$PAB_PRGSTART], $position );
		$cmd_end = index(
			$content, $this->[$PAB_PRGEND],
			$cmd_start >= 0 ? $cmd_start + $this->[$PAB_PRGSTARTLEN] : $position
		);
		if( ( $cmd_end >= 0 && $cmd_start < 0 )
			|| ( $cmd_start >= 0 && $cmd_end < 0 )
		) {
			# syntax error
			$PAB3::CGI::VERSION
				? &PAB3::CGI::printCode( $content )
				: &PAB3::printCode( $content )
			;
			if( $cmd_start >= 0 ) {
				$i1 = index( $content, "\n", $cmd_start );
				$i1 = index( $content, ' ', $cmd_start ) if $i1 < 0;
				$i1 = length( $content ) if $i1 < 0;
				return $this->_set_error(
					"Syntax error near " .
					substr( $content, $cmd_start, $i1 - $cmd_start )
				);
			}
			else {
				$i1 = rindex( $content, "\n", $cmd_end );
				$i1 = rindex( $content, ' ', $cmd_end ) if $i1 < 0;
				$i1 = 0 if $i1 < 0;
				return $this->_set_error(
					"Syntax error near " .
					substr( $content, $i1, $cmd_end - $i1 )
				);
			}
		}
		if( $cmd_end > $cmd_start ) {
			$length = $cmd_start - $position;
			if( $length > 0 ) {
				$text = substr( $content, $position, $length );
				#if( $text =~ m!\S! ) {
					$item = [ $ITEM_TEXT, undef, undef, $text ];
					push @{ $parent->[$FIELD_CHILD] }, $item;
				#}
			}
			$cmdline = substr(
				$content,
				$cmd_start + $this->[$PAB_PRGSTARTLEN],
				$cmd_end - $cmd_start - $this->[$PAB_PRGENDLEN]
			);
			$cmdline =~ s/^\s*//s;
			$cmdline =~ s/\s*$//s;
			foreach( split( $this->[$PAB_CMDSEP], $cmdline ) ) {
				tr!\n! !;
				if( /^LOOP\s+(\S+)\s+(\S+)\s*(.*)/i ) {
					$item = [ $ITEM_LOOP, $parent, [], $1, $2, $3 ];
					push @{ $parent->[$FIELD_CHILD] }, $item;
					$parent = $item;
					$rlb = 1;
				}
				elsif( /^LOOP\s+(\w+)\s*(.*)/i ) {
					$item = [ $ITEM_LOOP, $parent, [], $1, $2 ];
					push @{ $parent->[$FIELD_CHILD] }, $item;
					$parent = $item;
					$rlb = 1;
				}
				elsif( /^END\s*LOOP/i ) {
					$parent = $parent->[$FIELD_PARENT];
					$rlb = 1;
				}
				elsif( /^IF\s*(.+)/i ) {
					$item = [ $ITEM_CON, $parent, [], $1 ];
					push @{ $parent->[$FIELD_CHILD] }, $item;
					$parent = $item;
					$rlb = 1;
				}
				elsif( /^ELSIF\s+(.+)/i ) {
					$parent = $parent->[$FIELD_PARENT];
					$item = [ $ITEM_ELCO, $parent, [], $1 ];
					push @{ $parent->[$FIELD_CHILD] }, $item;
					$parent = $item;
					$rlb = 1;
				}
				elsif( /^ELSE/i ) {
					$parent = $parent->[$FIELD_PARENT];
					$item = [ $ITEM_ELSE, $parent, [] ];
					push @{ $parent->[$FIELD_CHILD] }, $item;
					$parent = $item;
					$rlb = 1;
				}
				elsif( /^END\s*IF/i ) {
					$parent = $parent->[$FIELD_PARENT];
					$item = [ $ITEM_ECON, $parent ];
					push @{ $parent->[$FIELD_CHILD] }, $item;
					$rlb = 1;
				}
				elsif( /^PRINT\s*(.*)/i || /^\=\s*(.*)/ ) {
					$item = [ $ITEM_PRINT, $parent, undef, $1 ];
					push @{ $parent->[$FIELD_CHILD] }, $item;
					$rlb = 0;
				}
				elsif( /^INCLUDE\s+(.+)/i ) {
					my( $t, $c, $inc, $pab );
					$c = $t = $1;
					if( $this->[$PAB_PATHCACHE] ) {
						$c =~ tr!/!.!;
						$c =~ tr!\\!.!;
						$c = 'inc.' . $c . '.pl';
					}
					else {
						$c = '';
					}
					if( $this->[$PAB_OBJECTNAME] ) {
						$pab = $this->[$PAB_OBJECTNAME];
					}
					else {
						$pab = '$PAB3::_CURRENT';
					}
					$inc =
						"$pab\->make_script_and_run(\n\t"
							. "qq{${t}},\n\tqq{${c}}\n)\n"
							. "\tor die $pab\->error();\n"
					;
					$item = [ $ITEM_ASIS, $parent, undef, $inc ];
					push @{ $parent->[$FIELD_CHILD] }, $item;
					$rlb = 1;
				}
				elsif( /^SUB\s+(.+)/i ) {
					$item = [ $ITEM_SUB, $parent, [], $1 ];
					push @{ $parent->[$FIELD_CHILD] }, $item;
					$parent = $item;
					$rlb = 1;
				}
				elsif( /^END\s*SUB/i ) {
					$parent = $parent->[$FIELD_PARENT];
					$rlb = 1;
				}
				elsif( /^#(.*)/ ) {
					$item = [ $ITEM_COMMENT, $parent, undef, $1 ];
					push @{ $parent->[$FIELD_CHILD] }, $item;
					$rlb = 0;
				}
				elsif( /^!X\s*(.*)/i ) {
					$_ = $1;
					if( /^(PRINT)\s*(.*)/i || /^(\=)\s*(.*)/
						|| /^(SUB)\s*(.*)/i || /^(IF)\s*(.+)/i
						|| /^(ELSIF)\s+(.+)/i
						|| /^(INCLUDE)\s+(.+)/i || /^(#)(.*)/ || /^(\:)(.*)/
					) {
						$item = [
							$ITEM_PRINT, $parent, undef,
							'qq{' . $this->[$PAB_PRGSTART] . ' ' . $1 . ' }, '
								. $2 . ', qq{ ' . $this->[$PAB_PRGEND] . '}'
						];
					}
					elsif( /^LOOP\s*/i || /^END\s*LOOP/i
						|| /^END\s*IF/i || /^ELSE/i || /^END\s*SUB/i
					) {
						chomp;
						$item = [
							$ITEM_PRINT, $parent, undef,
							'qq{' . $this->[$PAB_PRGSTART] . ' ' . $_ . ' '
								. $this->[$PAB_PRGEND] . '}'
						];
					}
					else {
						$item = [
							$ITEM_PRINT, $parent, undef,
							'qq{' . $this->[$PAB_PRGSTART] . ' }, '
								. $_ . ', qq{ ' . $this->[$PAB_PRGEND] . '}'
						];
					}
					push @{ $parent->[$FIELD_CHILD] }, $item;
					$rlb = 0;
				}
				elsif( /^: \s*(.+)/i ) {
					$item = [ $ITEM_DO, $parent, undef, $1 ];
					push @{ $parent->[$FIELD_CHILD] }, $item;
					$rlb = 1;
				}
				elsif( length( $_ ) ) {
					$item = [ $ITEM_DO, $parent, undef, $_ ];
					push @{ $parent->[$FIELD_CHILD] }, $item;
					$rlb = 1;
				}
			}
			$position = $cmd_end + $this->[$PAB_PRGENDLEN];
			if( $rlb ) {
				$lbs = substr( $content, $position, 1 );
				if( $lbs eq "\n" ) {
					$position ++;
				}
			}
		}
		else {
			if( $position < length( $content ) ) {
				$text = substr( $content, $position );
				$item = [ $ITEM_TEXT, $parent, undef, $text ];
				push @{ $parent->[$FIELD_CHILD] }, $item;
			}
			$position = 0;
		}
	} while( $position > 0 );
	$this->[$PAB_PARENTPARSED] = $parent;
	return 1;
}

sub _map_parsed {
	my( $this, $parsed ) = @_;
	my( $item, $hashmap, $loop );
	return 1 unless $this->[$PAB_HASHMAPDEF];
	# map global hashes
	foreach $hashmap( @{ $this->[$PAB_HASHMAPDEF] } ) {
		if( ! $hashmap->[$HASHMAP_LOOPID] ) {
			$this->_map_hash(
				$parsed, $hashmap->[$HASHMAP_HASHNAME],
				$hashmap->[$HASHMAP_MAP], PAB_SCALAR
			) or return 0;
		}
	}
	foreach $item( @{ $parsed->[$FIELD_CHILD] } ) {
		if( $item->[$FIELD_TYPE] == $ITEM_LOOP ) {
			# map hashes inside loops
			foreach $hashmap( @{ $this->[$PAB_HASHMAPDEF] } ) {
				if( $hashmap->[$HASHMAP_LOOPID] &&
					$hashmap->[$HASHMAP_LOOPID] eq $item->[$FIELD_LOOPID]
				) {
					$loop = $this->[$PAB_LOOPDEF]->{$item->[$FIELD_LOOPID]};
					$this->_map_hash(
						$item, $hashmap->[$HASHMAP_HASHNAME],
						$hashmap->[$HASHMAP_MAP], $loop->[$LOOP_RECORDTYPE]
					) or return 0;
					last;
				}
			}
		}
		if( $item->[$FIELD_CHILD] && $item->[$FIELD_CHILD]->[0] ) {
			$this->_map_parsed( $item ) or return 0;
		}
	}
	return 1;
}

sub _map_hash {
	my( $this, $parsed, $hashname, $fieldmap, $hashtype ) = @_;
	my( $item, $key, $hn );
	$hn = $hashname;
	$hn =~ s!^\$!\\\$!;
	if( $hashtype == PAB_ARRAY ) {
		foreach $item( @{ $parsed->[$FIELD_CHILD] } ) {
			if( $item->[$FIELD_CONTENT] ) {
				# $hash{'key'} => $hash[num]
				while( $item->[$FIELD_CONTENT] =~ m!$hn\{[\'\"]*(\w+)[\'\"]*\}! ) {
					$key = $1;
					if( ! defined $fieldmap->{$key} ) {
						return $this->_set_error(
							'Error while mapping hash "' . $hashname . '" to array.'
							. ' Field "' . $key . '" is not defined.'
						);
					}
					$item->[$FIELD_CONTENT] =~
						s/($hn)\{[\'\"]*$key[\'\"]*\}/$1\[$fieldmap->{$key}\]/g;
				}
			}
			if( $item->[$FIELD_CHILD] && $item->[$FIELD_CHILD]->[0] ) {
				$this->_map_hash( $item, $hashname, $fieldmap, $hashtype )
					or return 0;
			}
		}
	}
	else {
		foreach $item( @{ $parsed->[$FIELD_CHILD] } ) {
			if( $item->[$FIELD_CONTENT] ) {
				# $hash->{'key'} => $hash->[num]
				while( $item->[$FIELD_CONTENT] =~ m!$hn\->\{[\'\"]*(\w+)[\'\"]*\}! ) {
					$key = $1;
					if( ! defined $fieldmap->{$key} ) {
						return $this->_set_error(
							'Error while mapping hash "' . $hashname . '" to array.'
							. ' Field "' . $key . '" is not defined.'
						);
					}
					$item->[$FIELD_CONTENT] =~
						s/($hn\->)\{[\'\"]*$key[\'\"]*\}/$1\[$fieldmap->{$key}\]/g;
				}
			}
			if( $item->[$FIELD_CHILD] && $item->[$FIELD_CHILD]->[0] ) {
				$this->_map_hash( $item, $hashname, $fieldmap, $hashtype )
					or return 0;
			}
		}
	}
	return 1;
}

__END__

=head1 NAME

PAB3 - Perl Application Builder

=head1 SYNOPSIS

  use PAB3;

=head1 DESCRIPTION

C<PAB3> provides a framework for building rapid applications in Perl5.
It also includes a template handler for producing output. This part
is defined here.

=head2 Examples

Following example loads a template from B<template1.tpx>, does a loop
over the %ENV variable and produces output on STDOUT.

  -------------------------------------------------------------------
  test1.pl
  -------------------------------------------------------------------
  
  #!/usr/bin/perl -w
  
  use PAB3;
  
  my $pab = PAB3->new();
  
  $pab->make_script_and_run( 'template1.tpx' );

  -------------------------------------------------------------------
  template1.tpx
  -------------------------------------------------------------------
  
  i am from <*=$0*>
  
  my environment looks like:
  
  <* LOOP HASH %ENV *>
  <* PRINT $_ . ' = ' . $ENV{$_} . "\n" *>
  <* END LOOP *>


=head1 METHODS

=over

=item new ( [%arg] )

Creates a new instance of PAB3 template handler class.

Posible arguments are:

  path_cache     => path to save parsed templates
  path_template  => path to the template files
  auto_cache     => create cache files automatically. 'path_cache' is required
  prg_start      => begin of program sequence, default is '<*'
  prg_end        => end of program sequence, default is '*>'
  cmd_sep        => command separator, to define more directives in one program
                    sequence, default is ';;'
  record_name    => name of default record in loops, default is '$_'
  logger         => reference to a PAB3::Logger class
  warn           => warn on error, default is OFF
  die            => die on error, default is ON
  class_name     => name of the variable for this class. eg '$pab'
                    It is needed when templates including templates. If its
                    undefined, a variable $PAB3::_CURRENT will
                    be used as a reference to the current PAB3 class.

Example:

  $pab = PAB3->new(
      'path_cache'    => '/path/to/cache',
      'path_template' => '/path/to/template-files',
  );


=item setenv ()

Set some useful variables to the interpreters environment 

these variables are:

  $ENV{'SCRIPT_PATH'}   : path to the main script
  $ENV{'SCRIPT'}        : name of the main script


=item make_script ( $template )

=item make_script ( $template, $cache )

=item make_script ( $template, '', $package )

=item make_script ( $template, $cache, $package )

Generates a perl script from I<$template> file. If I<$cache> file is
defined the script will be saved into the cache file. If cache file
already exists and the template has not been modified, the function will break
here an return. If cache file has not been specified the script will be
compiled into the memory as a package. The name of this package can be defined
in the third parameter. If I<$package> has not been specified the package
from C<caller(0)> is used.

Returns TRUE on success or FALSE on error.

Example:

  $pab->make_script( 'template.htm' )
      or die $pab->error();

See also L<run_script>, L<make_script_and_run>


=item run_script ( $template )

=item run_script ( '', $cache )

=item run_script ( '', $cache, $package )

Runs a perl script which has been generated by L<make_script()>.
If I<$cache> file is specified, the script will be loaded from there and be
compiled into memory as a package. The name of this package can be defined
in the third parameter. If I<$package> has not been specified the package
from C<caller(0)> is used.

Returns a TRUE on success or FALSE on error.

Example:

  $pab->run_script( 'template.htm' )
      or die $pab->error();

See also
L<make_script>, L<make_script_and_run>,
L<PAB3::require_and_run|PAB3::System/item_require_and_run>


=item make_script_and_run ( $template )

=item make_script_and_run ( $template, $cache )

=item make_script_and_run ( $template, $cache, $package )

Combines the two functions above.
If I<$package> has not been specified the package from C<caller(0)> is used.

Returns a TRUE value on success or FALSE if an error occurs.

Example:

  $pab->make_script_and_run(
      'template.htm',
      'template.pl'
  ) or die $pab->error();

See also L<make_script>, L<run_script>


=item register_loop ( $id, $source, $s_type )

=item register_loop ( $id, $source, $s_type, $record, $r_type )

=item register_loop ( $id, $source, $s_type, $record, $r_type, $object )

=item register_loop ( $id, $source, $s_type, $record, $r_type, $object, $arg )

=item register_loop ( $id, $source, $s_type, $record, $r_type, $object, $arg, $fixed )

Registers a loop which can be used inside templates.

You do not need to define loops in this way. You can also write it directly in
the template. But if you want using hashmaps, you need to go in this way.

B<Arguments>

I<$id>

Loop identifier

I<$source>

the source for the loop.

I<$s_type>

the type of the source. One of these constants: PAB_ARRAY, PAB_HASH
or PAB_FUNC

I<$record>

the record for the loop.

I<$r_type>

the type of the record. One of these constants: PAB_SCALAR or PAB_FUNC

I<$object>

a object for $source or $record functions.

I<$arg>

arguments passed to the source if it is a function, as an array reference

I<$fixed>

installes the loop as fixed. it can not be overwritten

B<Combinations>

Following combinations are possible:

   --------------------------------------
  |   Source   |   Record   |   Object   |
   --------------------------------------
  | PAB_ARRAY  | PAB_SCALAR |     -      |
  | PAB_ARRAY  | PAB_FUNC   |    yes     |
  | PAB_HASH   | PAB_SCALAR |     -      |
  | PAB_HASH   | PAB_FUNC   |    yes     |
  | PAB_FUNC   | PAB_SCALAR |    yes     |
  | PAB_FUNC   | PAB_ARRAY  |    yes     |
  | PAB_FUNC   | PAB_HASH   |    yes     |
   --------------------------------------

I<Source as Array, Record as Scalar>

  # definition
  register_loop( 'id', 'source' => PAB_ARRAY, 'record' => PAB_SCALAR )
  
  # result
  foreach $record( @source ) {
  }

I<Source as Array, Record as Function>

  # definition
  register_loop( 'id', 'source' => PAB_ARRAY, 'record' => PAB_FUNC )
  
  # result
  foreach <iv>( @source ) {
       &record( <iv> );
  }

I<Source as Array, Record as Function, Object>

  # definition
  register_loop( 'id', 'source' => PAB_ARRAY, 'record' => PAB_FUNC, 'object' )
  
  # result
  foreach <iv>( @source ) {
       $object->record( <iv> );
  }

I<Source as Hash, Record as Scalar>

  # definition
  register_loop( 'id', 'source' => PAB_HASH, 'record' => PAB_SCALAR )
  
  # result
  foreach $record( keys %source ) {
  }

I<Source as Hash, Record as Function>

  # definition
  register_loop( 'id', 'source' => PAB_HASH, 'record' => PAB_FUNC )
  
  # result
  foreach <iv>( keys %source ) {
      &record( <iv> );
  }

I<Source as Hash, Record as Function, Object>

  # definition
  register_loop( 'id', 'source' => PAB_HASH, 'record' => PAB_FUNC, 'object' )
  
  # result
  foreach <iv>( keys %source ) {
      $object->record( <iv> );
  }

I<Source as Function, Record as Scalar>

  # definition
  register_loop( 'id', 'source' => PAB_FUNC, 'record' => PAB_SCALAR )
  
  # result
  while( $record = &source( @$arg ) ) {
  }

I<Source as Function, Record as Scalar, Object>

  # definition
  register_loop( 'id', 'source' => PAB_FUNC, 'record' => PAB_SCALAR, 'object' )
  
  # result
  while( $record = $object->source( @$arg ) ) {
  }

I<Source as Function, Record as Array>

  # definition
  register_loop( 'id', 'source' => PAB_FUNC, 'record' => PAB_ARRAY )
  
  # result
  while( @record = &source( @$arg ) ) {
  }

I<Source as Function, Record as Hash>

  # definition
  register_loop( 'id', 'source' => PAB_FUNC, 'record' => PAB_HASH )
  
  # result
  while( %record = &source( @$arg ) ) {
  }

I<Source as Function, Record as Function>

  # definition
  register_loop( 'id', 'source' => PAB_FUNC, 'record' => PAB_FUNC )
  
  # result
  while( <iv> = &source( @$arg ) ) {
      &record( <iv> );
  }

I<Source as Function, Record as Function, Object>

  # definition
  register_loop( 'id', 'source' => PAB_FUNC, 'record' => PAB_FUNC, 'object' )
  
  # result
  while( <iv> = $object->source( @$arg ) ) {
      &record( $object, <iv> );
  }

B<Examples>

Example of a loop over an array with record as subroutine:

  use PAB3 qw(:const);
  
  my @Array1 = ( 1, 2, 3 );
  
  $pab->register_loop(
      'MYLOOP', 'Array1' => PAB_ARRAY , 'init_record' => PAB_FUNC
  );
  
  sub init_record {
      $Record = shift;
      ...
  }

Example of an enumeration loop:

  $pab->register_loop(
      'MYLOOP', 'enum' => PAB_FUNC, 'Record' => PAB_SCALAR
  );
  
  $Counter = 10;
  
  sub enum {
       if( $Counter == 0 ) {
           $Counter = 10;
           return 0;
       }
       return $Counter --;
  }

--- inside the template ---

  <* LOOP MYLOOP *>
  <* PRINT $Record . "\n" *>
  <* END LOOP *>
  

B<See also>

L<-LOOP->.


=item add_hashmap ( $loop_id, $hashname, $fieldmap )

=item add_hashmap ( $loop_id, $hashname, $fieldmap, $hm_save )

Add a hashmap to the parser.
Hashmaps are designed to translate hashes in templates into arrays in the
parsed script. For example: you use $var->{'Key'} in your template. With a
hashmap you can convert it into an array like $var->[0] without taking care of
the indices.
This can noticable make the execution time faster.

B<Parameters>

I<$loop_id>

Defines the loop to search for 
If it is defined the program sequences inside the loop will be converted.
Otherwise the complete template will be used for.

I<$hashname>

Specifies the name of the hash to be translated.

I<$fieldmap>

Can be a reference to an array of fieldnames or a
reference to a hash containing fieldnames as keys and the assiocated indices
as values.

I<$hm_save>

If $fieldmap is an arrayref, the new generated hashmap can be saved in this
parameter.

B<Return Values>

Returns TRUE on success or FALSE if it fails.

B<Example>

  @data = (
      [ 'Smith', 'John', 33 ],
      [ 'Thomson', 'Peggy', 45 ],
      [ 'Johanson', 'Gustav', 27 ],
  );
  @fields = ( 'Name', 'Prename', 'Age' );
  
  $pab->register_loop( 'Person', 'data', PAB_ARRAY, 'per', PAB_SCALAR )
  $pab->add_hashmap( 'Person', 'per', \@fields );
  
  $pab->make_script_and_run( 'template' );

--- template ---

  <* LOOP Person *>
  <* = $per->{'Prename'} . ' ' . $per->{'Name'} *> is <* = $per->{'Age'} *> years old
  <* END LOOP *>

B<Warning>

If an empty result from a db query is returned,  no hashmap can be created.
If your template needs to be compiled and uses hashmaps, which are empty,
you will get an error.
You should recompile affected templates once by running them with
valid hashmaps. Or you can use a hashmap cache handler.
See more at L<PAB3::HashMapCache>.


=item reset ()

Resets loops and hashmaps in the PAB class.

Returns allways a TRUE value.


=item require ( $filename )

Loads the required file and compiles it into a package and runs it once it has
been changed.

Example:

  &PAB3::require( 'config.inc.pl' );


=item require_and_run ( $filename )

Loads the required file and compiles it into a package once it has been changed.
Runs it on every call.

Example:

  &PAB3::require_and_run( 'dosomething.pl' );


=back

=head1 PAB LANGUAGE SYNTAX

The little extended language is needed to extract the PAB and Perl elements from
the rest of the template.
By default program sequences are included in <* ... *> and directives are
separated by ;; .
This parameters can be overwritten in L<new()>.

B<Some Examples>

  <p><* PRINT localtime *></p>
  
  <*
      my $MyVar = int( rand( 3 ) );;
      my @MyText =
          (
              'I wish you a nice day.',
              'Was happy to see you.',
              'Would be nice to see you back.'
          )
  *>
  
  <* IF $MyVar == 0 *>
  <p>I wish you a nice day.</p>
  <* ELSIF $MyVar == 1 *>
  <p>Was happy to see you.</p>
  <* ELSE *>
  <p>Would be nice to see you back.</p>
  <* END IF *>
  
  <!-- OR SHORTLY -->
  
  <p><* PRINT $MyText[$MyVar] *></p>


=head2 Directives

The following list explains the directives available in PAB3.
The description is using the default program and command
separators. B<All directives are case insensitive>.

=over

=item PRINT   E<lt>expressionE<gt>

=item =   E<lt>expressionE<gt>

Prints the output returned from E<lt>expressionE<gt>.
B<Performance notice:> Tests are showing the double of speed
when expressions are combined as strings instead of multiple argmuents.
For example:

   faster:
   <* PRINT $x . ' some data: ' . $str *>
   
   slower:
   <* PRINT $x, ' some data: ', $str *>

Joining several PRINT directives into one directive does not realy
affect to the speed, because the optimizer will do it automatically.

  <* PRINT <expression> *>

or shortly

  <* =<expression>      *>

Example:

  <* PRINT $0, "\n" *>
  <* PRINT 'Now: ' . time . "\n" *>
  <* = 'Or formated: ' . &PAB3::Utils::strftime( '%c', time ) *>


=item :   E<lt>expressionE<gt>

=item     E<lt>expressionE<gt>

Executes E<lt>expressionE<gt> wihout printing the output.
B<This is also the default action if no directive has been specified.>

  <* : <expression> *>

or

  <* <expression>     *>

Example:

  <* : $MyVar = 1 *>
  <* : &mySub( $MyVar ) *>
  <* $X = $Y *>


=item IF   E<lt>conditionE<gt>

=item ELSIF   E<lt>conditionE<gt>

=item ELSE

=item END IF

Enclosed block is processed if the E<lt>conditionE<gt> is true.

  <* IF <condition>    *>
  ...
  <* ELSIF <condition> *>
  ...
  <* ELSE              *>
  ...
  <* END IF            *>


=item INCLUDE   E<lt>templateE<gt>

Process another template file. Please note the "class_name" in L<new()>.

  <* INCLUDE <template.file> *>


=item -LOOP-

=item LOOP   <id>

=item LOOP   <id> <exp1>

=item LOOP   <id> <exp1> <exp2>

=item END LOOP

Performs a predefined loop or a loop which has been registered by
L<register_loop>. In predifened loops like ARRAY, FOR and HASH, E<lt>exp1E<gt>
is used as source and E<lt>exp2E<gt> is used as record.
In userdefined loops E<lt>exp1E<gt> is used as record and E<lt>exp2E<gt> is used
as argument.

  <* LOOP <id> [<exp1> [<exp2>]] *>
  ...
  <* END LOOP                    *>

Theses loops are predefined:

  <* LOOP ARRAY <array> [<record>] *>
  
  <* LOOP FOR   <array> [<record>] *>
    
  <* LOOP HASH  <hash>  [<record>] *>

Example of an ARRAY loop: (FOR does the same like ARRAY)

  <* LOOP ARRAY @INC $_ *>
  <*   PRINT $_ . "\n" *>
  <* END LOOP *>

Example of a HASH loop:

  <* LOOP HASH %ENV $_ *>
  <*   PRINT $_ . ' = ' . $ENV{$_} . "\n" *>
  <* END LOOP *>

An example of a self defined loop:

This example also shows the use of the L<PAB3::DB|PAB3::DB> class.

--- inside the perl script ---

  use PAB3 qw(:const);
  use PAB3::DB;
  use PAB3::Utils qw(:default);
  
  $pab = PAB3->new( ... );
  $db = PAB3::DB->connect( ... );
  
  $r_gb = $db->query( 'SELECT * FROM guestbook ORDER BY Time DESC' );
  
  $pab->register_loop(
       'GUESTBOOK', 'fetch_hash' => PAB_FUNC, 'row' => PAB_HASH, '$r_gb'
  );
  
  $pab->make_script_and_run( 'template.htm' );

--- inside the template ---

  <* LOOP GUESTBOOK *>
  <* PRINT $row{'Submitter'} *> wrote at 
  <* PRINT &strftime( '%c', $row{'Time'} ) *> 
  the following comment:<br>
  <blockquote><* PRINT $row{'Comment'} *></blockquote>
  <hr noshade size="1">
  <* END LOOP *>


Second example of a self defined loop:

This example shows a implementation of guestbook example above, which can run
faster.
It uses an array instead of a hash as record. The Translation will be set by
L<add_hashmap()>.
The template must not be changed.

--- inside the perl script ---

  use PAB3 qw(:const);
  use PAB3::DB;
  use PAB3::Utils qw(:default);
  
  $pab = PAB3->new( ... );
  $db = PAB3::DB->connect( ... );
  
  $r_gb = $db->query( 'SELECT * FROM guestbook ORDER BY Time DESC' );
  
  $pab->register_loop(
       'GUESTBOOK', 'fetch_array', PAB_FUNC, 'row', PAB_ARRAY, '$r_gb'
  );
  $pab->add_hashmap( 'GUESTBOOK', 'row', [ $r_gb->fetch_names() ] );
  
  $pab->make_script_and_run( 'template.htm' );


--- inside the template ---

  <* LOOP GUESTBOOK *>
  <* PRINT $row{'Submitter'} *> wrote at 
  <* PRINT &strftime( '%c', $row{'Time'} ) *> 
  the following comment:<br>
  <blockquote><* PRINT $row{'Comment'} *></blockquote>
  <hr noshade size="1">
  <* END LOOP *>

See also
L<register_loop>, L<add_hashmap>, L<PAB3::DB>, L<PAB3::Utils>


=item SUB    <expression>

=item END SUB

Defines a subroutine in the style C<local E<lt>expressionE<gt> = sub { ... };>.

  <* SUB <expression> *>
  ...
  <* END SUB          *>

Example:

  <* SUB *action *>
  <* PRINT $ENV{'SCRIPT'} . '?do=' . ( $_[0] || '' ) *>
  <* END SUB *>
  
  <a href="<* &action( 'open' ) *>">Open</a>


=item COMMENTS

Comments are copied.

  <* #... *>

Example:

  # comment out directives.
  <* #PRINT $foo *>


=item !X    <directive>

This special directive prints the content in E<lt>directiveE<gt>
as a new directive. It can be useful to generate templates
from templates.

  <* !X <directive> *>

Example:

  <* $foo = '$bar' *>
  
  <* !X PRINT $foo *>
  
  produces: <* PRINT $bar *>
  
  <* !X PRINT "\$foo" *>
  
  produces: <* PRINT $foo *>

=back

=head1 EXPORTS

By default nothing is exported. To export constants like PAB_SCALAR etc. you
can use the export tag ":const"

=head1 AUTHORS

Christian Mueller <christian_at_hbr1.com>

=head1 COPYRIGHT

The PAB3 module is free software. You may distribute under the terms of
either the GNU General Public License or the Artistic License, as specified in
the Perl README file.

=cut
