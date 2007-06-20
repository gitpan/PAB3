#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <stdarg.h>

#include "my_utils.h"


const static int mday_array[] = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };


void parse_vdatetime( const char *str, my_vdatetime_t *tms );

void copy_tm_to_vdatetime( struct tm *src, my_vdatetime_t *dst ) {
	dst->tm_sec = src->tm_sec;
	dst->tm_min = src->tm_min;
	dst->tm_hour = src->tm_hour;
	dst->tm_mday = src->tm_mday;
	dst->tm_mon = src->tm_mon;
	dst->tm_year = src->tm_year;
	dst->tm_wday = src->tm_wday;
	dst->tm_yday = src->tm_yday;
	dst->tm_isdst = src->tm_isdst;
}

char *PerlIO_fgets( char *buf, size_t max, PerlIO *stream ) {
	int val;
	size_t pos = max + 1;
	char *tmp;
	tmp = buf;
	while( pos > 0 ) {
		val = PerlIO_getc( stream );
		if( val == -1 ) {
			if( pos == max + 1 ) return NULL;
			break;
		}
		else if( val == '\n' ) break;
		else if( val == '\r' ) continue;
		*tmp ++ = (char) val;
		pos --;
	}
	*tmp = '\0';
	return tmp;
}

my_thread_var_t *find_thread_var( unsigned long tid ) {
	dMY_CXT;
	my_thread_var_t *tv1;
	tv1 = MY_CXT.threads;
	while( tv1 ) {
		if( tv1->tid == tid ) return tv1;
		tv1 = tv1->next;
	}
	return 0;
}

my_thread_var_t *create_thread_var( unsigned long tid ) {
	my_thread_var_t *tv;
	dMY_CXT;
	Newz( 1, tv, 1, my_thread_var_t );
	if( ! tv ) {
		/* out of memory! */
		Perl_croak( aTHX_ "PANIC: running out of memory!" );
	}
	tv->tid = tid;
	Copy( &DEFAULT_LOCALE, &tv->locale, 1, my_locale_t );
	if( MY_CXT.threads == NULL )
		MY_CXT.threads = tv;
	else {
		MY_CXT.last_thread->next = tv;
		tv->prev = MY_CXT.last_thread;
	}
	MY_CXT.last_thread = tv;
	return tv;
}

void remove_thread_var( my_thread_var_t *tv ) {
	my_thread_var_t *tvp, *tvn;
	dMY_CXT;
	if( ! tv ) return;
	tvp = tv->prev;
	tvn = tv->next;
	if( tv == MY_CXT.threads )
		MY_CXT.threads = tvn;
	if( tv == MY_CXT.last_thread )
		MY_CXT.last_thread = tvp;
	if( tvp )
		tvp->next = tvn;
	if( tvn )
		tvn->prev = tvp;
	Safefree( tv );
}

void cleanup_my_utils() {
	my_thread_var_t *tv1, *tv2;
	dMY_CXT;
	tv1 = MY_CXT.threads;
	while( tv1 ) {
		tv2 = tv1->next;
		Safefree( tv1 );
		tv1 = tv2;
	}
	MY_CXT.threads = MY_CXT.last_thread = NULL;
	free_locale_alias();
}

void free_locale_alias() {
	dMY_CXT;
	my_locale_alias_t *p1, *p2;
	p1 = MY_CXT.locale_alias;
	while( p1 ) {
		p2 = p1->next;
		Safefree( p1->alias );
		Safefree( p1->locale );
		Safefree( p1 );
		p1 = p2;
	}
	MY_CXT.locale_alias = NULL;
}

void read_locale_alias() {
	dMY_CXT;
	PerlIO *pfile;
	char str[256], *key, *val, *p1;
	int lkey, lval;
	my_locale_alias_t *pl1, *pl2 = NULL;
	free_locale_alias();
	key = my_strcpy( str, MY_CXT.locale_path );
	my_strcpy( key, "#alias" );
	//printf( "read locale alias from %s\n", str );
	pfile = PerlIO_open( str, "r" );
	if( ! pfile ) return;
	while( ( p1 = PerlIO_fgets( str, sizeof( str ), pfile ) ) ) {
		if( p1 == str ) continue;
		key = str;
		while( ISWHITECHAR( *key ) ) {
			if( key >= p1 ) continue;
			key ++;
		}
		if( *key == '#' ) continue;
		val = key;
		while( ! ISWHITECHAR( *val ) ) {
			if( val >= p1 ) continue;
			val ++;
		}
		lkey = val - key;
		*val ++ = '\0';
		while( ISWHITECHAR( *val ) ) {
			if( val >= p1 ) continue;
			val ++;
		}
		lval = p1 - val;
		//printf( "got alias '%s'(%d) for '%s'(%d)\n", key, lkey, val, lval );
		Newz( 1, pl1, 1, my_locale_alias_t );
		New( 1, pl1->alias, lkey, char );
		New( 1, pl1->locale, lval, char );
		Copy( key, pl1->alias, lkey + 1, char );
		Copy( val, pl1->locale, lval + 1, char );
		if( pl2 == NULL )
			MY_CXT.locale_alias = pl1;
		else
			pl2->next = pl1;
		pl2 = pl1;
	}
	PerlIO_close( pfile );
}

const char *get_locale_alias( const char *id ) {
	dMY_CXT;
	my_locale_alias_t *la1;
	for( la1 = MY_CXT.locale_alias; la1 != NULL; la1 = la1->next ) {
		if( strcmp( la1->alias, id ) == 0 ) {
			//printf( "found alias %s\n", id );
			return la1->locale;
		}
	}
	return id;
}

