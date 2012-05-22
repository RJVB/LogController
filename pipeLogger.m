#import <AppKit/AppKit.h>

#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

#include <errno.h>
#include <signal.h>

#include <sys/types.h>
#include <unistd.h>

#include <syslog.h>

#include <time.h>

#import "PCLogController.h"

pid_t pid, caller_pid;
int f1= -1, f0= -1;
FILE *fp= NULL;
int handle_sig_called= 0;
char tty_device[256], *buffer;

#if !defined(linux) && !defined(__MACH__)
extern char *sys_errlist[];
extern int sys_nerr;
#endif

void notify_exit_to_caller()
{
	if( caller_pid){
		fprintf( stderr, "Sending SIGUSR2 to caller %d", caller_pid);
		errno= 0;
		kill( caller_pid, SIGUSR2);
		if( errno && errno< sys_nerr)
			fprintf( stderr, " (%s)", sys_errlist[errno]);
		fputc( '\n', stderr);
		sleep(2);
	}
}

void ignore_handler(int sig)
{
#ifdef DEBUG
	fprintf( stderr, "Ignoring signal %d\n", sig);
#endif
	signal( sig, ignore_handler);
}

void clean_up( int action, char *mem)
{  static char *Mem= NULL;

	if( !action){
		Mem= mem;
	}
	else{
		if( Mem){
			free( Mem);
		}
		close( f0);
		close( f1);
		closelog();
		sleep(1);
		exit(action);
	}
}

typedef void (*int_method)(int);

static int_method alarm_method= NULL;

void call_alarm_call( int action )
{
	if( action== SIGALRM ){
		signal( SIGALRM, SIG_IGN );
		if( alarm_method ){
			(*alarm_method)( action );
		}
		signal( SIGALRM, call_alarm_call );
	}
}

unsigned int set_alarm_call( unsigned int interval, int_method fun)
{
	alarm_method= fun;
	signal( SIGALRM, call_alarm_call );
	return( alarm( interval ) );
}

#define dev_null	1
#define NULL_DEVICE dev_null
#define CONSOLE_DEVICE	"/dev/console"

