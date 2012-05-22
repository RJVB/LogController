/*
 *  kk.cpp
 *  sfCAN
 *
 *  Created by René J.V. Bertin on 20110705.
 *  Copyright 2011 IFSTTAR — LEPSIS. All rights reserved.
 *
 */


#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>

#include "../timing.h"

#ifndef CRITSECT
#	define CRITSECT	CritSectEx
#endif

#include "CritSectEx.h"

#ifdef __GNUC__
#	include <semaphore.h>
#endif


#define SLEEPTIMEBG	3.14159
#define SLEEPTIMEFG	2.71828
#undef BUSYSLEEPING

#define LOCKSCOPEBG
#define LOCKSCOPEFG

CSEHandle *csex;
bool bgRun = true;

double tStart;

#if defined(WIN32) || defined(_MSC_VER)
	char *winError( DWORD err )
	{ static char errStr[512];
		FormatMessage( FORMAT_MESSAGE_FROM_SYSTEM
				    | FORMAT_MESSAGE_IGNORE_INSERTS | FORMAT_MESSAGE_MAX_WIDTH_MASK,
				    NULL, err, 0, errStr, sizeof(errStr), NULL );
		return errStr;
	}
#	ifndef __MINGW32__
	static int snprintf( char *buffer, size_t count, const char *format, ... )
	{ int n;
		va_list ap;
		va_start( ap, format );
		n = _vsnprintf( buffer, count, format, ap );
		if( n < 0 ){
			buffer[count-1] = '\0';
		}
		return n;
	}
#	endif

	void MMSleep(double seconds)
	{
		timeBeginPeriod(1);
		WaitForSingleObjectEx( GetCurrentThread(), (DWORD)(seconds * 1000), TRUE );
		timeEndPeriod(1);
	}
#else
#	define MMSleep(s)	usleep((useconds_t)(s*1000000))
#endif

#ifdef __GNUC__

#include <errno.h>
#include <signal.h>
#include <sys/time.h>

#endif

HANDLE nudgeEvent = NULL;

#if defined(WIN32) || defined(_MSC_VER)
DWORD WINAPI bgThread2Nudge( LPVOID dum )
#else
void *bgThread2Nudge(void *dum)
#endif
{ unsigned long ret;
	fprintf( stderr, "## bgThread2Nudge starting to wait for nudge event at t=%g\n", HRTime_Time() - tStart );
	ret = WaitForSingleObject( nudgeEvent, INFINITE );
	fprintf( stderr, "## WaitForSingleObject( nudgeEvent, INFINITE ) = %lu at t=%g\n", ret, HRTime_Time() - tStart );
#if defined(WIN32) || defined(_MSC_VER)
	return true;
#else
	return (void*) true;
#endif
}

#if defined(WIN32) || defined(_MSC_VER)
DWORD WINAPI bgCSEXaccess( LPVOID dum )
#else
void *bgCSEXaccess(void *dum)
#endif
{ static unsigned long n = 0;
	fprintf( stderr, "entering bgCSEXaccess thread %lu at t=%gs\n", GetCurrentThreadId(), HRTime_toc() );
	while( bgRun ){
	  double t0, t1;
		if( IsCSEHandleLocked(csex) ){
			fprintf( stderr, "\tbgCSEXaccess waiting for csex lock\n" );
		}
		t0 = HRTime_toc();
		{
#ifdef LOCKSCOPEBG
		  CSEScopedLock *scope = ObtainCSEScopedLock(csex);
#else
		  unsigned char unlock = LockCSEHandle(csex);
#endif
			t1 = HRTime_toc();
			n += 1;
			fprintf( stderr, "## got csex lock #%lu=%d at t=%g after %gs; starting %g s wait\n",
					n, IsCSEHandleLocked(csex), t1, t1-t0, SLEEPTIMEBG ); fflush(stderr);
#ifndef BUSYSLEEPING
			MMSleep(SLEEPTIMEBG);
#else
			do{
				t1 = HRTime_toc();
			} while (t1-t0 < SLEEPTIMEBG);
#endif
			fprintf( stderr, "\tbgCSEXaccess wait #%lu ended at t=%gs; csex lock=%d\n",
				n, HRTime_toc(), IsCSEHandleLocked(csex) ); fflush(stderr);
#ifndef LOCKSCOPEFG
			UnlockCSEHandle( csex, unlock );
#else
			scope = ReleaseCSEScopedLock(scope);
#endif
		}
		// just to give the other thread a chance to get a lock:
#if defined(WIN32) || defined(_MSC_VER)
		Sleep(1);
#else
		usleep(1000);
#endif
	}
	fprintf( stderr, "exiting bgCSEXaccess thread at t=%gs\n", HRTime_toc() );
#if defined(WIN32) || defined(_MSC_VER)
	return true;
#else
	return (void*) true;
#endif
}