const char *get_locale_format_settings( const char *id, my_locale_t *locale ) {
	dMY_CXT;
	char str[256], *key, *val, *p1;
	PerlIO *pfile;
	int i;
	if( locale == 0 ) return NULL;
	key = my_strncpy( str, MY_CXT.locale_path, MY_CXT.locale_path_length );
	id = get_locale_alias( id );
	my_strcpy( key, id );
	pfile = PerlIO_open( str, "r" );
	if( ! pfile ) return NULL;
	while( ( p1 = PerlIO_fgets( str, sizeof( str ), pfile ) ) ) {
		if( p1 == str || str[0] == '#' ) continue;
		val = strchr( str, ':' );
		if( ! val ) continue;
		*val ++ = '\0';
		key = str;
		if( strcmp( key, "grp" ) == 0 )
			locale->grouping = (char) atoi( val );
		else if( strcmp( key, "fd" ) == 0 )
			locale->frac_digits = (char) atoi( val );
		else if( strcmp( key, "dp" ) == 0 )
			locale->decimal_point = val[0];
		else if( strcmp( key, "ts" ) == 0 )
			locale->thousands_sep = val[0];
		else if( strcmp( key, "ns" ) == 0 )
			locale->negative_sign = val[0];
		else if( strcmp( key, "ps" ) == 0 )
			locale->positive_sign = val[0];
		else if( strcmp( key, "cs" ) == 0 )
			strncpy( locale->currency_symbol, val, sizeof( locale->currency_symbol ) );
		else if( strcmp( key, "ics" ) == 0 )
			strncpy( locale->int_curr_symbol, val, sizeof( locale->int_curr_symbol ) );
		else if( strcmp( key, "csa" ) == 0 )
			locale->curr_symb_align = val[0];
		else if( strcmp( key, "ica" ) == 0 )
			locale->int_curr_symb_align = val[0];
		else if( strcmp( key, "ldf" ) == 0 )
			strncpy( locale->long_date_format, val, sizeof( locale->long_date_format ) );
		else if( strcmp( key, "sdf" ) == 0 )
			strncpy( locale->short_date_format, val, sizeof( locale->short_date_format ) );
		else if( strcmp( key, "ltf" ) == 0 )
			strncpy( locale->long_time_format, val, sizeof( locale->long_time_format ) );
		else if( strcmp( key, "stf" ) == 0 )
			strncpy( locale->short_time_format, val, sizeof( locale->short_time_format ) );
		else if( strcmp( key, "ams" ) == 0 )
			strncpy( locale->time_am_string, val, sizeof( locale->time_am_string ) );
		else if( strcmp( key, "pms" ) == 0 )
			strncpy( locale->time_pm_string, val, sizeof( locale->time_pm_string ) );
		else if( strstr( key, "lm" ) == key ) {
			key += 2;
			i = atoi( key );
			if( i < 1 || i > 12 ) continue;
			strncpy(
				locale->long_month_names[i - 1],
				val,
				sizeof( locale->long_month_names[0] )
			);
		}
		else if( strstr( key, "sm" ) == key ) {
			key += 2;
			i = atoi( key );
			if( i < 1 || i > 12 ) continue;
			strncpy(
				locale->short_month_names[i - 1],
				val,
				sizeof( locale->short_month_names[0] )
			);
		}
		else if( strstr( key, "ld" ) == key ) {
			key += 2;
			i = atoi( key );
			if( i < 1 || i > 7 ) continue;
			strncpy(
				locale->long_day_names[i - 1],
				val,
				sizeof( locale->long_day_names[0] )
			);
		}
		else if( strstr( key, "sd" ) == key ) {
			key += 2;
			i = atoi( key );
			if( i < 1 || i > 7 ) continue;
			strncpy(
				locale->short_day_names[i - 1],
				val,
				sizeof( locale->short_day_names[0] )
			);
		}
	}
	PerlIO_close( pfile );
	return id;
}

time_t seconds_since_epoch( my_vdatetime_t *tim ) {
	int i, leapyear, year;
	time_t days = 0;
	//if( tim == NULL ) return 0;
	year = tim->tm_year + 1900;
	for( i = 1970; i < year; i ++ ) {
		leapyear = ( ( i % 4 == 0 && i % 100 != 0 ) || i % 400 == 0 );
		days += leapyear ? 366 : 365;
	}
	if( tim->tm_mon > 1 ) {
		days += ( ( year % 4 == 0 && year % 100 != 0 ) || year % 400 == 0 );
	}
	for( i = 0; i < tim->tm_mon - 1; i ++ ) {
		days += mday_array[i];
	}
	days += tim->tm_mday;
	return days * 86400 + tim->tm_hour * 3600 + tim->tm_min * 60 + tim->tm_sec;
}

