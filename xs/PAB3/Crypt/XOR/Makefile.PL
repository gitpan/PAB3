use 5.008;
use ExtUtils::MakeMaker;

$Verbose = 0;

WriteMakefile(
    NAME => 'PAB3::Crypt::XOR',
    VERSION_FROM => 'XOR.pm',
    ABSTRACT => 'Simple periodic XOR encryption',
    LIBS => '',
    DEFINE => '',
    INC => '-I../../../',
    XSPROTOARG => '-noprototypes',
    PREREQ_PM => {},
    OBJECT => '$(O_FILES)',
    XS => { 'XOR.xs' => 'XOR.c' },
    C => ['XOR.c'],
);
