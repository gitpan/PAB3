#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#include <math.h>
#include <stdlib.h>

#include "my_utils.h"

MODULE = PAB3::Utils		PACKAGE = PAB3::Utils


BOOT:
{
	MY_CXT_INIT;
	MY_CXT.threads = MY_CXT.last_thread = NULL;
	MY_CXT.locale_alias = NULL;
}


#/*****************************************************************************
# * _get_address( var )
# *****************************************************************************/

UV
_get_address( var )
	SV *var;
CODE:
	if( SvROK( var ) )
		RETVAL = (UV) SvRV( var );
	else
		RETVAL = (UV) var;
OUTPUT:
	RETVAL


#/*****************************************************************************
# * _set_module_path( path )
# *****************************************************************************/

void
_set_module_path( mpath )
	SV *mpath;
PREINIT:
	dMY_CXT;
	int i;
	STRLEN len;
	char *path, *s1, *s2;
CODE:
	path = SvPVx( mpath, len );
	//fprintf( stderr, "set module path [%s]\n", path );
	s1 = MY_CXT.locale_path;
	s2 = MY_CXT.zoneinfo_path;
	for( i = len; i > 0; i -- ) {
		*s1 ++ = *path;
		*s2 ++ = *path;
		path ++;
	}
	Copy( "locale/", s1, 7, char );
	Copy( "zoneinfo/", s2, 9, char );
	*( s1 += 7 ) = '\0';
	*( s2 += 9 ) = '\0';
	MY_CXT.locale_path_length = (int) ( s1 - MY_CXT.locale_path );
	MY_CXT.zoneinfo_path_length = (int) ( s2 - MY_CXT.zoneinfo_path );
	read_locale_alias( &MY_CXT );


#/*****************************************************************************
# * str_trim( string )
# *****************************************************************************/

void
str_trim( string )
	SV *string;
PREINIT:
	STRLEN lstr, p1, p2;
	char *sstr, ch;
CODE:
	//lstr = SVLEN( string );
	sstr = SvPVx( string, lstr );
	for( p1 = 0; p1 < lstr; p1 ++ ) {
		ch = sstr[p1];
		if( ! ISWHITECHAR( ch ) ) break;
	}
	for( p2 = lstr - 1; p2 >= 0; p2 -- ) {
		ch = sstr[p2];
		if( ! ISWHITECHAR( ch ) ) break;
	}
	if( p1 == 0 && p2 == lstr - 1 ) {
		ST(0) = sv_2mortal( newSVpvn( sstr, lstr ) );
	}
	else {
		ST(0) = sv_2mortal( newSVpvn( &sstr[p1], p2 - p1 + 1 ) );
	}


#/*****************************************************************************
# * round( num, ... )
# *****************************************************************************/

double
round( num, ... )
	double num;
PREINIT:
	int prec;
CODE:
	if( items < 2 )
		prec = 0;
	else {
		prec = (int) SvIV( ST(1) );
		if( prec > ROUND_PREC_MAX )
			prec = ROUND_PREC_MAX;
		else if( prec < 0 )
			prec = 0;
	}
	RETVAL = floor( num * ROUND_PREC[prec] + 0.5 ) / ROUND_PREC[prec]; 
OUTPUT:
	RETVAL


#/*****************************************************************************
# * _set_locale( tid, ... )
# *****************************************************************************/

const char *
_set_locale( tid, ... )
	UV tid;
PREINIT:
	dMY_CXT;
	my_thread_var_t *tv;
	int i;
	const char *str;
CODE:
	find_or_create_tv( &MY_CXT, tv, tid );
	for( i = 1; i < items; i ++ ) {
		str = (const char *) SvPV_nolen( ST(i) );
		if( ( str = get_locale_format_settings( &MY_CXT, str, &tv->locale ) ) ) {
			RETVAL = str;
			goto exit;
		}
	}
	RETVAL = 0;
exit:
OUTPUT:
	RETVAL


#/*****************************************************************************
# * _set_user_locale( tid, hash_ref )
# *****************************************************************************/

void
_set_user_locale( tid, hash_ref )
	UV tid;
	HV *hash_ref;
PREINIT:
	dMY_CXT;
	my_thread_var_t *tv;
	my_locale_t *loc;
	SV **svp;
	STRLEN vlen;
	AV *av;
	int i;
