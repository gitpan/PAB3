#!/usr/bin/perl

print "1..$tests\n";

$_pos = 1;

require PAB3::Crypt::XOR;
_check( 1 );

import PAB3::Crypt::XOR;
_check( 1 );

$key = 'bla';
$plain = 'THIS IS A REAL PLAIN TEXT';

$cipher = &PAB3::Crypt::XOR::encrypt( $key, $plain );
_check( $cipher );

$plain2 = &PAB3::Crypt::XOR::decrypt( $key, $cipher );
_check( $plain eq $plain2 );

$cipher = &PAB3::Crypt::XOR::encrypt_hex( $key, $plain );
_check( $cipher );

$plain2 = &PAB3::Crypt::XOR::decrypt_hex( $key, $cipher );
_check( $plain eq $plain2 );

BEGIN {
	$tests = 6;
}

sub _check {
	my( $val ) = @_;
	print "" . ( $val ? "ok" : "fail" ) . " $_pos\n";
	$_pos ++;
}
