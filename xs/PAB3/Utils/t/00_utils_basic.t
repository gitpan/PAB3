#!/usr/bin/perl

print "1..$tests\n";

require PAB3::Utils;
print "ok 1\n";

import PAB3::Utils;
print "ok 2\n";

BEGIN {
	$tests = 2;
}