int get_week_number( my_vdatetime_t *tim, int dayoffset, int iso ) {
	/*
	char tmp[256];
	strftime( tmp, sizeof( tmp ), "%%c %c %%W %W %%U %U %%V %V %%v %v %%o %o %%z %z %%G %G %%g %g", (struct tm*) tim );
	printf( "%s\n", tmp );
	*/
	int weeknum, offset;
	int year = tim->tm_year + 1900;
	int yday = tim->tm_yday + 1;
	int wd0101 = tim->tm_wday - ( tim->tm_yday % 7 );
	if( wd0101 < 0 ) wd0101 += 7; else if( wd0101 > 6 ) wd0101 -= 7;
	if( iso ) {
		if( dayoffset )
			if( wd0101 == 0 ) wd0101 = 6; else wd0101 --;
		weeknum = ( yday + wd0101 - 1 ) / 7;
		if( wd0101 < 4 )
			return weeknum + 1;
		if( weeknum != 0 )
			return weeknum;
		year --;
		wd0101 -= ( ( year % 4 == 0 && year % 100 != 0 ) || year % 400 == 0 ) ? 2 : 1;
		if( dayoffset )
			if( wd0101 == 0 ) wd0101 = 6; else wd0101 --;
		return ( wd0101 < 4 ) ? 53 : 52;
	}
	offset = 7 + 1 - wd0101 + dayoffset;
	if( offset == 8 ) offset = 1;
	return ( yday - offset + 7 ) / 7;
	/*
	int weeknum = ( yday - offset + 7 ) / 7;
	if( weeknum != 0 ) return weeknum;
	year --;
	wd0101 -= ( ( year % 4 == 0 && year % 100 != 0 ) || year % 400 == 0 ) ? 2 : 1;
	if( wd0101 < 0 ) wd0101 += 7;
	offset = 7 + 1 - wd0101 + dayoffset;
	return ( offset == 2 || offset == 8 ) ? 53 : 52;
	*/
}

int get_iso8601_year( my_vdatetime_t *tim, int full ) {
	int year = tim->tm_year - 100;
	int wd0101 = tim->tm_wday - ( tim->tm_yday % 7 );
	if( wd0101 < 0 ) wd0101 += 7; else if( wd0101 > 6 ) wd0101 -= 7;
	if( wd0101 == 0 ) wd0101 = 6; else wd0101 --;
	if( wd0101 >= 4 ) year --;
	if( full ) return year + 2000;
	if( year < 0 ) return year + 100;
	while( year > 100 ) year -= 100;
	return year;
}

int is_short_year( my_vdatetime_t *tim ) {
	int y = tim->tm_year + 1900;
	y = y + y / 4 - y / 100 + y / 400;
	if( ( y % 7 ) == 4 ) return 0;
	if( ( ( y - 1 ) % 7 ) == 3 ) return 0;
	return 1;
}

/*
strtime..
almost posix compatible
*/

