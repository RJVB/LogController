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

#define _PCLOGCONTROLLER_M

#undef BGSERVER

#import <Foundation/Foundation.h>
#import "PCLogController.h"
#import <libgen.h>

#import "CritSectEx.h"

NSAutoreleasePool *PCLogPool = NULL;
static NSString *ProgName = NULL;
char lastPCLogMsg[2048] = "";

static PCLogController *_logCtrllr = nil;

//#define PREFSNAME	(CFStringRef) @"org.gnustep.PCLogController"
#define PREFSNAME	kCFPreferencesCurrentApplication

int
PCLog(id sender, int tag, const char *fileName, int lineNr, NSString* format, va_list args)
{ NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
	[[PCLogController sharedLogController:YES]
		 logMessage:message
		 withTag:tag
		 sender:sender withFileName:fileName withLineNr:lineNr];
	[message getCString:lastPCLogMsg maxLength:sizeof(lastPCLogMsg) encoding:NSUTF8StringEncoding];
	return [message length];
}

int
PCLogInfo(id sender, const char *fileName, int lineNr, NSString* format, ...)
{ va_list ap;
  int ret;

  va_start(ap, format);
  ret = PCLog(sender, INFO, fileName, lineNr, format, ap);
  va_end(ap);
  return ret;
}

int
PCLogStatus(id sender, const char *fileName, int lineNr, NSString* format, ...)
{ va_list ap;
  int ret;

  va_start(ap, format);
  ret = PCLog(sender, STATUS, fileName, lineNr, format, ap);
  va_end(ap);
  return ret;
}

int
vPCLogStatus(id sender, const char *fileName, int lineNr, NSString* format, va_list args)
{ int ret;

  ret = PCLog(sender, STATUS, fileName, lineNr, format, args);
  return ret;
}

int
PCLogWarning(id sender, const char *fileName, int lineNr, NSString* format, ...)
{ va_list ap;
  int ret;

  va_start(ap, format);
  ret = PCLog(sender, WARNING, fileName, lineNr, format, ap);
  va_end(ap);
	return ret;
}

int
PCLogError(id sender, const char *fileName, int lineNr, NSString* format, ...)
{ va_list ap;
  int ret;

  va_start(ap, format);
  ret = PCLog(sender, ERROR, fileName, lineNr, format, ap);
  va_end(ap);
	return ret;
}

BOOL PCLogSetActive(BOOL active)
{ BOOL ret;
	if( _logCtrllr ){
		ret = _logCtrllr->panelActive;
		[_logCtrllr setActive:active];
	}
	else{
		ret = NO;
		[PCLogController sharedLogController:active];
	}
	return ret;
}

BOOL PCLogActive()
{ BOOL ret;
	if( _logCtrllr ){
		ret = _logCtrllr->panelActive;
	}
	else{
		ret = NO;
	}
	return ret;
}

BOOL PCLogHasBGServer()
{ BOOL ret;
	if( _logCtrllr ){
		ret = [_logCtrllr hasBGServer];
	}
	else{
		ret = NO;
	}
	return ret;
}

BOOL PCLogSetHasBGServer(BOOL hasBGServer)
{ BOOL ret;
	if( _logCtrllr ){
		ret = [_logCtrllr hasBGServer];
		[_logCtrllr setHasBGServer:hasBGServer];
	}
	else{
		ret = NO;
	}
	return ret;
}

@interface PCLogController (Private)
- (void) PCLogBGController;
@end

@implementation PCLogController (Private)

- (void) PCLogBGController
{ NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  PCLogEntry *entry = NULL;
	loggerThread = [NSThread currentThread];
	[loggerThread setName:[[NSString alloc] initWithFormat:@"[%@ PCLogBGController]", self ] ];
	hasBGServer = YES;
	NSLog( @"Loggerthread %@ started", loggerThread );
	while( ![loggerThread isCancelled] && hasBGServer
		 && WaitForSingleObject(logNudge, INFINITE) != WAIT_ABANDONED
	){
		while( queueSizeAndFront( fifoLock, msgQueue, &entry, true, nil )
			 && ![loggerThread isCancelled]
			 && hasBGServer
		){
			[self logMessage:entry->logMessage withTag:entry->tag sender:entry->sender
			    withFileName:entry->fileName withLineNr:entry->lineNr];
			delete entry;
		}
		[textView setNeedsDisplay:YES];
	}
	NSLog( @"Loggerthread %@ exiting (isCancelled:%s)", loggerThread, ([loggerThread isCancelled])? " yes" : " no" );
	loggerThread = nil;
	SetEvent(logNudge);
	[pool drain];
}