void handle_sig(int sig)
{  static char called= 0;
	switch( sig){
		case SIGALRM:
			errno= 0;
			if( caller_pid ){
				  /* send test signal (shouldn't arrive at the other side)	*/
				if( kill( caller_pid, 0 ) ){
					if( errno== ESRCH){
						fprintf( stderr, "xpipe(%d): caller process %d is gone - exitting\n", sig, caller_pid );
						clean_up( sig, buffer );
					}
				}
				else{
				  time_t timer= time(NULL);
					fprintf( stderr, "xpipe(%d): %d is still there at %s\n",
						sig, caller_pid,
						asctime( localtime(&timer) )
					);
				}
				  /* reinstall ourselves	*/
				set_alarm_call( 1800, handle_sig );
			}
			break;
		case SIGHUP:
			if( !called ){
				fputs( "xpipe: received HUP - detaching from tty\n", stderr);
				fflush( stderr);
#if NULL_DEVICE == dev_null
				freopen( "/dev/null", "r", stdin);
				freopen( "/dev/null", "a", stdout);
				freopen( "/dev/null", "a", stderr);
#else
				freopen( CONSOLE_DEVICE, "r", stdin);
				freopen( CONSOLE_DEVICE, "a", stdout);
				freopen( CONSOLE_DEVICE, "a", stderr);
#endif
				called++;
				signal( SIGHUP, SIG_IGN);
				signal( SIGUSR1, handle_sig);
				signal( SIGUSR2, handle_sig);
			}
			else
				signal( SIGHUP, handle_sig);
			break;
		case SIGINT:
			fputs( "xpipe: interrupt - exitting\n", stderr);
			fflush( stderr);
			signal( SIGINT, SIG_IGN );
			clean_up(sig, buffer);
			break;
		case SIGUSR1:{
			if( called ){
			  int succes;
				errno= 0;
				succes= freopen( tty_device, "a+", stdout) && freopen( tty_device, "a+", stderr);
				if( succes && !errno ){
					fputs( "xpipe: re-attached to ", stderr);
					fputs( tty_device, stderr);
					fputc( '\n', stderr);
					fflush( stderr);
					called--;
					signal( SIGHUP, handle_sig);
					signal( SIGUSR1, SIG_IGN);
					signal( SIGUSR2, SIG_IGN);
				}
				else{
					syslog( LOG_NOTICE, "xpipe: can't reopen %s: %m\n", tty_device);
					signal( SIGUSR1, SIG_IGN);
#if NULL_DEVICE == dev_null
					freopen( CONSOLE_DEVICE, "a", stdout);
					freopen( CONSOLE_DEVICE, "a", stderr);
#else
					fputs( "xpipe: can't reopen ", stderr);
					fputs( tty_device, stderr);
					fputs( ": ", stderr);
					if( errno< sys_nerr)
						fputs( sys_errlist[errno], stderr);
					fputc( '\n', stderr);
					fflush( stderr);
					clean_up(1, buffer);
#endif
				}
			}
			else
				signal( SIGUSR1, handle_sig);
			break;
		}
		case SIGUSR2:
			if( called){
			  char terminal[128];
				terminal[0]= '\0';
				fgets( terminal, 127, fp);
				if( freopen( terminal, "r+", stdin) && freopen( terminal, "a+", stdout) && freopen( terminal, "a+", stderr) ){
					fputs( "xpipe: re-attached to tty ", stderr);
					fputs( terminal, stderr);
					fputc( '\n', stderr);
					fflush( stderr);
					called--;
					signal( SIGHUP, handle_sig);
					signal( SIGUSR1, SIG_IGN);
					signal( SIGUSR2, SIG_IGN);
					strcpy( tty_device, terminal);
				}
				else{
					syslog( LOG_NOTICE, "xpipe: can't reopen %s: %m\n", terminal);
					signal( SIGUSR2, SIG_IGN);
#if NULL_DEVICE == dev_null
					freopen( CONSOLE_DEVICE, "a", stdout);
					freopen( CONSOLE_DEVICE, "a", stderr);
#else
					fputs( "xpipe: can't reopen ", stderr);
					fputs( terminal, stderr);
					fputs( ": ", stderr);
					if( errno< sys_nerr)
						fputs( sys_errlist[errno], stderr);
					fputc( '\n', stderr);
					fflush( stderr);
					clean_up(1, buffer);
#endif
				}
			}
			else
				signal( SIGUSR2, handle_sig);
			break;
		case SIGCONT:{
		  char comm[512];
			if( strlen(buffer) ){
				fputs( buffer, stdout);
			}
/*
			sprintf( comm, "ps -flu %d | sort -bn +3.0 -4.0 | fgrep -v -e 'sort -bn +3.0 -4.0' ; w",
				getuid()
			);
			system( comm );
 */
			fputs( "\033[5m", stdout );
			system( "w" );
			fputs( "\033[0m", stdout );
			fflush( stdout);
			fputs( "\t**[Flush]**\t\n", stderr);
			fflush( stdin);
			fflush( stderr);
			*buffer= '\0';
			signal( SIGCONT, handle_sig);
			break;
		}
		default:
			return;
			break;
	}

	handle_sig_called= 1;
	return;
}

int read_pipe( int f0, int f1, int bufsize)
{ char *c, C, *t;
  extern char *ttyname();
  pid_t Pid;

	if( bufsize== 0){
		c= &C;
		bufsize= 1;
	}
	else{
		if( !(buffer= c= calloc( bufsize, 1)) ){
			perror( "xpipe: can't get buffer memory");
			return(-2);
		}
		clean_up( 0, c);
	}

	if( !(t= ttyname( fileno(stdin) ) ) ){
		perror( "xpipe: can't get terminal name");
		return(-20);
	}
	strncpy( tty_device, t, 255);

	signal( SIGHUP, handle_sig);
	signal( SIGINT, handle_sig);
	signal( SIGCONT, handle_sig);
	signal( SIGUSR1, SIG_IGN);
	signal( SIGUSR2, SIG_IGN);
	openlog("xpipe", LOG_PID|LOG_CONS, LOG_USER);

	sleep(1);
	read( f0, &Pid, sizeof(pid_t));
	if( Pid== pid)
		while( Pid== pid){
			write( f1, &Pid, sizeof(pid_t));
			sleep(1);
			read( f0, &Pid, sizeof(pid_t));
		}
	putw( Pid, stdout);

	if( fp){
	  char *d;
		/* this gives better stream behaviour	*/
		d= fgets( c, bufsize, fp);
		while( d || handle_sig_called ){
			if( *c){
				fputs( c, stdout);
				fflush( stdout);
				*c= '\0';
			}
			handle_sig_called= 0;
			d= fgets( c, bufsize, fp);
		}
	}
	else{
		while( read( f0, c, bufsize) || handle_sig_called ){
			fputs( c, stdout);
			fflush( stdout);
			*c= '\0';
			handle_sig_called= 0;
		}
	}
	clean_up(1, buffer );
	return( 0);
}


#ifndef PIPE_MAX
#	define PIPE_MAX	1024
#endif