CODE:
	find_or_create_tv( &MY_CXT, tv, tid );
	loc = &tv->locale;
	if( ( svp = hv_fetch( hash_ref, "grp", 3, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "grouping", 8, 0 ) ) != 0
	)
		loc->grouping = (char) SvIV( *svp );
	if(
		( svp = hv_fetch( hash_ref, "fd", 2, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "frac_digits", 11, 0 ) ) != 0
	)
		loc->frac_digits = (char) SvIV( *svp );
	if(
		( svp = hv_fetch( hash_ref, "ifd", 3, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "int_frac_digits", 15, 0 ) ) != 0
	)
		loc->int_frac_digits = (char) SvIV( *svp );
	if(
		( svp = hv_fetch( hash_ref, "dp", 2, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "decimal_point", 13, 0 ) ) != 0
	)
		loc->decimal_point = ( SvPVx( *svp, vlen ) )[0];
	if( ( svp = hv_fetch( hash_ref, "ts", 2, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "thousands_sep", 13, 0 ) ) != 0
	)
		loc->thousands_sep = ( SvPVx( *svp, vlen ) )[0];
	if(
		( svp = hv_fetch( hash_ref, "cs", 2, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "currency_symbol", 15, 0 ) ) != 0
	)
		strncpy(
			loc->currency_symbol,
			SvPVx( *svp, vlen ),
			sizeof( loc->currency_symbol )
		);
	if(
		( svp = hv_fetch( hash_ref, "ics", 3, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "int_curr_symbol", 15, 0 ) ) != 0
	)
		strncpy(
			loc->int_curr_symbol,
			SvPVx( *svp, vlen ),
			sizeof( loc->int_curr_symbol )
		);
	if(
		( svp = hv_fetch( hash_ref, "csa", 2, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "curr_symb_align", 17, 0 ) ) != 0
	)
		loc->curr_symb_align = ( SvPVx( *svp, vlen ) )[0];
	if(
		( svp = hv_fetch( hash_ref, "ica", 2, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "int_curr_symb_align", 21, 0 ) ) != 0
	)
		loc->int_curr_symb_align = ( SvPVx( *svp, vlen ) )[0];
	if(
		( svp = hv_fetch( hash_ref, "ns", 2, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "negative_sign", 13, 0 ) ) != 0
	)
		loc->negative_sign = ( SvPVx( *svp, vlen ) )[0];
	if(
		( svp = hv_fetch( hash_ref, "ps", 2, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "positive_sign", 13, 0 ) ) != 0
	)
		loc->positive_sign = ( SvPVx( *svp, vlen ) )[0];
	if(
		( svp = hv_fetch( hash_ref, "sdf", 3, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "short_date_format", 17, 0 ) ) != 0
	)
		strncpy(
			loc->short_date_format,
			SvPVx( *svp, vlen ),
			sizeof( loc->short_date_format )
		);
	if(
		( svp = hv_fetch( hash_ref, "ldf", 3, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "long_date_format", 16, 0 ) ) != 0
	)
		strncpy(
			loc->long_date_format,
			SvPVx( *svp, vlen ),
			sizeof( loc->long_date_format )
		);
	if(
		( svp = hv_fetch( hash_ref, "stf", 3, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "short_time_format", 17, 0 ) ) != 0
	)
		strncpy(
			loc->short_time_format,
			SvPVx( *svp, vlen ),
			sizeof( loc->short_time_format )
		);
	if(
		( svp = hv_fetch( hash_ref, "ltf", 3, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "long_time_format", 16, 0 ) ) != 0
	)
		strncpy(
			loc->long_time_format,
			SvPVx( *svp, vlen ),
			sizeof( loc->long_time_format )
		);
	if(
		( svp = hv_fetch( hash_ref, "ams", 3, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "am_string", 9, 0 ) ) != 0
	)
		strncpy(
			loc->time_am_string,
			SvPVx( *svp, vlen ),
			sizeof( loc->time_am_string )
		);
	if(
		( svp = hv_fetch( hash_ref, "pms", 3, 0 ) ) != 0
		|| ( svp = hv_fetch( hash_ref, "pm_string", 9, 0 ) ) != 0
	)
		strncpy(
			loc->time_pm_string,
			SvPVx( *svp, vlen ),
			sizeof( loc->time_pm_string )
		);
	svp = hv_fetch( hash_ref, "sdn", 3, 0 );
	if( svp == 0 ) svp = hv_fetch( hash_ref, "short_day_names", 15, 0 );
	if( svp != 0 && SvTYPE( SvRV( *svp ) ) == SVt_PVAV ) {
		av = (AV*) SvRV( *svp );
		for( i = 0; i < 7; i ++ )
			if( ( svp = av_fetch( av, i, 0 ) ) != 0 )
				strncpy(
					loc->short_day_names[i],
					SvPVx( *svp, vlen ),
					sizeof( loc->short_day_names[i] )
				);
	}
	svp = hv_fetch( hash_ref, "ldn", 3, 0 );
	if( svp == 0 ) svp = hv_fetch( hash_ref, "long_day_names", 14, 0 );
	if( svp != 0 && SvTYPE( SvRV( *svp ) ) == SVt_PVAV ) {
		av = (AV*) SvRV( *svp );
		for( i = 0; i < 7; i ++ )
			if( ( svp = av_fetch( av, i, 0 ) ) != 0 )
				strncpy(
					loc->long_day_names[i],
					SvPVx( *svp, vlen ),
					sizeof( loc->long_day_names[i] )
				);
	}
	svp = hv_fetch( hash_ref, "smn", 3, 0 );
	if( svp == 0 ) svp = hv_fetch( hash_ref, "short_month_names", 17, 0 );
	if( svp != 0 && SvTYPE( SvRV( *svp ) ) == SVt_PVAV ) {
		av = (AV*) SvRV( *svp );
		for( i = 0; i < 12; i ++ )
			if( ( svp = av_fetch( av, i, 0 ) ) != 0 )
				strncpy(
					loc->short_month_names[i],
					SvPVx( *svp, vlen ),
					sizeof( loc->short_month_names[i] )
				);
	}
	svp = hv_fetch( hash_ref, "lmn", 3, 0 );
	if( svp == 0 ) svp = hv_fetch( hash_ref, "long_month_names", 17, 0 );
	if( svp != 0 && SvTYPE( SvRV( *svp ) ) == SVt_PVAV ) {
		av = (AV*) SvRV( *svp );
		for( i = 0; i < 12; i ++ )
			if( ( svp = av_fetch( av, i, 0 ) ) != 0 )
				strncpy(
					loc->long_month_names[i],
					SvPVx( *svp, vlen ),
					sizeof( loc->long_month_names[i] )
				);
	}