@end

@implementation PCLogController

// ===========================================================================
// ==== Class methods
// ===========================================================================

+ (PCLogController *)sharedLogController:(BOOL)startsActive
{
  if (!_logCtrllr)
    {
      _logCtrllr = [[PCLogController alloc] initActive:startsActive];
//			NSLog( @"Opened %@", _logCtrllr );
    }

  return _logCtrllr;
}

@synthesize hasBGServer;

// ===========================================================================
// ==== Init and free
// ===========================================================================

- (id)initActive:(BOOL)startsActive
{ NSFont *font = nil;
  NSDictionary *textAttrs = NULL;
  BOOL forceVisible = NO;

  if (!(self = [super init]))
    {
      return nil;
    }

  if( [NSBundle loadNibNamed:@"PCLogController" owner:self] == NO ){
			NSLog(@"PCLogController[init]: error loading NIB file!");
			panel = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 512, 256)
						styleMask:NSClosableWindowMask|NSTitledWindowMask
						 |NSMiniaturizableWindowMask|NSResizableWindowMask
						backing:NSBackingStoreBuffered
						defer:NO];
			[panel setFrameAutosaveName:@"PCLogController"];
			if( ![panel setFrameUsingName: @"PCLogController"] ){
				[panel center];
			}

			textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
			[panel setContentView:textView];
	}
	else{
		[panel setFrameAutosaveName:@"PCLogController"];
		if( ![panel setFrameUsingName: @"PCLogController"] ){
			[panel center];
		}
	}

	if( !CFPreferencesAppSynchronize( PREFSNAME )
		 || !(textAttrs = (NSDictionary*) CFPreferencesCopyAppValue( (CFStringRef)@"textAttributes", PREFSNAME ))
	){
		font = [NSFont userFixedPitchFontOfSize:[NSFont smallSystemFontSize]];
		textAttributes =
			[NSMutableDictionary dictionaryWithObject:font forKey:NSFontAttributeName];
//		CFPreferencesSetAppValue( (CFStringRef) @"textAttributes", (CFPropertyListRef) textAttributes, PREFSNAME );
	}
	else{
		textAttributes = [NSMutableDictionary dictionaryWithDictionary:textAttrs];
	}
	[textAttributes retain];

	panelClosed = NO;
	if( !CFPreferencesAppSynchronize( PREFSNAME )
		 || !(panelVisible = (BOOL) (CFPreferencesCopyAppValue( (CFStringRef)@"panelVisible", PREFSNAME ) != NULL) )
	){
		panelVisible = YES;
//		CFPreferencesSetAppValue( (CFStringRef) @"panelVisible", (CFPropertyListRef) panelVisible, PREFSNAME );
	}
	else{
		forceVisible = YES;
	}

	dateFormatter = [[[NSDateFormatter alloc] init] retain];
	[dateFormatter setDateStyle:NSDateFormatterShortStyle];
	[dateFormatter setTimeStyle:NSDateFormatterMediumStyle];

//	[textView setDelegate:[[[PCLDelegate alloc] init] autorelease]];

//	[panel setDelegate:[[PanelDelegate alloc] init]];
	[panel setDelegate:self];
	if( startsActive ){
		panelActive = YES;
		[panel orderFront:nil];
		if( !panelVisible && forceVisible ){
			[panel miniaturize:panel];
		}
	}
	else{
		if( !(panelVisible && forceVisible) ){
			[panel miniaturize:panel];
			panelVisible = NO;
		}
		panelActive = NO;
	}
//	CFPreferencesSetAppValue( (CFStringRef) @"panelActive", (CFPropertyListRef) panelActive, PREFSNAME );
#ifdef BGSERVER
	fifoLock = new CRITSECT(4000);
	msgQueue = new PCLogMessageQueue;
	logNudge = CreateEvent( NULL, FALSE, FALSE, NULL );
	[NSThread detachNewThreadSelector:@selector(PCLogBGController) toTarget:self withObject:nil];
#else
	csex = new CRITSECT(4000);
#endif
	if( textAttrs ){
		CFRelease(textAttrs);
	}
	return self;
}