int _int_strftime( my_thread_var_t *tv, char *str, int maxlen, const char *format, my_vdatetime_t *stime ) {
	int i, fml, step, val, l;
	char *ret, *ml;
	const char *sval;
	unsigned char tmp[8];
	time_t uval;
	if( str == NULL || format == NULL ) return 0;
	if( stime == NULL ) {
		stime = apply_timezone( tv, 0 );
	}
	fml = strlen( format );
	ml = str + maxlen;
	ret = str;
	step = 0;
	for( i = 0; i < fml && ret < ml; i ++ ) {
		switch( step ) {
		case 0:
			if( format[i] == '%' ) {
				step = 1;
				continue;
			}
			*ret ++ = format[i];
			break;
		case 1:
			switch( format[i] ) {
			case '%':
				*ret ++ = '%';
				break;
			case 'I':
				val = stime->tm_hour;
				if( val == 0 ) val = 12;
				else if( val > 12 ) val -= 12;
				goto setval_2digits;
			case 'H':
				val = stime->tm_hour;
				goto setval_2digits;
			case 'M':
				val = stime->tm_min;
				goto setval_2digits;
			case 'S':
				val = stime->tm_sec;
				goto setval_2digits;
			case 'm':
				val = stime->tm_mon + 1;
				goto setval_2digits;
			case 'd':
				val = stime->tm_mday;
				goto setval_2digits;
			case 'C':
				val = ( 1900 + stime->tm_year ) / 100;
				while( val > 100 ) val -= 100;
				goto setval_2digits;
			case 'g':
				val = get_iso8601_year( stime, 0 );
				goto setval_2digits;
			case 'U':
				val = get_week_number( stime, 0, 0 );
				goto setval_2digits;
			case 'V':
				val = get_week_number( stime, 1, 1 );
				goto setval_2digits;
			case 'W':
				val = get_week_number( stime, 1, 0 );
				goto setval_2digits;
			case 'y':
				val = stime->tm_year;
				while( val >= 100 ) val -= 100;
setval_2digits:
				if( ret >= ml - 1 ) goto exit;
				my_itoa( ret, val, 10 );
				if( ! ret[1] ) {
					ret[1] = ret[0];
					ret[0] = '0';
				}
				ret += 2;
				break;
			case 'e':
				val = stime->tm_mday;
				goto setval_2digits_space;
			case 'l':
				val = stime->tm_hour;
				if( val == 0 ) val = 12;
				else if( val > 12 ) val -= 12;
				goto setval_2digits_space;
			case 'k':
				val = stime->tm_hour;
				//goto setval_2digits_space;
setval_2digits_space:
				if( ret >= ml - 1 ) goto exit;
				my_itoa( ret, val, 10 );
				if( ! ret[1] ) {
					ret[1] = ret[0];
					ret[0] = ' ';
				}
				ret += 2;
				break;
			case 'n':
				*ret ++ = '\n';
			case 't':
				*ret ++ = '\t';
				break;
			case 'a':
				sval = tv->locale.short_day_names[stime->tm_wday];
				goto setval_str;
			case 'A':
				sval = tv->locale.long_day_names[stime->tm_wday];
				goto setval_str;
			case 'b':
			case 'h':
				sval = tv->locale.short_month_names[stime->tm_mon];
				goto setval_str;
			case 'B':
				sval = tv->locale.long_month_names[stime->tm_mon];
				goto setval_str;
			case 'Z':
				sval = stime->tm_zone;
				goto setval_str;
			case 'p':
				if( stime->tm_hour >= 12 )
					sval = tv->locale.time_pm_string;
				else
					sval = tv->locale.time_am_string;
				goto setval_str;
			case 'P':
				if( stime->tm_hour >= 12 )
					sval = tv->locale.time_pm_string;
				else
					sval = tv->locale.time_am_string;
				for( l = 0; sval[l] != '\0'; l ++ )
					tmp[l] = tolower( sval[l] );
				tmp[l] = '\0';
				sval = (const char *) tmp;
setval_str:
				while( 1 ) {
					if( ret >= ml ) goto exit;
					if( *sval == '\0' ) break;
					*ret ++ = *sval ++;
				}
				break;
			case 'G':
				val = get_iso8601_year( stime, 1 );
				if( ret >= ml - 3 ) goto exit;
				ret = my_itoa( ret, val, 10 );
				break;
			case 'Y':
				val = stime->tm_year + 1900;
				if( ret >= ml - 3 ) goto exit;
				ret = my_itoa( ret, val, 10 );
				break;
			case 'w':
				if( ret >= ml ) goto exit;
				ret = my_itoa( ret, stime->tm_wday, 10 );
				break;
			case 'u':
				if( ret >= ml ) goto exit;
				ret = my_itoa( ret, stime->tm_wday == 0 ? 7 : stime->tm_wday, 10 );
				break;
			case 'j':
				if( ret >= ml - 2 ) goto exit;
				my_itoa( ret, stime->tm_yday + 1, 10 );
				if( ! ret[1] ) {
					ret[2] = ret[0];
					ret[0] = ret[1] = '0';
				}
				else if( ! ret[2] ) {
					ret[2] = ret[1];
					ret[1] = ret[0];
					ret[0] = '0';
				}
				ret += 3;
				break;
			case 'o':
			case 'O':
				if( ret >= ml - 6 ) goto exit;
				val = stime->tm_gmtoff;
				val = ( val / 100 ) * 3600 + ( val % 100 ) * 60;
				ret = my_itoa( ret, val, 10 );
				break;
			case 'z':
				if( ret >= ml - 5 ) goto exit;
				val = stime->tm_gmtoff;
				if( val < 0 ) {
					*ret ++ = '-';
					val *= -1;
				}
				else if( val == 0 ) {
					ret = my_strcpy( ret, "+0000" );
					break;
				}
				else
					*ret ++ = '+';
				if( val < 1000 )
					*ret ++ = '0';
				ret = my_itoa( ret, val, 10 );
				break;
			case 's':
				if( ret >= ml - 10 ) goto exit;
				uval = seconds_since_epoch( stime );
				l = sprintf( ret, "%lu", uval );
				ret += l;
				break;
			case 'D':
				l = _int_strftime( tv, ret, (int) ( ml - ret ), "%m/%d/%y", stime );
				ret += l;
				break;
			case 'F':
				l = _int_strftime( tv, ret, (int) ( ml - ret ), "%Y-%m-%d", stime );
				ret += l;
				break;
			case 'r':
				l = _int_strftime( tv, ret, (int) ( ml - ret ), "%I:%M:%S %p", stime );
				ret += l;
				break;
			case 'R':
				l = _int_strftime( tv, ret, (int) ( ml - ret ), "%H:%M", stime );
				ret += l;
				break;
			case 'T':
				l = _int_strftime( tv, ret, (int) ( ml - ret ), "%H:%M:%S", stime );
				ret += l;
				break;
			case 'x':
				l = _int_strftime(
					tv, ret, (int) ( ml - ret ), tv->locale.short_date_format, stime
				);
				ret += l;
				break;
			case 'X':
				l = _int_strftime(
					tv, ret, (int) ( ml - ret ), tv->locale.short_time_format, stime
				);
				ret += l;
				break;
			case 'v':
				l = _int_strftime(
					tv, ret, (int) ( ml - ret ), "%e-%b-%Y", stime
				);
				ret += l;
				break;
			case 'c':
			case '+':
				l = _int_strftime(
					tv, ret, (int) ( ml - ret ), tv->locale.long_date_format, stime
				);
				ret += l;
				if( ret >= ml - 1 ) goto exit;
				*ret ++ = ' ';
				l = _int_strftime(
					tv, ret, (int) ( ml - ret ), tv->locale.long_time_format, stime
				);
				ret += l;
				break;
			default:
				*ret ++ = '%';
				if( ret >= ml ) goto exit;
				*ret ++ = format[i];
			}
			step = 0;
			break;
		}
	}
exit:
	*ret = '\0';
	return (int) ( ret - str );
}

/*
strfmon..
almost posix compatible
*/

//#define MY_STRFMON_FMT "[%-14#5.0n]"

