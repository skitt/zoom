//
//  ZoomiFButton.m
//  ZoomCocoa
//
//  Created by Andrew Hunter on Thu Jan 22 2004.
//  Copyright (c) 2004 Andrew Hunter. All rights reserved.
//

#import "ZoomiFButton.h"


@implementation ZoomiFButton

static NSImage* disabledImage;

+ (void) initialize {
	disabledImage = [[NSImage imageNamed: @"disabledButton"] retain];
}

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
		pushedImage = nil;
    }
    return self;
}

- (void) dealloc {
	if (pushedImage) [pushedImage release];
	if (unpushedImage) [unpushedImage release];
	
	[super dealloc];
}

- (void) setPushedImage: (NSImage*) newPushedImage {
	if (pushedImage) [pushedImage release];
	pushedImage = [newPushedImage retain];
}

- (void) mouseDown: (NSEvent*) theEvent {
	if (![self isEnabled]) return;
	
	if (!unpushedImage) {
		unpushedImage = [[self image] retain];
		[self setImage: pushedImage];
		
		inside = YES;
		theTrackingRect = [self addTrackingRect: [self bounds]
										  owner: self 
									   userData: nil
								   assumeInside: YES];
	}
}

- (void) mouseEntered: (NSEvent*) theEvent {
	if (unpushedImage) {
		[self setImage: pushedImage];
		inside = YES;
	}
}

- (void) mouseExited: (NSEvent*) theEvent {	
	if (unpushedImage) {
		[self setImage: unpushedImage];
		inside = NO;
	}
}

- (void) mouseUp: (NSEvent *) theEvent {
	if (![self isEnabled]) return;

	if (unpushedImage) {
		[self setImage: unpushedImage];
		[unpushedImage release];
		unpushedImage = nil;
		
		[self removeTrackingRect: theTrackingRect];
		
		if (inside) {
			[self sendAction: [self action] 
						  to: [self target]];
		}
	}
}

- (void) setEnabled: (BOOL) enabled {
	if (!enabled) {
		if (!unpushedImage) {
			unpushedImage = [[self image] retain];
			[self setImage: disabledImage];
		}
	} else {
		if (unpushedImage) {
			[self setImage: unpushedImage];
			[unpushedImage release];
		}
	}
	
	[super setEnabled: enabled];
}

@end