- (id)init
{ BOOL active;
	if( !CFPreferencesAppSynchronize( PREFSNAME )
		 || !(active = (CFPreferencesCopyAppValue( (CFStringRef)@"panelActive", PREFSNAME ) != NULL) )
	){
		active = YES;
	}
	return [self initActive:active];
}

- (void)dealloc
{
//  NSLog(@"PCLogController: dealloc %@", self);
//	CFPreferencesSetAppValue( (CFStringRef) @"textAttributes", (CFPropertyListRef) textAttributes, PREFSNAME );
	CFPreferencesAppSynchronize( PREFSNAME );
	[textAttributes release];
	[dateFormatter release];
	[[NSBundle bundleForClass:[self class]] unload];
	if( loggerThread ){
		hasBGServer = NO;
		[loggerThread cancel];
		SetEvent(logNudge);
		WaitForSingleObject(logNudge, INFINITE);
	}
	if( csex ){
		delete csex;
	}
	if( fifoLock ){
		delete fifoLock;
	}
	if( logNudge ){
		CloseHandle(logNudge);
	}
	if( msgQueue ){
		delete msgQueue;
	}
	if( _logCtrllr == self ){
		_logCtrllr = nil;
	}
	[super dealloc];
}

- (void)showPanel
{
	[panel makeKeyAndOrderFront:self];
}

- (void)setActive:(BOOL)active
{
	if( !panelActive && active && !panelVisible ){
		[self showPanel];
		panelClosed = NO;
	}
	panelActive = active;
}

- (void)logMessage:(NSString *)text withTag:(int)tag sender:(id)sender
				withFileName:(const char*)fileName withLineNr:(int)lineNr;
{
  NSString			*headerText = nil, *FileLine = nil;
  NSAttributedString	*header = nil, *message = nil;

	if( !panelActive ){
		return;
	}

	if( msgQueue && logNudge && [NSThread currentThread] != loggerThread ){
	  PCLogEntry *msg = new PCLogEntry(sender, tag, fileName, lineNr, text);
	  CRITSECT::Scope scope( fifoLock, 1000 );
		msgQueue->push(msg);
		SetEvent(logNudge);
		return;
	}

	if( !ProgName ){
		ProgName = [[NSString string] retain];
	}
	if( fileName ){
		FileLine = [NSString stringWithFormat:@"::%s:%d", fileName, lineNr ];
	}
	else{
		FileLine = [NSString string];
	}
	if( !text || ![text length] ){
		// we output a completely blank line, without time and app stamps
		headerText = [NSString string];
		text = nil;
	}
	else if( [text isEqualToString:@"\n"] ){
		// we always append a newline, so a string with only a newline is of no interest
		/* noop */
//		// but this blocks the output whateversomehow, so we just output something.
//		headerText = [NSString stringWithFormat:@"%@ %@[%@]%@\n",
//									 [dateFormatter stringFromDate:[NSDate date]], ProgName, [sender className], FileLine];
		text = nil;
	}
	else if( [text hasSuffix:@"\n"] ){
		headerText = [NSString stringWithFormat:@"%@ %@%@: ",
				    [dateFormatter stringFromDate:[NSDate date]], ProgName, FileLine];
	}
	else{
		headerText = [NSString stringWithFormat:@"%@ %@%@: ",
				[dateFormatter stringFromDate:[NSDate date]], ProgName, FileLine];
		text = [text stringByAppendingString:@"\n"];
	}

	if( headerText ){
		/*@synchronized(panel)*/{
		CRITSECT::Scope scope(csex, 5000);
			[textAttributes
			 setObject:[NSColor colorWithDeviceRed:0.45 green:0.35 blue:0.45 alpha:1.0]
			 forKey:NSForegroundColorAttributeName];
			header = [[[NSAttributedString alloc] initWithString:headerText
											  attributes:textAttributes] autorelease];
			switch (tag)
			{
				case INFO:
					[textAttributes
					 setObject:[NSColor colorWithDeviceRed:0.0 green:0.0 blue:0.0 alpha:1.0]
					 forKey:NSForegroundColorAttributeName];
					break;
				case STATUS:
					[textAttributes
					 setObject:[NSColor colorWithDeviceRed:0.0 green:0.25 blue:0.0 alpha:1.0]
					 forKey:NSForegroundColorAttributeName];
					break;

				case WARNING:
					[textAttributes
					 setObject:[NSColor colorWithDeviceRed:0.56 green:0.45 blue:0.0 alpha:1.0]
					 forKey:NSForegroundColorAttributeName];
					break;

				case ERROR:
					[textAttributes
					 setObject:[NSColor colorWithDeviceRed:0.63 green:0.0 blue:0.0 alpha:1.0]
					 forKey:NSForegroundColorAttributeName];
					break;

				default:
					break;
			}

			if( text ){
				message = [[[NSAttributedString alloc] initWithString:text
												  attributes:textAttributes] autorelease];
			}
			else{
				message = [[[NSAttributedString alloc] initWithString:@"\n"
												  attributes:textAttributes] autorelease];
			}
			if( panelClosed /*|| ![panel isVisible] */ ){
				[self showPanel];
				panelClosed = NO;
			}
//			[self putMessageOnScreenWithHeader:message Header:header];
			[[textView textStorage] appendAttributedString:header];
			[[textView textStorage] appendAttributedString:message];
			if( panelVisible ){
				[textView scrollRangeToVisible:NSMakeRange([[textView string] length], 0)];
			}
//			[header release], [message release];
		}
	}
}