typedef struct kk {
	int count;
} kk;

void u1handler(int sig)
{
	fprintf( stderr, "process %lu (thread %p) received signal %d\n",
		   getpid(), pthread_self(), sig );
}

int main( int argc, char *argv[] )
{ int i;
  HANDLE bgThread;
#if 1
  char test[256], *head;
	test[0] = '\0';
	head = test;
	fprintf( stderr, "appending to test[%lu] with snprintf:\n", sizeof(test) );
	do{
	  int len = strlen(test), n;
	  size_t ni = strlen("0123456789");
		fprintf( stderr, "len(test[%lu])=%d, rem. %lu added", sizeof(test), len, (size_t)(sizeof(test) - len) ); fflush(stderr);
		n = snprintf( &test[len], (size_t)(sizeof(test) - len), "0123456789" );
		head += n;
		fprintf( stderr, " %d (head=", n ); fflush(stderr);
		fprintf( stderr, "%c) -> %lu\n", head[0], strlen(test) );
	} while( strlen(test) < sizeof(test)-1 );
	fprintf( stderr, "test = %s\n", test );
#endif
	init_HRTime();
	tStart = HRTime_Time();
	HRTime_tic();
	{ double t0;
	  long ret;
	  HANDLE hh;
		if( (hh = CreateSemaphore( NULL, 1, 0x7FFFFFFF, NULL )) ){
			t0 = HRTime_Time();
			ret = WaitForSingleObject(hh, (DWORD)(SLEEPTIMEFG*1000));
			t0 = HRTime_Time() - t0;
			fprintf( stderr, "WaitForSingleObject(hh,%u)==%lu took %g seconds\n",
				   (DWORD)(SLEEPTIMEFG*1000), ret, t0
			);
			t0 = HRTime_Time();
			ret = WaitForSingleObject(hh, (DWORD)(SLEEPTIMEFG*1000));
			t0 = HRTime_Time() - t0;
			fprintf( stderr, "WaitForSingleObject(hh,%u)==%lu took %g seconds\n",
				   (DWORD)(SLEEPTIMEFG*1000), ret, t0
			);
			CloseHandle(hh);
		}
		else{
#ifdef __GNUC__
			fprintf( stderr, "Error creating semaphore: %s\n", strerror(errno) );
#else
			fprintf( stderr, "Error creating semaphore: %s\n", winError(GetLastError()) );
#endif
		}

		ret = 0;
		YieldProcessor();
		fprintf( stderr, "sizeof(long)=%lu\n", sizeof(long) );
		_WriteBarrier();
		{ long oval, lbool;
		  void *ptr = NULL, *optr;
			oval = _InterlockedCompareExchange( (long*) &ret, 10L, 0L );
			fprintf( stderr, "_InterlockedCompareExchange(&ret==0, 10, 0) == %lu, ret==%lu\n", oval, ret );
			optr = InterlockedCompareExchangePointer( &ptr, (void*) fprintf, NULL );
			fprintf( stderr, "InterlockedCompareExchangePointer(&ptr==NULL, fprintf==%p, NULL) == %p, ret==%p\n",
				   fprintf, optr, ptr );
			_InterlockedIncrement( (long*) &ret );
			fprintf( stderr, "_InterlockedIncrement(&ret) ret=%lu\n", ret );
			_InterlockedDecrement( (long*) &ret );
			fprintf( stderr, "_InterlockedDecrement(&ret) ret=%lu\n", ret );
			_ReadWriteBarrier();
			lbool = false;
			_InterlockedSetTrue(&lbool);
			fprintf( stderr, "lbool = %ld\n", lbool );
			_InterlockedSetTrue(&lbool);
			fprintf( stderr, "lbool = %ld\n", lbool );
			_InterlockedSetFalse(&lbool);
			fprintf( stderr, "lbool = %ld\n", lbool );
		}
	}
#ifdef DEBUG
	{ CSEScopedLock *scope = ObtainCSEScopedLock(NULL);
		fprintf( stderr, "NULL testscope %p:locked==%u\n", scope, IsCSEScopeLocked(scope) );
		scope = ReleaseCSEScopedLock(scope);
	}
#endif

	csex = CreateCSEHandle(4000);
	if( !csex ){
		fprintf( stderr, "Failure creating CSEHandle\n" );
		exit(1);
	}
	else{
		fprintf( stderr, "Created a '%s' CSEHandle with spinMax==%u\n", CSEHandleInfo(csex), csex->spinMax );
	}

	if( (nudgeEvent = CreateEvent( NULL, false, false, NULL )) ){
		if( (bgThread = CreateThread( NULL, 0, bgThread2Nudge, NULL, 0, NULL )) ){
			sleep(1);
			fprintf( stderr, "> t=%g SetEvent(nudgeEvent) = %d\n", HRTime_Time() - tStart, SetEvent(nudgeEvent) );
			WaitForSingleObject( bgThread, 5000 );
			CloseHandle(bgThread);
		}
	}
	if( (bgThread = CreateThread( NULL, 0, bgCSEXaccess, NULL, CREATE_SUSPENDED, NULL )) ){
		fprintf( stderr, "csex is %slocked\n", (IsCSEHandleLocked(csex))? "" : "not " );
		SetThreadPriority( bgThread, GetThreadPriority(GetCurrentThread()) );
		fprintf( stderr, "GetThreadPriority(GetCurrentThread()) = %d\n", GetThreadPriority(GetCurrentThread()) );
		ResumeThread(bgThread);
		i = 0;
		fprintf( stderr, "entering main csex locking loop at t=%gs\n", HRTime_toc() );
		while( i < 5 ){
		  double t0, t1;

			if( IsCSEHandleLocked(csex) ){
				fprintf( stderr, "\tmain loop waiting for csex lock\n" );
			}
			t0 = HRTime_toc();
			{
#ifdef LOCKSCOPEFG
			  CSEScopedLock *scope = ObtainCSEScopedLock(csex);
#else
			  unsigned char unlock = LockCSEHandle(csex);
#endif
				t1 = HRTime_toc();
				i += 1;
				fprintf( stderr, "> got csex lock #%d=%d at t=%g after %gs; starting %g s wait\n",
						i, IsCSEHandleLocked(csex), t1, t1-t0, SLEEPTIMEFG ); fflush(stderr);
#ifdef BUSYSLEEPING
				MMSleep(SLEEPTIMEFG);
#else
				do{
					t1 = HRTime_toc();
				} while (t1-t0 < SLEEPTIMEFG);
#endif
				fprintf( stderr, "\tmain loop wait #%d ended at t=%gs; csex lock=%d\n",
					i, HRTime_toc(), IsCSEHandleLocked(csex) ); fflush(stderr);
#ifndef LOCKSCOPEFG
				UnlockCSEHandle( csex, unlock );
#else
				scope = ReleaseCSEScopedLock(scope);
#endif
			}
			// just to give the other thread a chance to get a lock:
#if defined(WIN32) || defined(_MSC_VER)
			Sleep(1);
#else
			usleep(1000);
#endif
		}
		fprintf( stderr, "exiting main csex locking loop at t=%gs\n", HRTime_toc() );
		bgRun = false;
		WaitForSingleObject( bgThread, 5000 );
		CloseHandle(bgThread);
		fprintf( stderr, "Background loop finished at t=%gs\n", HRTime_toc() );
	}
	else{
		fprintf( stderr, "Failure creating bgCSEXaccess thread\n" );
	}
	DeleteCSEHandle(csex);
	exit(0);
}