size_t _int_strfmon( my_thread_var_t *tv, char *str, size_t maxsize, const char *format, ... ) {
	my_locale_t *loc = &tv->locale;
	int step = 0, grouping = 0, plus = 0, currency = 0, justify, width;
	int swp = 0, lpp = 0, rpp = 0, lprec, rprec, j, fmt;
	size_t fml, i;
	char *ret, chf, *ml, fill, swidth[16], slprec[16], srprec[16];
	char *cptr, *cpt2;
	double darg;
	/*
	char tmp[256];
	strfmon( tmp, sizeof( tmp ), MY_STRFMON_FMT "\n" MY_STRFMON_FMT "\n" MY_STRFMON_FMT, 123.45, -123.45, 3456.781 );
	printf( "\n%s\n\n", tmp );
	*/
	va_list ap;
	va_start( ap, format );
	fml = strlen( format );
	ml = str + maxsize;
	ret = str;
	for( i = 0; i < fml && ret < ml; i ++ ) {
		chf = format[i];
		switch( step ) {
		case 0:
			if( chf == '%' ) {
				grouping = 1;
				plus = 0;
				currency = 1;
				justify = 2;
				swp = lpp = rpp = 0;
				fmt = 0;
				step = 1;
				fill = ' ';
			}
			else {
				*ret ++ = chf;
			}
			break;
		case 1:
			switch( chf ) {
			case '%':
				*ret ++ = '%';
				break;
			case '=':
				if( i ++ >= fml - 1 ) break;
				fill = format[i];
				break;
			case '^':
				grouping = 0;
				break;
			case '+':
				plus = 1;
				break;
			case '(':
				plus = 2;
				break;
			case '!':
				currency = 0;
				break;
			case '-':
				justify = 1;
				break;
			case '#':
				step = 2;
				break;
			case '.':
				step = 3;
				break;
			case 'n':
				fmt = 1;
				goto calcmon;
			case 'i':
				fmt = 2;
				goto calcmon;
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
				if( swp < sizeof( swidth ) )
					swidth[swp ++] = chf;
				break;
			default:
				*ret ++ = '%';
				if( ret >= ml ) goto exit;
				*ret ++ = chf;
				break;
			}
			break;
		case 2: // left precision
			switch( chf ) {
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
				if( lpp < sizeof( slprec ) )
					slprec[lpp ++] = chf;
				break;
			default:
				step = 1;
				i --;
				break;
			}
			break;
		case 3: // right precision
			switch( chf ) {
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
				if( rpp < sizeof( srprec ) )
					srprec[rpp ++] = chf;
				break;
			default:
				step = 1;
				i --;
				break;
			}
			break;
		}
		continue;
calcmon:
		if( swp > 0 ) {
			swidth[swp] = '\0';
			width = atoi( swidth );
		}
		else
			width = 0;
		if( lpp > 0 ) {
			slprec[lpp] = '\0';
			lprec = atoi( slprec );
		}
		else
			lprec = 0;
		if( rpp > 0 ) {
			srprec[rpp] = '\0';
			rprec = atoi( srprec );
		}
		else
			rprec = ( fmt == 1 ) ? loc->frac_digits : loc->int_frac_digits;
		darg = va_arg( ap, double );
		cptr = ret;
		if( darg < 0 ) {
			if( plus == 2 )
				*cptr ++ = '(';
			else
				*cptr ++ = loc->negative_sign;
		}
		else if( plus == 1 )
			*cptr ++ = loc->positive_sign;
		else if( plus == 2 || ( currency && lprec > 0 ) )
			*cptr ++ = ' ';
		if( currency ) {
			if( fmt == 1 ) {
				if( loc->curr_symb_align == 'l' )
					for( j = 0; loc->currency_symbol[j] != '\0'; j ++ )
						*cptr ++ = loc->currency_symbol[j];
			}
			else {
				if( loc->int_curr_symb_align == 'l' ) {
					for( j = 0; loc->int_curr_symbol[j] != '\0'; j ++ )
						*cptr ++ = loc->int_curr_symbol[j];
					*cptr ++ = ' ';
				}
			}
		}
		cptr = _int_number_format(
			darg < 0 ? -darg : darg,
			cptr,
			(int) ( maxsize - ( cptr - str ) ),
			rprec,
			loc->decimal_point,
			grouping ? loc->thousands_sep : 0,
			'\0',
			'\0',
			lprec,
			fill
		);
		if( currency ) {
			if( fmt == 1 ) {
				if( loc->curr_symb_align == 'r' ) {
					*cptr ++ = ' ';
					for( j = 0; loc->currency_symbol[j] != '\0'; j ++ )
						*cptr ++ = loc->currency_symbol[j];
				}
			}
			else {
				if( loc->int_curr_symb_align == 'r' ) {
					*cptr ++ = ' ';
					for( j = 0; loc->int_curr_symbol[j] != '\0'; j ++ )
						*cptr ++ = loc->int_curr_symbol[j];
				}
			}
		}
		if( width > cptr - ret ) {
			if( justify == 2 ) {
				cpt2 = ret + width;
				while( cptr >= ret )
					*cpt2 -- = *cptr --;
				while( cpt2 >= ret )
					*cpt2 -- = fill;
				ret += width;
			}
			else {
				ret += width;
				while( cptr < ret )
					*cptr ++ = fill;
			}
		}
		else
			ret = cptr;
		if( plus == 2 ) {
			if( darg < 0 )
				*ret ++ = ')';
			else
				*ret ++ = ' ';
		}
		step = 0;
	}
exit:
	va_end( ap );
	*ret = '\0';
	return (size_t) ( ret - str );
}

