use 5.008;
use ExtUtils::MakeMaker;

$Verbose = 0;

my @libs;
push @libs, '-L/lib/w32api -lole32 -lversion' if $^O eq 'cygwin';
#push @libs, 'LIBCMT.LIB' if $^O eq 'MSWin32';

WriteMakefile(
    NAME => 'PAB3',
    VERSION_FROM => 'PAB3.pm', # finds $VERSION
#    ABSTRACT_FROM => 'Utils.pm', # retrieve abstract from module
    LIBS => \@libs, # e.g., '-lm'
    DEFINE => '', # e.g., '-DHAVE_SOMETHING'
    INC => '-I../../', # e.g., '-I. -I/usr/include/other'
    XSPROTOARG => '-noprototypes',
    PREREQ_PM => {
    },
    OBJECT => '$(O_FILES)',
    XS => { 'PAB3.xs' => 'PAB3.c' },
    C => ['my_pab3.c', 'PAB3.c'],
    H => ['my_pab3.h'],
);
