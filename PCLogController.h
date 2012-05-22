/*
   GNUstep ProjectCenter - http://www.gnustep.org/experience/ProjectCenter.html

   Copyright (C) 2001 Free Software Foundation

   This file is part of GNUstep.

   This application is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This application is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.
*/

#ifndef _PCLOGCONTROLLER_H
#define _PCLOGCONTROLLER_H

#import <AppKit/AppKit.h>
#import <AppKit/NSTextView.h>

#ifdef _PCLOGCONTROLLER_M
#	import "CritSectEx.h"
#	import "queue"
#endif

#define INFO	0
#define STATUS	1
#define WARNING	2
#define ERROR	3

#ifdef __cplusplus
extern "C" {
#endif

extern char lastPCLogMsg[2048];

// --- Functions
int
PCLog(id sender, int tag, const char *fileName, int lineNr, NSString* format, va_list args);
int
PCLogInfo(id sender, const char *fileName, int lineNr, NSString* format, ...);
int
PCLogStatus(id sender, const char *fileName, int lineNr, NSString* format, ...);
int
vPCLogStatus(id sender, const char *fileName, int lineNr, NSString* format, va_list args);
int
PCLogWarning(id sender, const char *fileName, int lineNr, NSString* format, ...);
int
PCLogError(id sender, const char *fileName, int lineNr, NSString* format, ...);
BOOL PCLogSetActive(BOOL active);
BOOL PCLogActive();
BOOL PCLogHasBGServer();
BOOL PCLogSetHasBGServer(BOOL hasBGServer);

// when using PCLog from an application that is not a regular ObjC 'NSApplication', i.e.
// that does not have a global pool: allocates an NSAutoReleasePool.
void PCLogAllocPool();

#ifdef __cplusplus
}
#endif

typedef struct PCLogEntry {
	NSString *logMessage;
	int tag, lineNr;
	id sender;
	const char *fileName;
#ifdef __cplusplus
	PCLogEntry(id _sender, int _tag, const char *_fileName, int _lineNr, NSString* message)
	{
		logMessage = [message retain];
		tag = _tag, lineNr = _lineNr;
		sender = [_sender retain];
		fileName = strdup(_fileName);
	}
	~PCLogEntry()
	{
		[logMessage release];
		[sender release];
		free( (void*) fileName);
	}
#endif
} PCLogEntry;

#ifdef __cplusplus
	typedef std::queue<PCLogEntry*>	PCLogMessageQueue;

	template <class qElem> inline size_t queueSizeAndFront(CRITSECT *cs, std::queue<qElem> *q, qElem *front, bool pop, bool *to)
	{ size_t n;
		if( cs ){
		  CRITSECT::Scope scope(cs, 1000);
			n = q->size();
			if( n > 0 ){
				if( front ){
					*front = q->front();
				}
				if( pop ){
					q->pop();
				}
			}
			if( to ){
				*to = scope.TimedOut();
			}
		}
		else{
			n = q->size();
			if( n > 0 ){
				if( front ){
					*front = q->front();
				}
				if( pop ){
					q->pop();
				}
			}
			if( to ){
				*to = false;
			}
		}
		return n;
	}

#else
	typedef void*					PCLogMessageQueue;
#endif

@class NSTextView;

@interface PCLogController : NSObject
{
//	IBOutlet NSPanel	*panel;
	IBOutlet NSWindow	*panel;
	IBOutlet NSTextView	*textView;

	NSMutableDictionary	*textAttributes;
	NSDateFormatter	*dateFormatter;
#ifdef _PCLOGCONTROLLER_M
	CRITSECT			*csex, *fifoLock;
	HANDLE			logNudge;
#else
	void				*csex, *fifoLock;
	void*			logNudge;
#endif
	PCLogMessageQueue	*msgQueue;
	BOOL				hasBGServer;
@public
	BOOL panelClosed, panelActive, panelVisible;
	NSThread			*loggerThread;
}

+ (PCLogController *)sharedLogController:(BOOL)startsActive;

- (id) initActive:(BOOL)startsActive;
- (void)showPanel;
- (void)setActive:(BOOL)active;
- (void)logMessage:(NSString *)message withTag:(int)tag sender:(id)sender
				withFileName:(const char*)fileName withLineNr:(int)lineNr;
- (void)putMessageOnScreenWithHeader:(NSAttributedString *)message Header:(NSAttributedString*)header;
// delegate functions:
- (BOOL) windowShouldClose:(id)sender;
- (void) windowWillClose:(NSNotification*) notification;

@property (retain) NSWindow			*panel;
@property (retain) NSTextView			*textView;
@property (retain) NSMutableDictionary	*textAttributes;
@property (retain) NSDateFormatter		*dateFormatter;
@property		BOOL					hasBGServer;
@end

@class NSTextViewDelegate;

@interface PCLDelegate : NSObject

- (void) textViewDidChangeTypingAttributes:(NSNotification*) notification;

@end

@interface PanelDelegate : NSObject

- (BOOL) windowShouldClose:(id)sender;
- (void) windowWillClose:(NSNotification*) notification;

@end

#endif