#/*****************************************************************************
# * _number_format(
# *     tid, value [, dec [, pnt [, thou [, neg [, pos [, zerofill [, fillchar]]]]]]]
# * )
# *****************************************************************************/

void
_number_format( tid, value, dec = 0, pnt = 0, thou = 0, neg = 0, pos = 0, zerofill = 0, fillchar = 0 )
	UV tid;
	double value;
	int dec;
	char pnt;
	SV *thou;
	char neg;
	SV *pos;
	int zerofill;
	char fillchar;
PREINIT:
	dMY_CXT;
	char thousep;
	char pos2;
	my_thread_var_t *tv;
	char str[256];
CODE:
	find_or_create_tv( &MY_CXT, tv, tid );
	if( pnt == 0 ) pnt = tv->locale.decimal_point;
	if( thou == 0 || ! SvOK( thou ) )
		thousep = tv->locale.thousands_sep;
	else if( SvPOK( thou ) )
		thousep = (char)* SvPV_nolen( thou );
	else
		thousep = 0;
	if( neg == 0 ) neg = tv->locale.negative_sign;
	if( pos == 0 || ! SvOK( pos ) )
		pos2 = 0;
	else if( SvPOK( pos ) )
		pos2 = (char)* SvPV_nolen( pos );
	else
		pos2 = tv->locale.positive_sign;
	_int_number_format(
		value, str, 255, dec, pnt, thousep, neg, pos2, zerofill, fillchar
	);
	ST(0) = sv_2mortal( newSVpv( str, 0 ) );


#/*****************************************************************************
# * _set_timezone( tid, tz )
# *****************************************************************************/

int
_set_timezone( tid, tz )
	UV tid;
	const char *tz;
PREINIT:
	dMY_CXT;
	my_thread_var_t *tv;