int main( int argc, char **argv)
{ char *geo= NULL;
  int i, bufsize= PIPE_MAX;
  char *env;

	pid= getpid();
	if( (env = getenv("XPIPE-FILDES")) ){
		if( sscanf( env, "%d,%d", &f0, &f1)!= 2){
			fprintf( stderr, "xpipe: $XPIPE-FILDES=%s : need 2 file descriptors (%d)\n",
				env, errno
			);
		}
	}
	if( (env = getenv("XPIPE-BUFSIZE")) ){
		if( sscanf( env, "%d", &bufsize)!= 1 || bufsize< 0 ){
			fprintf( stderr, "xpipe: invalid buffersize $XPIPE-BUFSIZE=%s (using %d)\n",
				env, (bufsize= PIPE_MAX)
			);
		}
	}
	for( i= 1; i< argc; i++){
		if( !strcmp( argv[i], "-fildes") ){
			if( ++i< argc){
				if( sscanf( argv[i], "%d,%d", &f0, &f1)!= 2){
					perror( "xpipe (fildes mode):");
				}
			}
			else{
				fprintf( stderr, "xpipe: nead 2 pipe file descriptors after -fildes in,out\n");
				exit(1);
			}
		}
		else if( !strcmp( argv[i], "-bufsize") ){
			if( ++i< argc){
				if( sscanf( argv[i], "%d", &bufsize)!= 1 || bufsize< 0 ){
					fprintf( stderr, "xpipe: invalid buffersize after -bufsize (using %d)\n",
						(bufsize= PIPE_MAX)
					);
				}
			}
			else{
				fprintf( stderr, "xpipe: nead a buffersize after -bufsize (using %d)\n",
					(bufsize= PIPE_MAX)
				);
			}
		}
	}
// 	if( f0 >= 0 && f1 >= 0 ){
// 		setsid();
// 	}

#ifdef DEBUG
	fprintf( stderr, "Fin=%d Fout=%d BUFSIZ=%d\n", f0, f1, bufsize);
	fflush(stderr);
#endif
	if( f0 >= 0){
	  int p;
		signal( SIGUSR2, ignore_handler );
		signal( SIGUSR1, ignore_handler );
		signal( SIGHUP, ignore_handler );
		signal( SIGCONT, ignore_handler );
#ifdef DEBUG
		  /* Turn on logging	*/
		fputs( "\033]46;xpipe.log\033[?46h", stderr);
		fprintf( stderr, "Writing pid=%d to Fout and pausing ", pid);
		fflush(stderr);
#endif
		i= write( f1, &pid, sizeof(pid_t) );
		p= pause();
		signal( SIGUSR1, SIG_DFL );
#ifdef DEBUG
		fprintf( stderr, "- returns %d,%d\n", i, p);
		fflush( stderr);
#endif
#ifdef DEBUG
		fprintf( stderr, "reading caller_pid from Fin", pid);
		fflush(stderr);
#endif
		i= read( f0, &caller_pid, sizeof(pid_t) );
#ifdef DEBUG
		fprintf( stderr, "- returns %d; caller_pid=%d\n", i, caller_pid);
		fflush(stderr);
#endif
		i= read( f0, &caller_pid, sizeof(pid_t) );
#ifdef DEBUG
		fprintf( stderr, "- returns %d; caller_pid=%d\n", i, caller_pid);
		fflush(stderr);
#endif
		i= read( f0, &caller_pid, sizeof(pid_t) );
#ifdef DEBUG
		fprintf( stderr, "- returns %d; caller_pid=%d\n", i, caller_pid);
		fflush(stderr);
#endif
		i= read( f0, &caller_pid, sizeof(pid_t) );
#ifdef DEBUG
		fprintf( stderr, "- returns %d; caller_pid=%d\n", i, caller_pid);
		fflush(stderr);
#endif
		if( !(fp= fdopen( f0, "r")) ){
			perror( "xpipe: can't create filepointer");
			sleep(1);
		}
		atexit( notify_exit_to_caller);
		  /* Turn off logging	*/
		fputs( "\033[?46l", stderr); fflush( stderr);
		set_alarm_call( 1800, handle_sig );
		exit( read_pipe(f0, f1, bufsize) );
	}
	else{
//		fprintf( stderr, "xpipe: usage xpipe [-bufsize #] -fildes <f0>\n");
//		exit( 1);
	  char buffer[1024];
	  long line = 1;
		PCLogAllocPool();
		while( fgets( buffer, sizeof(buffer), stdin ) ){
			PCLogInfo( [NSApplication sharedApplication], @"stdin", line, @"%s\n", buffer );
			line += 1;
		}
		exit(0);
	}
}