int parse_timezone( const char *tz, my_vtimezone_t *vtz ) {
	dMY_CXT;
	char zfile[256], str[256], *key, *val, *val2, *key2;
	char *key3, *val3;
	PerlIO *pfile;
	int level = 0, len, itmp2, vzip;
	my_vzoneinfo_t *vzi = 0;
	my_weekdaynum_t *wdn;
	if( vtz == 0 ) return 0;
	len = strlen( tz );
	key = my_strncpy( zfile, MY_CXT.zoneinfo_path, MY_CXT.zoneinfo_path_length );
	key = my_strncpy( key, tz, len );
	key = my_strncpy( key, ".ics", 4 );
	pfile = PerlIO_open( zfile, "r" );
	if( ! pfile ) {
		Perl_croak( aTHX_ "Timezone not found: %s", tz );
		return 0;
	}
	Copy( tz, vtz->id, len, char );
	while( PerlIO_fgets( str, sizeof( str ), pfile ) ) {
		val = strchr( str, ':' );
		if( ! val ) continue;
		*val ++ = 0;
		key = str;
		switch( level ) {
		case 0: // ROOT
			if( strcmp( key, "BEGIN" ) == 0 ) {
				if( strcmp( val, "VTIMEZONE" ) == 0 ) {
					level = 1;
					continue;
				}
			}
			break;
		case 1: // VTIMEZONE
			if( strcmp( key, "END" ) == 0 ) {
				if( strcmp( val, "VTIMEZONE" ) == 0 ) {
					level = 0;
					continue;
				}
			}
			if( strcmp( key, "BEGIN" ) == 0 ) {
				level = 2;
				vzip = strcmp( val, "DAYLIGHT" ) == 0 ? 1 : 0;
				vzi = &vtz->zoneinfo[vzip];
				vzi->isdst = vzip;
				continue;
			}
			break;
		case 2: // DAYLIGHT/STANDARD
			if( strcmp( key, "END" ) == 0 ) {
				if( strcmp( val, "DAYLIGHT" ) == 0
					|| strcmp( val, "STANDARD" ) == 0
				) {
					level = 1;
					continue;
				}
			}
			if( strcmp( key, "TZOFFSETTO" ) == 0 ) {
				vzi->tzoffsetto = atoi( val );
			}
			else if( strcmp( key, "TZNAME" ) == 0 ) {
				len = strlen( val );
				Copy( val, vzi->tzname, len, char );
			}
			else if( strcmp( key, "DTSTART" ) == 0 ) {
				parse_vdatetime( val, &vzi->dtstart );
			}
			else if( strcmp( key, "RRULE" ) == 0 ) {
				while( 1 ) {
					key = strchr( val, ';' );
					if( key ) *key = 0;
					val2 = strchr( val, '=' );
					if( ! val2 ) break;
					*val2 ++ = 0;
					key2 = val;
					if( strcmp( key2, "FREQ" ) == 0 ) {
						if( strcmp( val2, "YEARLY" ) == 0 )
							vzi->rr_frequency = 1;
						else if( strcmp( val2, "MONTHLY" ) == 0 )
							vzi->rr_frequency = 2;
						else if( strcmp( val2, "WEEKLY" ) == 0 )
							vzi->rr_frequency = 3;
						else if( strcmp( val2, "DAILY" ) == 0 )
							vzi->rr_frequency = 4;
						else if( strcmp( val2, "HOURLY" ) == 0 )
							vzi->rr_frequency = 5;
						else if( strcmp( val2, "MINUTELY" ) == 0 )
							vzi->rr_frequency = 6;
						else if( strcmp( val2, "SECONDLY" ) == 0 )
							vzi->rr_frequency = 7;
					}
					else if( strcmp( key2, "BYMONTH" ) == 0 ) {
						while( 1 ) {
							val3 = strchr( val2, ',' );
							if( val3 ) *val3 = 0;
							vzi->rr_bymonth[atoi( val2 ) - 1] = 1;
							if( ! val3 ) break;
							val2 = val3 + 1;
						}
					}
					else if( strcmp( key2, "BYDAY" ) == 0 ) {
						while( 1 ) {
							val3 = strchr( val2, ',' );
							if( val3 ) *val3 = 0;
							wdn = &vzi->rr_byday;
							if( val2[0] == '-' || val2[0] == '+' )
								itmp2 = strlen( val2 ) == 5 ? 3 : 2; 
							else if( val2[0] >= '0' && val2[0] <= '9' )
								itmp2 = strlen( val2 ) == 4 ? 2 : 1;
							else
								itmp2 = 0;
							key3 = val2 + itmp2;
							wdn->day = WKDAY_TO_NUM( key3 );
							if( itmp2 ) {
								val2[itmp2] = 0;
								wdn->ordwk = atoi( val2 );
							}
							if( ! val3 ) break;
							val2 = val3 + 1;
						}
					}
					else {
						//printf( "Unknown item: %s -> %s\n", key2, val2 );
					}
					if( ! key ) break;
					val = key + 1;
				}
			}
			break;
		}
	}
	PerlIO_close( pfile );
	return 1;
}

void parse_vdatetime( const char *str, my_vdatetime_t *tms ) {
	char stmp[5];
	const char *val = str;
	memcpy( stmp, val, 4 );
	stmp[4] = 0;
	tms->tm_year = atoi( stmp ) - 1900;
	val = &val[4];
	memcpy( stmp, val, 2 );
	stmp[2] = 0;
	tms->tm_mon = atoi( stmp ) - 1;
	val = &val[2];
	memcpy( stmp, val, 2 );
	stmp[2] = 0;
	tms->tm_mday = atoi( stmp );
	if( strlen( str ) > 8 ) {
		val = &val[3];
		memcpy( stmp, val, 2 );
		stmp[2] = 0;
		tms->tm_hour = atoi( stmp );
		val = &val[2];
		memcpy( stmp, val, 2 );
		stmp[2] = 0;
		tms->tm_min = atoi( stmp );
		val = &val[2];
		memcpy( stmp, val, 2 );
		stmp[2] = 0;
		tms->tm_sec = atoi( stmp );
	}
	else {
		tms->tm_hour = tms->tm_min = tms->tm_sec = -1;
	}
}

