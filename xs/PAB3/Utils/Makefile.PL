use 5.008;
use ExtUtils::MakeMaker;

$Verbose = 0;

my @libs;
push @libs, '-L/lib/w32api -lole32 -lversion' if $^O eq 'cygwin';
#push @libs, 'LIBCMT.LIB' if $^O eq 'MSWin32';

WriteMakefile(
    NAME => 'PAB3::Utils',
    VERSION_FROM => 'Utils.pm', # finds $VERSION
#    ABSTRACT_FROM => 'Utils.pm', # retrieve abstract from module
    LIBS => \@libs, # e.g., '-lm'
    DEFINE => '', # e.g., '-DHAVE_SOMETHING'
    INC => '-I../../', # e.g., '-I. -I/usr/include/other'
    XSPROTOARG => '-noprototypes',
    PREREQ_PM => {
    },
    OBJECT => '$(O_FILES)',
    XS => { 'Utils.xs' => 'Utils.c' },
    C => ['my_utils.c', 'Utils.c'],
    H => ['my_utils.h'],
);
