/*
 *  fwInitialiser.m
 *  LogController
 *
 *  Created by René J.V. Bertin on 20111215.
 *  Copyright 2011 INRETS/LCPC — LEPSIS. All rights reserved.
 *
 */

#import <Foundation/Foundation.h>
#import <libgen.h>

// PCLogController.mm is ObjC++ which doesn't seem to support initialisers with the argument list

__attribute__((constructor))
static void PCLoginitialiser( int argc, char **argv, char **envp )
{ NSAutoreleasePool *pool = NULL;
  extern void SetProgName(int argc, char **argv);
//#ifndef EMBEDDED_FRAMEWORK
	pool = [[NSAutoreleasePool alloc] init];
//#endif
	SetProgName( argc, argv );
	if( pool ){
		[pool drain];
		pool = NULL;
	}
}