my_vdatetime_t *apply_timezone( my_thread_var_t *tv, time_t *timer ) {

	my_vtimezone_t *vtz;
	my_vzoneinfo_t *vzi;
	my_vdatetime_t *vdt;
	my_weekdaynum_t *vwdn;
	time_t tt1, tt2, tt3;
	my_vdatetime_t *tim, tmz[2], *ctmz1, *ctmz2;
	int i, leapyear, year, tmz_pos = 0;
	long days1, days2, days, wday, mday, mdayl;

	if( timer == 0 ) {
		tt1 = time( 0 );
		timer = &tt1;
	}
	vtz = &tv->timezone;
	copy_tm_to_vdatetime( gmtime( timer ), &tv->time_struct );
	tim = &tv->time_struct;
	tim->tm_gmtoff = 0;
	tim->tm_zone = DEFAULT_ZONE;
	if( vtz == 0 || vtz->id[0] == 0 ) {
		return tim;
	}

	year = tim->tm_year + 1900;
	days = 0;
	for( i = 1970; i < year; i ++ ) {
		days += ( ( i % 4 == 0 && i % 100 != 0 ) || i % 400 == 0 ) ? 366 : 365;
	}
	leapyear = ( ( year % 4 == 0 && year % 100 != 0 ) || year % 400 == 0 );

	for( tmz_pos = 0; tmz_pos < 2; tmz_pos ++ ) {
		vzi = &vtz->zoneinfo[tmz_pos];
		ctmz1 = &tmz[tmz_pos];
		vdt = &vzi->dtstart;
		ctmz1->tm_mon = vdt->tm_mon;
		ctmz1->tm_mday = vdt->tm_mday;
		ctmz1->tm_hour = vdt->tm_hour;
		ctmz1->tm_min = vdt->tm_min;
		ctmz1->tm_sec = vdt->tm_sec;
		ctmz1->tm_isdst = vzi->isdst;
		ctmz1->tm_gmtoff = vzi->tzoffsetto;
		ctmz1->tm_zone = vzi->tzname;
		switch( vzi->rr_frequency ) {
		case 0:
			break;
		case 1: // FREQ::YEARLY
			// BYMONTH
			days1 = days;
			for( i = 0; i < 12; i ++ ) {
				days2 = days1 + ( i == 2 && leapyear ? mday_array[i] : mday_array[i] - 1 );
				if( ! vzi->rr_bymonth[i] || tim->tm_mon < i ) goto rrbymonthnext;
				ctmz1->tm_mon = i;
				mdayl = ( i == 2 && leapyear ) ? mday_array[i] + 1 : mday_array[i];
				// BYDAY
				vwdn = &vzi->rr_byday;
				if( vwdn ) {
					if( vwdn->ordwk < 0 ) {
						mday = mdayl;
						wday = ( days2 % 7 ) + 4;
						if( wday > 6 ) wday -= 7;
						while( wday != vwdn->day ) {
							mday --;
							wday --;
							if( wday < 0 ) wday = 6;
						}
						if( vwdn->ordwk < -1 )
							mday += ( vwdn->ordwk + 1 ) * 7;
					}
					else {
						wday = ( days1 % 7 ) + 4;
						if( wday > 6 ) wday -= 7;
						if( vwdn->day < wday )
							mday = 1 + vwdn->day + 7 - wday;
						else
							mday = 1 + vwdn->day - wday;
						if( vwdn->ordwk > 1 )
							mday += ( vwdn->ordwk - 1 ) * 7;
					}
					ctmz1->tm_mday = mday;
					break;
				}
rrbymonthnext:
				days1 = days2 + 1;
			}
			break;
		}
	}
	if( tmz_pos < 2 ) ctmz1 = &tmz[0];
	else {
		if( tmz[0].tm_mon < tmz[1].tm_mon ) {
			ctmz1 = &tmz[0];
			ctmz2 = &tmz[1];
		}
		else {
			ctmz1 = &tmz[1];
			ctmz2 = &tmz[0];
		}
		tt1 = ctmz1->tm_sec + ctmz1->tm_min * 60 + ctmz1->tm_hour * 3600
			+ ctmz1->tm_mday * 86400 + ctmz1->tm_mon * 2678400;
		tt2 = ctmz2->tm_sec + ctmz2->tm_min * 60 + ctmz2->tm_hour * 3600
			+ ctmz2->tm_mday * 86400 + ctmz2->tm_mon * 2678400;
		tt3 = tim->tm_sec + tim->tm_min * 60 + tim->tm_hour * 3600
			+ tim->tm_mday * 86400 + tim->tm_mon * 2678400;
		if( tt3 < tt1 || tt3 > tt2 ) goto usetmz2;
		goto calczone;
usetmz2:
		ctmz1 = ctmz2;
	}
calczone:
	tim->tm_gmtoff = ctmz1->tm_gmtoff;
	tim->tm_zone = ctmz1->tm_zone;
	if( ( i = tim->tm_gmtoff ) == 0 ) goto exit;
	tim->tm_min += i % 100;
	tim->tm_hour += i / 100;
	if( i < 0 ) {
		if( tim->tm_min < 0 ) {
			tim->tm_min += 60;
			tim->tm_hour --;
		}
		if( tim->tm_hour < 0 ) {
			tim->tm_hour += 24;
			tim->tm_mday --;
			tim->tm_yday --;
			if( tim->tm_wday == 0 )
				tim->tm_wday = 6;
			else
				tim->tm_wday --;
		}
		if( tim->tm_mday < 0 ) {
			if( tim->tm_mon == 0 ) {
				tim->tm_mon = 11;
				tim->tm_year --;
				tim->tm_yday = ( ( tim->tm_year % 4 == 0 && tim->tm_year % 100 != 0 ) || tim->tm_year % 400 == 0 ) ? 365 : 364;
			}
			else {
				tim->tm_mon --;
			}
			tim->tm_mday = mday_array[tim->tm_mon];
		}
	}
	else {
		if( tim->tm_min > 59 ) {
			tim->tm_min -= 60;
			tim->tm_hour ++;
		}
		if( tim->tm_hour > 23 ) {
			tim->tm_hour -= 24;
			tim->tm_mday ++;
			tim->tm_yday ++;
			if( tim->tm_wday == 6 )
				tim->tm_wday = 0;
			else
				tim->tm_wday ++;
		}
		i = tim->tm_mon == 1
			&& ( ( tim->tm_year % 4 == 0 && tim->tm_year % 100 != 0 ) || tim->tm_year % 400 == 0 )
				? 29 : mday_array[tim->tm_mon];
		if( tim->tm_mday > i ) {
			if( tim->tm_mon == 11 ) {
				tim->tm_mon = 0;
				tim->tm_year ++;
				tim->tm_yday = 0;
			}
			else
				tim->tm_mon ++;
			tim->tm_mday = 1;
		}
	}
exit:
	return tim;
}