CODE:
	find_or_create_tv( &MY_CXT, tv, tid );
	if(
		! tv->timezone.id[0]
		|| strcmp( tv->timezone.id, tz ) != 0
	) {
		Zero( &tv->timezone, 1, my_vtimezone_t );
		RETVAL = read_timezone( &MY_CXT, tz, &tv->timezone );
	}
	else {
		RETVAL = 1;
	}
OUTPUT:
	RETVAL


#/*****************************************************************************
# * _localtime( tid, ... )
# *****************************************************************************/

void
_localtime( tid, ... )
	UV tid;
PREINIT:
	dMY_CXT;
	time_t timer;
	my_vdatetime_t *tim;
	my_thread_var_t *tv;
PPCODE:
	find_or_create_tv( &MY_CXT, tv, tid );
	if( items < 2 )
		timer = time( 0 );
	else
		timer = (time_t) SvUV( ST(1) );
	tim = apply_timezone( tv, &timer );
	EXTEND( SP, 9 );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_sec ) ) );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_min ) ) );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_hour ) ) );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_mday ) ) );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_mon ) ) );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_year ) ) );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_wday ) ) );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_yday ) ) );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_isdst ) ) );


#/*****************************************************************************
# * gmtime( ... )
# *****************************************************************************/

void
gmtime( ... )
PREINIT:
	time_t timer;
	struct tm *tim;
PPCODE:
	if( items < 1 )
		timer = time( 0 );
	else
		timer = (time_t) SvUV( ST(0) );
	tim = gmtime( &timer );
	EXTEND( SP, 9 );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_sec ) ) );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_min ) ) );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_hour ) ) );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_mday ) ) );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_mon ) ) );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_year ) ) );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_wday ) ) );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_yday ) ) );
	XPUSHs( sv_2mortal( newSVuv( tim->tm_isdst ) ) );


#/*****************************************************************************
# * _strftime( format, ... )
# *****************************************************************************/

char *
_strftime( tid, format, ... )
	UV tid;
	const char *format;
PREINIT:
	dMY_CXT;
	my_thread_var_t *tv;
	long len, gmt;
	my_vdatetime_t *tim;
	time_t timestamp;
CODE:
	find_or_create_tv( &MY_CXT, tv, tid );
	len = strlen( format );
	if( ! len ) {
		RETVAL = NULL;
		goto exit;
	}
	len = 64 + len * 4;
	New( 1, RETVAL, len, char );
	if( items < 3 )
		timestamp = time( 0 );
	else
		timestamp = SvUV( ST(2) );
	if( items < 4 )
		gmt = 0;
	else
		gmt = SvIV( ST(3) );
	if( ! gmt )
		tim = apply_timezone( tv, &timestamp );
	else {
		copy_tm_to_vdatetime( gmtime( &timestamp ), &tv->time_struct );
		tim = &tv->time_struct;
		tim->tm_gmtoff = 0;
		tim->tm_zone = DEFAULT_ZONE;
	}
	_int_strftime( tv, RETVAL, len, format, tim );
exit:
OUTPUT:
	RETVAL
CLEANUP:
	Safefree( RETVAL );


#/*****************************************************************************
# * _strfmon( tid, format, number )
# *****************************************************************************/

char *
_strfmon( tid, format, number )
	UV tid;
	const char *format;
	double number;
PREINIT:
	dMY_CXT;
	my_thread_var_t *tv;
CODE:
	find_or_create_tv( &MY_CXT, tv, tid );
	New( 1, RETVAL, 64, char );
	_int_strfmon( tv, RETVAL, 64, format, number );
OUTPUT:
	RETVAL
CLEANUP:
	Safefree( RETVAL );


#/*****************************************************************************
# * _cleanup_class( tid )
# *****************************************************************************/

void
_cleanup_class( tid )
	UV tid;
PREINIT:
	dMY_CXT;
	my_thread_var_t *tv;
CODE:
	find_or_create_tv( &MY_CXT, tv, tid );
	if( tv )
		remove_thread_var( &MY_CXT, tv );


#/*****************************************************************************
# * _cleanup()
# *****************************************************************************/

void
_cleanup()
PREINIT:
	dMY_CXT;
CODE:
	cleanup_my_utils( &MY_CXT );