- (void)putMessageOnScreenWithHeader:(NSAttributedString *)message Header:(NSAttributedString*)header
{
	/*@synchronized(panel)*/{
	  CRITSECT::Scope scope(csex, 5000);
		[[textView textStorage] appendAttributedString:header];
		[[textView textStorage] appendAttributedString:message];
		if( panelVisible ){
			[textView scrollRangeToVisible:NSMakeRange([[textView string] length], 0)];
		}
	}
}

- (BOOL) windowShouldClose:(id)sender
{ // NSWindow *nswin = (NSWindow*) sender;
//	NSLog( @"PCLogController %@ not allowed to be closed; miniaturising\n", nswin );
	if( panel ){
		[panel miniaturize:panel];
		panelClosed = YES;
	}
	return NO;
}

- (void) windowDidMiniaturize:(NSNotification*) notification
{
	NSLog( @"%@ now invisible", self );
	panelVisible = NO;
}

- (void) windowDidDeminiaturize:(NSNotification*) notification
{
	NSLog( @"%@ now visible", self );
	panelVisible = YES;
	[textView scrollRangeToVisible:NSMakeRange([[textView string] length], 0)];
}

- (void) windowDidUpdate:(NSNotification*) notification
{
	if( !panelVisible && [panel isVisible] ){
//		NSLog( @"%@ should be invisible: hiding", self );
		[panel miniaturize:panel];
	}
}

-(void)awakeFromNib
{
	NSLog( @"%@ now visible", self );
	panelVisible = YES;
}

- (void) windowWillClose:(NSNotification*) notification
{
	panelClosed = YES;
	[_logCtrllr dealloc];
	_logCtrllr = nil;
}

@synthesize panel;
@synthesize textView;
@synthesize textAttributes;
@synthesize dateFormatter;
@end

@implementation PCLDelegate

- (void) textViewDidChangeTypingAttributes:(NSNotification*) notification
{
	NSLog(@"PCLogController text attributes changed");
}

@end

@implementation PanelDelegate

- (BOOL) windowShouldClose:(id)sender
{ NSWindow *nswin = (NSWindow*) sender;
//	NSLog( @"PCLogController %@ not allowed to be closed; miniaturising\n", nswin );
	if( nswin ){
		[nswin miniaturize:nswin];
	}
	return NO;
}

- (void) windowWillClose:(NSNotification*) notification
{
	_logCtrllr->panelClosed = YES;
	[_logCtrllr dealloc];
	_logCtrllr = nil;
}

@end

void PCLogAllocPool()
{
	if( !PCLogPool ){
		// allocate us a pool - unless we're destined to be embedded in a bundle (app, plugin, ...)
		PCLogPool = [[NSAutoreleasePool alloc] init];
	}
}

extern "C" void SetProgName(int argc, char **argv);

void SetProgName(int argc, char **argv)
{
	if( !ProgName ){
		NSLog( @"Loading PCLogController from %s\n", argv[0] );
		ProgName = [[NSString stringWithFormat:@"\"%s\"",
				   (argc > 0 && argv[0])? basename(argv[0]) : "?"] retain];
	}
}

__attribute__((destructor))
static void PCLogfinaliser()
{ extern void DelProgName();
	if( PCLogPool ){
		[PCLogPool drain];
		PCLogPool = NULL;
	}
	if( ProgName ){
		[ProgName release];
	}
}
