use 5.008;
use ExtUtils::MakeMaker;

%os_supported = ( 'linux' => 1, 'MSWin32' => 1, 'darwin' => 1 );

if( ! $os_supported{$^O} ) {
print <<EOF1;
************* WARNING *************
* Your operation system has not   *
* been tested.                    *
* The installation may fail!      *
***********************************
EOF1
}

$PAB = 1;
%PAB_OPT = (
	'with_mysql' => '_auto_',
	'with_pgsql' => '_auto_',
	'with_sqlite3' => '_auto_',
);

@argv = ();
foreach( @ARGV ) {
	if( /--help/ ) {
		print_usage();
	}
	if( /--with-mysql=*(.*)/ ) {
		$PAB_OPT{'with_mysql'} = $1 ? $1 : '_search_';
	}
	elsif( /--with-pgsql=*(.*)/ ) {
		$PAB_OPT{'with_pgsql'} = $1 ? $1 : '_search_';
	}
	elsif( /--with-sqlite3=*(.*)/ ) {
		$PAB_OPT{'with_sqlite3'} = $1 ? $1 : '_search_';
	}
	elsif( /--enable-sqlite3-metadata/ ) {
		$PAB_OPT{'sqlite3_enable_metadata'} = 1;
	}
	elsif( /--disable-mysql/ ) {
		$PAB_OPT{'with_mysql'} = 0;
	}
	elsif( /--disable-pgsql/ ) {
		$PAB_OPT{'with_pgsql'} = 0;
	}
	elsif( /--disable-sqlite3/ ) {
		$PAB_OPT{'with_sqlite3'} = 0;
	}
	else {
		push @argv, $_;
	}
}
@ARGV = @argv;

WriteMakefile(
    NAME => 'PAB3',
    VERSION_FROM => 'xs/PAB3/PAB3.pm',
    ABSTRACT => 'PAB - Perl Application Builder',
    PREREQ_PM => {
        'Time::HiRes' => 0,
        'Digest::MD5' => 0,
        'Storable' => 0,
    },
    XSPROTOARG => '-prototypes',
    OPTIMIZE => '-O3',
    DIR => [ 'xs' ],
);

1;

sub print_usage {
	print <<USAGE;
Usage: perl $0 [options]
Options:
    --help               print this message

    --with-mysql[=DIR]   Include MySQL support. DIR is the MySQL base directory or the path to mysql_config
    --with-pgsql[=DIR]   Include PostgreSQL support. DIR is the PostgreSQL base install directory or the path to pg_config
    --with-sqlite3[=DIR]  Include SQLite3 support. DIR is the SQLite3 base install directory
    --enable-sqlite3-metadata   Enable SQLite3 column metadata. SQLite3 must be compiled with SQLITE_ENABLE_COLUMN_METADATA preprocessor symbol

    --disable-mysql      Disable MySQL support. Enabled by default
    --disable-pgsql      Disable PostgreSQL support. Enabled by default
    --disable-sqlite3    Disable SQLite3 support. Enabled by default
USAGE
	exit 256;
}