double _my_round( double num, int prec ) {
	if( prec > ROUND_PREC_MAX )
		prec = ROUND_PREC_MAX;
	else if( prec < 0 )
		prec = 0;
	return floor( num * ROUND_PREC[prec] + 0.5 ) / ROUND_PREC[prec];
}

// original by Will Bateman (March 2005) / GPL License

char *_int_number_format( double value, char *str, int maxlen, int fd, char dp,
	char ts, char ns, char ps, int zf, char fc
) {
	long i, j, k, count;
	double val;
	long a, b;
	char *number, *tmp, *p2;
	
	assert( fd >= 0 );
	assert( fd <= 19 );
	if( ns == 0 ) ns = '-';
	if( dp == 0 ) dp = ',';
	number = str;
	if( value < 0 ) {
		*number ++ = ns;
		val = _my_round( -value, fd );
	}
	else {
		if( ps ) *number ++ = ps;
		val = _my_round( value, fd );
	}
	
	a = (int) floor( val );
	if( zf > 0 ) {
		b = a;
		j = 1;
		while( b > 10 ) {
			b /= 10;
			j ++;
		}
		tmp = number;
		if( ( j = zf - j ) > 0 ) {
			if( fc == 0 ) fc = '0';
			while( j -- ) *tmp ++ = fc;
		}
		p2 = tmp;
		tmp = my_itoa( tmp, a, 10 );
	}
	else {
		p2 = str;
		tmp = my_itoa( number, a, 10 );
	}
	
	if( ts != 0 ) {
		i = tmp - str - ( str[0] == ns || ps != 0 );
		j = ( i - 1 ) / 3;
		for( k = i + j, count = -1; k >= 0 && j > 0; k --, count ++ ) {
			if( count == 3 ) {
				number[k] = number + k > p2 ? ts : fc;
				j --;
				k --;
				count = 0;
				tmp ++;
			}
			number[k] = number[k - j];
		}
	}
	
	if( fd > 0 ) {
		*tmp ++ = dp;
		
		j = (long) pow( 10.0, fd );
		a = (long) floor( ( val - a ) * (double) j + 0.5 );
		
		if( a > 0 ) {
			j /= 10;
			while( a < j ) {
				*tmp ++ = '0';
				j /= 10;
			}
			tmp = my_itoa( tmp, a, 10 );
		}
		else {
			j = fd;
			while( j > 0 ) {
				*tmp ++ = '0';
				j --;
			}
		}
	}
	*tmp = '\0';
	
	return tmp;
}

char *my_strncpy( char *dst, const char *src, unsigned long len ) {
	char ch;
	for( ; len > 0; len -- ) {
		if( ( ch = *src ++ ) == '\0' ) {
			*dst = '\0';
			return dst;
		}
		*dst ++ = ch;
	}
	*dst = '\0';
	return dst;
}

char *my_strcpy( char *dst, const char *src ) {
	char ch;
	while( 1 ) {
		if( ( ch = *src ++ ) == '\0' ) {
			*dst = '\0';
			return dst;
		}
		*dst ++ = ch;
	}
	*dst = '\0';
	return dst;
}

char *my_strrev( char *str, size_t len ) {
	char *p1, *p2;
	if( ! str || ! *str ) return str;
	for( p1 = str, p2 = str + len - 1; p2 > p1; ++ p1, -- p2 ) {
		*p1 ^= *p2;
		*p2 ^= *p1;
		*p1 ^= *p2;
	}
	return str;
}

char *my_itoa( char *str, int value, int radix ) {
	int rem;
	char *ret = str;
	switch( radix ) {
	case 16:
		do {
			rem = value % 16;
			value /= 16;
			switch( rem ) {
			case 10:
				*ret ++ = 'A';
				break;
			case 11:
				*ret ++ = 'B';
				break;
			case 12:
				*ret ++ = 'C';
				break;
			case 13:
				*ret ++ = 'D';
				break;
			case 14:
				*ret ++ = 'E';
				break;
			case 15:
				*ret ++ = 'F';
				break;
			default:
				*ret ++ = (char) ( rem + 0x30 );
				break;
			}
		} while( value != 0 );
		break;
	default:
		do {
			rem = value % radix;
			value /= radix;
			*ret ++ = (char) ( rem + 0x30 );
		} while( value != 0 );
	}
	*ret = '\0' ;
	my_strrev( str, ret - str );
	return ret;
}
