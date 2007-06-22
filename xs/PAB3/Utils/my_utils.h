#ifndef __INCLUDE__MY_SYSUTILS_H__
#define __INCLUDE__MY_SYSUTILS_H__ 1

#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#define __PACKAGE__ "PAB3::Utils"

#ifndef DWORD
#define DWORD unsigned long
#endif

#ifndef my_longlong
#if defined __unix__
#define my_longlong long long
#elif defined _WIN32
#define my_longlong __int64
#else
#define my_longlong long
#endif
#endif

typedef struct st_my_vdatetime {
	int tm_sec;				/* Seconds.	[0-60] (1 leap second) */
	int tm_min;				/* Minutes.	[0-59] */
	int tm_hour;			/* Hours.	[0-23] */
	int tm_mday;			/* Day.		[1-31] */
	int tm_mon;				/* Month.	[0-11] */
	int tm_year;			/* Year	- 1900.  */
    int tm_wday;    		/* days since Sunday    [0-6] */
    int tm_yday;    		/* days since January 1 [0-365] */
    int tm_isdst;   		/* daylight savings time flag */
	long tm_gmtoff;			/* Seconds east of UTC */
	const char *tm_zone;	/* Timezone abbreviation */
} my_vdatetime_t;

typedef struct st_my_weekdaynum {
	int ordwk, day;
} my_weekdaynum_t;

typedef struct st_my_vzoneinfo {
	int					tzoffsetto;
	char				tzname[6];
	my_vdatetime_t 		dtstart;
	int					isdst;
	int					rr_frequency;
	int					rr_bymonth[12];
	my_weekdaynum_t		rr_byday;
} my_vzoneinfo_t;

typedef struct st_my_vtimezone {
	my_vzoneinfo_t		zoneinfo[2];
	char				id[32];
} my_vtimezone_t;

typedef struct st_my_locale {
	char		name[16];
	char		decimal_point;
	char		thousands_sep;
	char		grouping;
	char		frac_digits;
	char		int_frac_digits;
	char		currency_symbol[4];
	char		int_curr_symbol[4];
	char		curr_symb_align;
	char		int_curr_symb_align;
	char		negative_sign;
	char		positive_sign;
	char		short_date_format[16];
	char		long_date_format[16];
	char		short_time_format[16];
	char		long_time_format[16];
	char		time_am_string[8];
	char		time_pm_string[8];
	char		short_month_names[12][8];
	char		long_month_names[12][16];
	char		short_day_names[7][8];
	char		long_day_names[7][16];
} my_locale_t;

typedef struct st_my_locale_alias {
	struct st_my_locale_alias	*next;
	char						*alias;
	char						*locale;
} my_locale_alias_t;

typedef struct st_my_thread_var {
	struct st_my_thread_var		*prev, *next;
	unsigned long				tid;
	my_locale_t					locale;
	my_vtimezone_t				timezone;
	my_vdatetime_t				time_struct;
} my_thread_var_t;

#define MY_CXT_KEY __PACKAGE__ "::_guts" XS_VERSION

typedef struct st_my_cxt {
	char						locale_path[256]; 
	char						zoneinfo_path[256]; 
	int							locale_path_length;
	int							zoneinfo_path_length;
	my_thread_var_t				*threads;
	my_thread_var_t				*last_thread;
	my_locale_alias_t			*locale_alias;
} my_cxt_t;

START_MY_CXT

#define ISWHITECHAR(ch) \
	( (ch) == 32 || (ch) == 10 || (ch) == 13 || (ch) == 9 || (ch) == 0 || (ch) == 11 )

#define WKDAY_TO_NUM( wkd ) ( \
	( (wkd)[0] == 'S' && (wkd)[1] == 'U' ) ? 0 : \
	( (wkd)[0] == 'M' && (wkd)[1] == 'O' ) ? 1 : \
	( (wkd)[0] == 'T' && (wkd)[1] == 'U' ) ? 2 : \
	( (wkd)[0] == 'W' && (wkd)[1] == 'E' ) ? 3 : \
	( (wkd)[0] == 'T' && (wkd)[1] == 'H' ) ? 4 : \
	( (wkd)[0] == 'F' && (wkd)[1] == 'R' ) ? 5 : \
	( (wkd)[0] == 'S' && (wkd)[1] == 'A' ) ? 6 : \
	-1 )

#define ARRAY_LEN(x) ( sizeof( (x) ) / sizeof( (x)[0] ) )

static const double ROUND_PREC[] = {
	1, 10, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12
	, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19
};
static const int ROUND_PREC_MAX = 1 + (int) ARRAY_LEN( ROUND_PREC );

static const my_locale_t DEFAULT_LOCALE = {
	"en_EN", '.', ',', 3, 2, 2, "$", "USD", 'l', 'l', '-', '+',
	"%m/%d/%Y", "%a %b %d %Y", "%H:%M", "%H:%M:%S %Z", "AM", "PM",
	{
		"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep",
		"Oct", "Nov", "Dec"
	},
	{
		"January", "February", "March", "April", "May", "June", "July",
		"August", "September", "October", "November", "December"
	},
	{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" },
	{
		"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday",
		"Friday", "Saturday"
	},
};

static const char *DEFAULT_ZONE = "GMT";

char *PerlIO_fgets( char *buf, size_t max, PerlIO *stream );

char *my_strncpy( char *dst, const char *src, unsigned long len );
char *my_strcpy( char *dst, const char *src );
char *my_itoa( char* str, int value, int radix );

#define find_or_create_tv(cxt,tv,tid) \
	if( ! ( (tv) = find_thread_var( (cxt), (tid) ) ) ) \
		(tv) = create_thread_var( (cxt), (tid) )

my_thread_var_t *find_thread_var( my_cxt_t *cxt, UV tid );
my_thread_var_t *create_thread_var( my_cxt_t *cxt, UV tid );
void remove_thread_var( my_cxt_t *cxt, my_thread_var_t *tv );
void cleanup_my_utils( my_cxt_t *cxt );

void copy_tm_to_vdatetime( struct tm *src, my_vdatetime_t *dst );
void free_locale_alias( my_cxt_t *cxt );
void read_locale_alias( my_cxt_t *cxt );
const char *get_locale_format_settings( my_cxt_t *cxt, const char *id, my_locale_t *locale );
int _int_strftime( my_thread_var_t *tv, char *str, int maxlen, const char *format, my_vdatetime_t *stime );
size_t _int_strfmon( my_thread_var_t *tv, char *str, size_t maxsize, const char *format, ... );
int parse_timezone( my_cxt_t *cxt, const char *tz, my_vtimezone_t *vtz );
#define read_timezone parse_timezone
my_vdatetime_t *apply_timezone( my_thread_var_t *tv, time_t *timer );
char *_int_number_format( double value, char *str, int maxlen, int fd, char dp, char ts, char ns, char ps, int zf, char fc );
double _my_round( double num, int prec );

#endif
