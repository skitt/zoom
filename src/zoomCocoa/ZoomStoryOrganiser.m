//
//  ZoomStoryOrganiser.m
//  ZoomCocoa
//
//  Created by Andrew Hunter on Thu Jan 22 2004.
//  Copyright (c) 2004 Andrew Hunter. All rights reserved.
//

#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>

#import <Cocoa/Cocoa.h>

#import "ZoomStoryOrganiser.h"
#import "ZoomAppDelegate.h"
#import "ZoomPreferences.h"

NSString* ZoomStoryOrganiserChangedNotification = @"ZoomStoryOrganiserChangedNotification";
NSString* ZoomStoryOrganiserProgressNotification = @"ZoomStoryOrganiserProgressNotification";

static NSString* defaultName = @"ZoomStoryOrganiser";
static NSString* extraDefaultsName = @"ZoomStoryOrganiserExtra";
static NSString* ZoomGameDirectories = @"ZoomGameDirectories";
static NSString* ZoomGameStorageDirectory = @"ZoomGameStorageDirectory";
static NSString* ZoomIdentityFilename = @".zoomIdentity";

@implementation ZoomStoryOrganiser

// = Internal functions =

- (NSDictionary*) dictionary {
	NSMutableDictionary* defaultDictionary = [NSMutableDictionary dictionary];
	
	NSEnumerator* filenameEnum = [filenamesToIdents keyEnumerator];
	NSString* filename;
	
	while (filename = [filenameEnum nextObject]) {
		NSData* encodedId = [NSArchiver archivedDataWithRootObject: [filenamesToIdents objectForKey: filename]];
		
		[defaultDictionary setObject: encodedId
							  forKey: filename];
	}
		
	return defaultDictionary;
}

- (NSDictionary*) extraDictionary {
	return [NSDictionary dictionary];
}

- (void) storePreferences {
	[[NSUserDefaults standardUserDefaults] setObject:[self dictionary] 
											  forKey:defaultName];
	[[NSUserDefaults standardUserDefaults] setObject:[self extraDictionary] 
											  forKey:extraDefaultsName];
}

- (void) preferenceThread: (NSDictionary*) threadDictionary {
	NSAutoreleasePool* p = [[NSAutoreleasePool alloc] init];
	NSDictionary* prefs = [threadDictionary objectForKey: @"preferences"];
	//NSDictionary* prefs2 = [threadDictionary objectForKey: @"extraPreferences"]; - unused, presently
	
	int counter = 0;
	
	// Connect to the main thread
	[[NSRunLoop currentRunLoop] addPort: port2
                                forMode: NSDefaultRunLoopMode];
	subThread = [[NSConnection allocWithZone: [self zone]]
        initWithReceivePort: port2
                   sendPort: port1];
	[subThread setRootObject: self];
	
	// Notify the main thread that things are happening
	[(ZoomStoryOrganiser*)[subThread rootProxy] startedActing];
			
	// Preference keys indicate the filenames
	NSEnumerator* filenameEnum = [prefs keyEnumerator];
	NSString* filename;
	
	while (filename = [filenameEnum nextObject]) {
		NSData* storyData = [prefs objectForKey: filename];
		ZoomStoryID* fileID = [NSUnarchiver unarchiveObjectWithData: storyData];
		ZoomStoryID* realID = [[ZoomStoryID alloc] initWithZCodeFile: filename];
		
		if (fileID != nil && realID != nil && [fileID isEqual: realID]) {
			// Check for a pre-existing entry
			[storyLock lock];
			
			NSString* oldFilename;
			ZoomStoryID* oldIdent;
			
			oldFilename = [identsToFilenames objectForKey: fileID];
			oldIdent = [filenamesToIdents objectForKey: filename];
			
			if (oldFilename && oldIdent && [oldFilename isEqualToString: filename] && [oldIdent isEqualTo: fileID]) {
				[storyLock unlock];
				continue;
			}
			
			// Remove old entries
			if (oldFilename) {
				[identsToFilenames removeObjectForKey: fileID];
				[storyFilenames removeObject: oldFilename];
			}
			
			if (oldIdent) {
				[filenamesToIdents removeObjectForKey: filename];
				[storyIdents removeObject: oldIdent];
			}
			
			// Add this entry
			NSString* newFilename = [[filename copy] autorelease];
			NSString* newIdent    = [[fileID copy] autorelease];
			
			[storyFilenames addObject: newFilename];
			[storyIdents addObject: newIdent];
			
			[identsToFilenames setObject: newFilename forKey: newIdent];
			[filenamesToIdents setObject: newIdent forKey: newFilename];
			
			[storyLock unlock];
		}
		
		[realID release];
		
		counter++;
		if (counter > 40) {
			counter = 0;
			[(ZoomStoryOrganiser*)[subThread rootProxy] organiserChanged];
		}
	}	
	
	[(ZoomStoryOrganiser*)[subThread rootProxy] organiserChanged];
	
	// If story organisation is on, we need to check for any disappeared stories that have appeared in
	// the organiser directory, and recreate any story data as required.
	//
	// REMEMBER: this is not the main thread! Don't make bad things happen!
	if ([[ZoomPreferences globalPreferences] keepGamesOrganised]) {
		// Directory scanning time. NSFileManager is not thread-safe, so we use opendir instead
		// (Yup, pain in the neck)
		NSString* orgDir = [[ZoomPreferences globalPreferences] organiserDirectory];
		DIR* orgD = opendir([orgDir UTF8String]);
		struct dirent* ent;
		
		while (orgD && (ent = readdir(orgD))) {
			NSString* groupName = [NSString stringWithUTF8String: ent->d_name];
			
			// Don't really want to iterate these
			if ([groupName isEqualToString: @".."] ||
				[groupName isEqualToString: @"."]) {
				continue;
			}
			
			// Must be a directory
			if (ent->d_type != DT_DIR) continue;
			
			// Iterate through the files in this directory
			NSString* newDir = [orgDir stringByAppendingPathComponent: groupName];
			
			DIR* groupD = opendir([newDir UTF8String]);
			struct dirent* gEnt;
			
			while (groupD && (gEnt = readdir(groupD))) {
				NSString* gameName = [NSString stringWithUTF8String: gEnt->d_name];
				
				// Don't really want to iterate these
				if ([gameName isEqualToString: @".."] ||
					[gameName isEqualToString: @"."]) {
					continue;
				}
				
				// Must be a directory
				if (gEnt->d_type != DT_DIR) continue;
				
				// See if there's a game.z5 there
				NSString* gameDir = [newDir stringByAppendingPathComponent: gameName];
				NSString* gameFile = [gameDir stringByAppendingPathComponent: @"game.z5"];
				
				struct stat sb;
				if (stat([gameFile UTF8String], &sb) != 0) continue;
				
				// See if it's already in our database
				[storyLock lock];
				ZoomStoryID* fileID = [filenamesToIdents objectForKey: gameFile];
				
				if (fileID == nil) {
					// Pass this off to the main thread
					[self performSelectorOnMainThread: @selector(foundFileNotInDatabase:)
										   withObject: [NSArray arrayWithObjects: groupName, gameName, gameFile, nil]
										waitUntilDone: NO];
				}
				[storyLock unlock];
			}
			
			if (groupD) closedir(groupD);
		}
		
		if (orgD) closedir(orgD);
	}

	[(ZoomStoryOrganiser*)[subThread rootProxy] organiserChanged];

	// Tidy up
	[(ZoomStoryOrganiser*)[subThread rootProxy] endedActing];

	[subThread release];
	[port1 release];
	[port2 release];

	subThread = nil;
	port1 = port2 = nil;
	
	// Done
	[threadDictionary release];
	[self release];
	
	// Clear the pool
	[p release];
}

- (void) loadPreferences {
	NSDictionary* prefs = [[NSUserDefaults standardUserDefaults] objectForKey: defaultName];
	NSDictionary* extraPrefs = [[NSUserDefaults standardUserDefaults] objectForKey: defaultName];
	
	// Detach a thread to decode the dictionary
	NSDictionary* threadDictionary =
		[[NSDictionary dictionaryWithObjectsAndKeys:
			prefs, @"preferences",
			extraPrefs, @"extraPreferences",
			nil] retain];
	
	// Create a connection so the threads can communicate
	port1 = [[NSPort port] retain];
	port2 = [[NSPort port] retain];
	
	mainThread = [[NSConnection allocWithZone: [self zone]]
		initWithReceivePort: port1
                   sendPort: port2];
	[mainThread setRootObject: self];
	
	// Run the thread
	[self retain]; // Released by the thread when it finishes
	[NSThread detachNewThreadSelector: @selector(preferenceThread:)
							 toTarget: self
						   withObject: threadDictionary];
}

- (void) organiserChanged {
	[self storePreferences];
	
	[[NSNotificationCenter defaultCenter] postNotificationName: ZoomStoryOrganiserChangedNotification
														object: self];
}

- (void) foundFileNotInDatabase: (NSArray*) info {
	// Called from the preferenceThread when a story not in the database is found
	NSString* groupName = [info objectAtIndex: 0];
	NSString* gameName = [info objectAtIndex: 1];
	NSString* gameFile = [info objectAtIndex: 2];
	
	static BOOL loggedNote = NO;
	if (!loggedNote) {
		loggedNote = YES;
	}
	
	// Check for story metadata first
	ZoomStoryID* newID = [[[ZoomStoryID alloc] initWithZCodeFile: gameFile] autorelease];
	
	if (newID == nil) {
		NSLog(@"Found unindexed game at %@, but failed to obtain an ID. Not indexing", gameFile);
		return;
	}
	
	BOOL otherFile;
	
	[storyLock lock];
	if ([identsToFilenames objectForKey: newID] != nil) {
		otherFile = YES;
		
		NSLog(@"Story %@ appears to be a duplicate of %@", gameFile, [identsToFilenames objectForKey: newID]);
	} else {
		otherFile = NO;
		
		NSLog(@"Story %@ not in database (will add)", gameFile);
	}
	[storyLock unlock];
	
	ZoomMetadata* data = [[NSApp delegate] userMetadata];	
	ZoomStory* oldStory = [[NSApp delegate] findStory: newID];
	
	if (oldStory == nil) {
		NSLog(@"Creating metadata entry for story '%@'", gameName);
		
		ZoomStory* newStory = [[ZoomStory alloc] init];
		
		[newStory setTitle: gameName];
		if (![groupName isEqualToString: @"Ungrouped"]);
		[newStory setGroup: groupName];
		[newStory addID: newID];
		
		[data storeStory: newStory];
		[data writeToDefaultFile];
		oldStory = [newStory autorelease];
	} else {
		NSLog(@"Found metadata for story '%@'", gameName);
	}
	
	// Check for any resources associated with this story
	if ([oldStory objectForKey: @"ResourceFilename"] == nil) {
		NSString* possibleResource = [[gameFile stringByDeletingLastPathComponent] stringByAppendingPathComponent: @"resource.blb"];
		BOOL isDir = NO;
		BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath: possibleResource
														   isDirectory: &isDir];
		
		if (exists && !isDir) {
			NSLog(@"Found resources for game at %@", possibleResource);
			
			[oldStory setObject: possibleResource
						 forKey: @"ResourceFilename"];

			[data storeStory: oldStory];
			[data writeToDefaultFile];
		}
	}
	
	// Now store with us
	[self addStory: gameFile
		 withIdent: newID
		  organise: NO];	
}

// = Initialisation =

+ (void) initialize {
	// User defaults
    NSUserDefaults *defaults  = [NSUserDefaults standardUserDefaults];
	ZoomStoryOrganiser* defaultPrefs = [[[[self class] alloc] init] autorelease];
	
	NSArray* libraries = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString* libraryDir = [[libraries objectAtIndex: 0] stringByAppendingPathComponent: @"Interactive Fiction"];
	
    NSDictionary *appDefaults = [NSDictionary dictionaryWithObjectsAndKeys: [defaultPrefs dictionary], defaultName,
		libraryDir, ZoomGameStorageDirectory, nil];
	
    [defaults registerDefaults: appDefaults];	
}

- (id) init {
	self = [super init];
	
	if (self) {
		storyFilenames = [[NSMutableArray alloc] init];
		storyIdents = [[NSMutableArray alloc] init];
		
		filenamesToIdents = [[NSMutableDictionary alloc] init];
		identsToFilenames = [[NSMutableDictionary alloc] init];
		
		storyLock = [[NSLock alloc] init];
		port1 = nil;
		port2 = nil;
		mainThread = nil;
		subThread = nil;
		
		// Any time a story changes, we move it
		[[NSNotificationCenter defaultCenter] addObserver: self
												 selector: @selector(someStoryHasChanged:)
													 name: ZoomStoryDataHasChangedNotification
												   object: nil];
	}
	
	return self;
}

- (void) dealloc {
	[storyFilenames release];
	[storyIdents release];
	[filenamesToIdents release];
	[identsToFilenames release];
	
	[storyLock release];
	[port1 release];
	[port2 release];
	[mainThread release];
	[subThread release];
	
	[[NSNotificationCenter defaultCenter] removeObserver: self];
	
	[super dealloc];
}

// = The shared organiser =

static ZoomStoryOrganiser* sharedOrganiser = nil;

+ (ZoomStoryOrganiser*) sharedStoryOrganiser {
	if (!sharedOrganiser) {
		sharedOrganiser = [[ZoomStoryOrganiser alloc] init];
		[sharedOrganiser loadPreferences];
	}
	
	return sharedOrganiser;
}

// = Storing stories =

- (void) addStory: (NSString*) filename
		withIdent: (ZoomStoryID*) ident {
	[self addStory: filename
		 withIdent: ident
		  organise: NO];
}

- (void) removeStoryWithIdent: (ZoomStoryID*) ident {
	[storyLock lock];
	
	NSString* filename = [identsToFilenames objectForKey: ident];
	
	if (filename != nil) {
		[filenamesToIdents removeObjectForKey: filename];
		[identsToFilenames removeObjectForKey: ident];
		[storyIdents removeObjectIdenticalTo: ident];
		[storyFilenames removeObject: filename];
	}
	
	[storyLock unlock];
	[self organiserChanged];
}

- (void) addStory: (NSString*) filename
		withIdent: (ZoomStoryID*) ident
		 organise: (BOOL) organise {	
	[storyLock lock];
	
	NSString* oldFilename;
	ZoomStoryID* oldIdent;
	
	oldFilename = [[identsToFilenames objectForKey: ident] stringByStandardizingPath];
	oldIdent = [filenamesToIdents objectForKey: oldFilename];
	
	// Get the story from the metadata database
	ZoomStory* theStory = [[NSApp delegate] findStory: ident];
	
	// If there's no story registered, then we need to create one
	if (theStory == nil) {
		theStory = [[ZoomStory alloc] init];
		
		[theStory addID: ident];
		[theStory setTitle: [[filename lastPathComponent] stringByDeletingPathExtension]];
		
		[[[NSApp delegate] userMetadata] storeStory: [theStory autorelease]];
		[[[NSApp delegate] userMetadata] writeToDefaultFile];
	}
		
	if (oldFilename && oldIdent && [oldFilename isEqualToString: filename] && [oldIdent isEqualTo: ident]) {
		// Nothing to do
		[storyLock unlock];

		
		if (organise) {
			[self organiseStory: theStory
					  withIdent: ident] ;
		}
		return;
	}
	
	if (oldFilename) {
		[identsToFilenames removeObjectForKey: ident];
		[filenamesToIdents removeObjectForKey: oldFilename];
		[storyFilenames removeObject: oldFilename];
	}

	if (oldIdent) {
		[filenamesToIdents removeObjectForKey: filename];
		[identsToFilenames removeObjectForKey: oldIdent];
		[storyIdents removeObject: oldIdent];
	}
	
	[filenamesToIdents removeObjectForKey: filename];
	[identsToFilenames removeObjectForKey: ident];
	
	NSString* newFilename = [[filename copy] autorelease];
	ZoomStoryID* newIdent = [[ident copy] autorelease];
		
	[storyFilenames addObject: newFilename];
	[storyIdents addObject: newIdent];
	
	[identsToFilenames setObject: newFilename forKey: newIdent];
	[filenamesToIdents setObject: newIdent forKey: newFilename];
	
	[storyLock unlock];
	
	if (organise) {
		[self organiseStory: theStory
				  withIdent: newIdent] ;
	}
	
	[self organiserChanged];
}

// = Progress =
- (void) startedActing {
	[[NSNotificationCenter defaultCenter] postNotificationName: ZoomStoryOrganiserProgressNotification
														object: self
													  userInfo: [NSDictionary dictionaryWithObjectsAndKeys:
														  [NSNumber numberWithBool: YES], @"ActionStarting",
														  nil]];
}

- (void) endedActing {
	[[NSNotificationCenter defaultCenter] postNotificationName: ZoomStoryOrganiserProgressNotification
														object: self
													  userInfo: [NSDictionary dictionaryWithObjectsAndKeys:
														  [NSNumber numberWithBool: NO], @"ActionStarting",
														  nil]];
}

// = Retrieving story information =

- (NSString*) filenameForIdent: (ZoomStoryID*) ident {
	NSString* res;
	
	[storyLock lock];
	res = [[[identsToFilenames objectForKey: ident] retain] autorelease];
	[storyLock unlock];
	
	return res;
}

- (ZoomStoryID*) identForFilename: (NSString*) filename {
	ZoomStoryID* res;
		
	[storyLock lock];
	res = [[[filenamesToIdents objectForKey: filename] retain] autorelease];
	[storyLock unlock];
	
	return res;
}

- (NSArray*) storyFilenames {
	return [[storyFilenames copy] autorelease];
}

- (NSArray*) storyIdents {
	return [[storyIdents copy] autorelease];
}

// = Story-specific data =

- (NSString*) preferredDirectoryForIdent: (ZoomStoryID*) ident {
	// The preferred directory is defined by the story group and title
	// (Ungrouped/untitled if there is no story group/title)

	// TESTME: what does stringByAppendingPathComponent do in the case where the group/title
	// contains a '/' or other evil character?
	NSString* confDir = [[NSUserDefaults standardUserDefaults] objectForKey: ZoomGameStorageDirectory];
	ZoomStory* theStory = [[NSApp delegate] findStory: ident];
	
	confDir = [confDir stringByAppendingPathComponent: [theStory group]];
	confDir = [confDir stringByAppendingPathComponent: [theStory title]];
	
	return confDir;
}

- (BOOL) directory: (NSString*) dir
		 isForGame: (ZoomStoryID*) ident {
	// If the preferences get corrupted or something similarily silly happens,
	// we want to avoid having games point to the wrong directories. This
	// routine checks that a directory belongs to a particular game.
	BOOL isDir;
	
	if (![[NSFileManager defaultManager] fileExistsAtPath: dir
											  isDirectory: &isDir]) {
		// Corner case
		return YES;
	}
	
	if (!isDir) // Files belong to no game
		return NO;
	
	NSString* idFile = [dir stringByAppendingPathComponent: ZoomIdentityFilename];
	if (![[NSFileManager defaultManager] fileExistsAtPath: idFile
											  isDirectory: &isDir]) {
		// Directory has no identification
		return NO;
	}
	
	if (isDir) // Identification must be a file
		return NO;
	
	ZoomStoryID* owner = [NSUnarchiver unarchiveObjectWithFile: idFile];
	
	if (owner && [owner isKindOfClass: [ZoomStoryID class]] && [owner isEqual: ident])
		return YES;
	
	// Directory belongs to some other game
	return NO;
}

- (NSString*) findDirectoryForIdent: (ZoomStoryID*) ident
					  createGameDir: (BOOL) createGame
					 createGroupDir: (BOOL) createGroup {
	// Assuming a story doesn't already have a directory, find (and possibly create)
	// a directory for it
	BOOL isDir;
	
	ZoomStory* theStory = [[NSApp delegate] findStory: ident];
	NSString* group = [theStory group];
	NSString* title = [theStory title];
	
	if (group == nil || [group isEqualToString: @""])
		group = @"Ungrouped";
	if (title == nil || [title isEqualToString: @""])
		title = @"Untitled";
	
	// Find the root directory
	NSString* rootDir = [[NSUserDefaults standardUserDefaults] objectForKey: ZoomGameStorageDirectory];
	
	if (![[NSFileManager defaultManager] fileExistsAtPath: rootDir
											  isDirectory: &isDir]) {
		if (createGroup) {
			[[NSFileManager defaultManager] createDirectoryAtPath: rootDir
													   attributes: nil];
			isDir = YES;
		} else {
			return nil;
		}
	}
	
	if (!isDir) {
		static BOOL warned = NO;
		
		if (!warned)
			NSRunAlertPanel([NSString stringWithFormat: @"Game library not found"],
							[NSString stringWithFormat: @"Warning: %@ is a file", rootDir], 
							@"OK", nil, nil);
		warned = YES;
		return nil;
	}
	
	// Find the group directory
	NSString* groupDir = [rootDir stringByAppendingPathComponent: group];
	
	if (![[NSFileManager defaultManager] fileExistsAtPath: groupDir
											  isDirectory: &isDir]) {
		if (createGroup) {
			[[NSFileManager defaultManager] createDirectoryAtPath: groupDir
													   attributes: nil];
			isDir = YES;
		} else {
			return nil;
		}
	}
	
	if (!isDir) {
		static BOOL warned = NO;
		
		if (!warned)
			NSRunAlertPanel([NSString stringWithFormat: @"Group directory not found"],
							[NSString stringWithFormat: @"Warning: %@ is a file", groupDir], 
							@"OK", nil, nil);
		warned = YES;
		return nil;
	}
	
	// Now the game directory
	NSString* gameDir = [groupDir stringByAppendingPathComponent: title];
	int number = 0;
	const int maxNumber = 20;
	
	while (![self directory: gameDir 
				  isForGame: ident] &&
		   number < maxNumber) {
		number++;
		gameDir = [groupDir stringByAppendingPathComponent: [NSString stringWithFormat: @"%@ %i", title, number]];
	}
	
	if (number >= maxNumber) {
		static BOOL warned = NO;
		
		if (!warned)
			NSRunAlertPanel([NSString stringWithFormat: @"Game directory not found"],
							[NSString stringWithFormat: @"Zoom was unable to locate a directory for the game '%@'", title], 
							@"OK", nil, nil);
		warned = YES;
		return nil;
	}
	
	// Create the directory if necessary
	if (![[NSFileManager defaultManager] fileExistsAtPath: gameDir
											  isDirectory: &isDir]) {
		if (createGame) {
			[[NSFileManager defaultManager] createDirectoryAtPath: gameDir
													   attributes: nil];
		} else {
			if (createGroup) {
				// Special case, really. Sometimes we need to know where we're going to move the game to
				return gameDir;
			} else {
				return nil;
			}
		}
	}
	
	if (![[NSFileManager defaultManager] fileExistsAtPath: gameDir
											  isDirectory: &isDir] || !isDir) {
		// Chances of reaching here should have been eliminated previously
		return nil;
	}
	
	// Create the identifier file
	NSString* identityFile = [gameDir stringByAppendingPathComponent: ZoomIdentityFilename];
	[NSArchiver archiveRootObject: ident
						   toFile: identityFile];
	
	return gameDir;
}

- (NSString*) directoryForIdent: (ZoomStoryID*) ident
						 create: (BOOL) create {
	NSString* confDir = nil;
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
		
	// If there is a directory in the preferences, then that's the directory to use
	NSDictionary* gameDirs = [defaults objectForKey: ZoomGameDirectories];
	
	if (gameDirs)
		confDir = [gameDirs objectForKey: [ident description]];

	BOOL isDir;
	if (![[NSFileManager defaultManager] fileExistsAtPath: confDir
											  isDirectory: &isDir]) {
		confDir = nil;
	}
	
	if (!isDir)
		confDir = nil;
	
	if (confDir && [self directory: confDir isForGame: ident])
		return confDir;
	
	confDir = nil;
	
	NSString* gameDir = [self findDirectoryForIdent: ident
									  createGameDir: create
									 createGroupDir: create];
	
	if (gameDir == nil) return nil;
		
	// Store this directory as the dir for this game
	NSMutableDictionary* newGameDirs = [gameDirs mutableCopy];

	if (newGameDirs == nil) {
		newGameDirs = [[NSMutableDictionary alloc] init];
	}

	[newGameDirs setObject: gameDir
					forKey: [ident description]];
	[defaults setObject: [newGameDirs autorelease]
				 forKey: ZoomGameDirectories];
	
	return gameDir;
}

- (BOOL) moveStoryToPreferredDirectoryWithIdent: (ZoomStoryID*) ident {
	// Get the current directory
	NSString* currentDir = [self directoryForIdent: ident 
											create: NO];
	currentDir = [currentDir stringByStandardizingPath];
	
	if (currentDir == nil) return NO;
	
	// Get the 'ideal' directory
	NSString* idealDir = [self findDirectoryForIdent: ident
									   createGameDir: NO
									  createGroupDir: YES];
	idealDir = [idealDir stringByStandardizingPath];
	
	// See if they already match
	if ([idealDir isEqualToString: currentDir]) 
		return YES;
	
	// If they don't match, then idealDir should be new (or something weird has just occured)
	// Hmph. HFS+ is case-insensitve, and stringByStandardizingPath does not take account of this. This could
	// cause some major problems with organiseStory:withIdent:, as that deletes/copies files...
	if ([[NSFileManager defaultManager] fileExistsAtPath: idealDir]) {
		// Doh!
		NSLog(@"Wanted to move game from '%@' to '%@', but '%@' already exists", currentDir, idealDir, idealDir);
		return NO;
	}
	
	// Move the old directory to the new directory
	
	// Vague possibilities of this failing: in particular, currentDir may be not write-accessible or
	// something might appear there between our check and actually moving the directory	
	if (![[NSFileManager defaultManager] movePath: currentDir
										  toPath: idealDir
										 handler: nil]) {
		NSLog(@"Failed to move '%@' to '%@'", currentDir, idealDir);
		return NO;
	}
	
	// Success: store the new directory in the defaults
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	
	NSDictionary* gameDirs = [defaults objectForKey: ZoomGameDirectories];
	if (gameDirs == nil) gameDirs = [NSDictionary dictionary];
	NSMutableDictionary* newGameDirs = [gameDirs mutableCopy];
	
	if (newGameDirs == nil) {
		newGameDirs = [[NSMutableDictionary alloc] init];
	}
	
	[newGameDirs setObject: idealDir
					forKey: [ident description]];
	[defaults setObject: [newGameDirs autorelease]
				 forKey: ZoomGameDirectories];	
	
	return YES;
}

- (void) someStoryHasChanged: (NSNotification*) not {
	ZoomStory* story = [not object];
	
	if (![story isKindOfClass: [ZoomStory class]]) {
		NSLog(@"someStoryHasChanged: called with a non-story object (too many spoons?)");
		return; // Unlikely but possible. If I'm a spoon, that is.
	}
	
	// De and requeue this to be done next time through the run loop
	// (stops this from being performed multiple times when many story parameters are updated together)
	[[NSRunLoop currentRunLoop] cancelPerformSelector: @selector(finishChangingStory:)
											   target: self
											 argument: story];
	[[NSRunLoop currentRunLoop] performSelector: @selector(finishChangingStory:)
										 target: self
									   argument: story
										  order: 128
										  modes: [NSArray arrayWithObjects: NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
}

- (void) finishChangingStory: (ZoomStory*) story {
	// For our pre-arranged stories, several IDs are possible, but more usually one
	NSEnumerator* identEnum = [[story storyIDs] objectEnumerator];
	ZoomStoryID* ident;
	BOOL changed = NO;
	
	while (ident = [identEnum nextObject]) {
		int identID = [storyIdents indexOfObject: ident];
		
		if (identID != NSNotFound) {
			// Get the old location of the game
			ZoomStoryID* realID = [storyIdents objectAtIndex: identID];
			
			NSString* oldGameFile = [self directoryForIdent: ident create: NO];
			oldGameFile = [oldGameFile stringByAppendingPathComponent: @"game.z5"];
			NSString* oldGameLoc = [storyFilenames objectAtIndex: identID];
			
			oldGameFile = [oldGameFile stringByStandardizingPath];
			oldGameLoc = [oldGameLoc stringByStandardizingPath];

			// Actually perform the move
			if ([self moveStoryToPreferredDirectoryWithIdent: [storyIdents objectAtIndex: identID]]) {
				changed = YES;
			
				// Store the new location of the game, if necessary
				if ([oldGameLoc isEqualToString: oldGameFile]) {
					NSString* newGameFile = [[self directoryForIdent: ident create: NO] stringByAppendingPathComponent: @"game.z5"];
					newGameFile = [newGameFile stringByStandardizingPath];

					if (![oldGameFile isEqualToString: newGameFile]) {
						[filenamesToIdents removeObjectForKey: oldGameFile];
						
						[filenamesToIdents setObject: realID
											  forKey: newGameFile];
						[identsToFilenames setObject: newGameFile
											  forKey: realID];
						
						[storyFilenames replaceObjectAtIndex: identID
												  withObject: newGameFile];
					}
				}
			}
		}
	}
	
	if (changed)
		[self organiserChanged];
}

// = Reorganising stories =

- (void) organiseStory: (ZoomStory*) story
			 withIdent: (ZoomStoryID*) ident {
	NSString* filename = [self filenameForIdent: ident];
	
	if (filename == nil) {
		NSLog(@"WARNING: Attempted to organise a story with no filename");
		return;
	}
		
	NSString* oldFilename = [[filename retain] autorelease];
	
	// Copy to a standard directory, change the filename we're using
	filename = [filename stringByStandardizingPath];
		
	NSString* fileDir = [self directoryForIdent: ident create: YES];
	NSString* destFile = [fileDir stringByAppendingPathComponent: @"game.z5"];
	destFile = [destFile stringByStandardizingPath];
		
	if (![filename isEqualToString: destFile]) {
		BOOL moved = NO;
		
		if ([[filename lowercaseString] isEqualToString: [destFile lowercaseString]]) {
			// *LIKELY* that these are in fact the same file with different case names
			// Cocoa doesn't seem to provide a good way to see if too paths are actually the same:
			// so the semantics of this might be incorrect in certain edge cases. We move to ensure
			// that everything is nice and safe
			[[NSFileManager defaultManager] movePath: filename
											  toPath: destFile
											 handler: nil];
			
			moved = YES;
		}
		
		// The file might already be organised, but in the wrong directory
		NSString* gameStorageDirectory = [[NSUserDefaults standardUserDefaults] objectForKey: ZoomGameStorageDirectory];
		NSArray* storageComponents = [gameStorageDirectory pathComponents];

		NSArray* filenameComponents = [filename pathComponents];
		BOOL outsideOrganisation = YES;
		
		if ([filenameComponents count] == [storageComponents count]+3) {
			// filenameComponents should have 3 components extra over the storage directory: group/title/game.z5
			
			// Compare the components
			int x;
			outsideOrganisation = NO;
			for (x=0; x<[storageComponents count]; x++) {
				// Note, there's no way to see if we're using a case-sensitive file system or not. We assume
				// we are, as that's the default. People running with HFSX or UFS can just put up with the
				// odd weirdness occuring due to this.
				NSString* c1 = [[filenameComponents objectAtIndex: x] lowercaseString];
				NSString* c2 = [[storageComponents objectAtIndex: x] lowercaseString];
				
				if (![c1 isEqualToString: c2]) {
					outsideOrganisation = YES;
					break;
				}
			}
		}
		
		if (!outsideOrganisation) {
			// Have to move the file from the directory it's in to the new directory
			// Really want to move resources and savegames too... Hmm
			NSString* oldDir = [filename stringByDeletingLastPathComponent];
			NSEnumerator* dirEnum = [[[NSFileManager defaultManager] directoryContentsAtPath: oldDir] objectEnumerator];
			
			NSString* fileToMove;
			while (fileToMove = [dirEnum nextObject]) {
				[[NSFileManager defaultManager] movePath: [oldDir stringByAppendingPathComponent: fileToMove]
												  toPath: [fileDir stringByAppendingPathComponent: fileToMove]
												 handler: nil];
			}
			
			moved = YES;
		}
		
		// If we haven't already moved the file, then
		if (!moved) {
			[[NSFileManager defaultManager] removeFileAtPath: destFile handler: nil];
			if ([[NSFileManager defaultManager] copyPath: filename
												  toPath: destFile
												 handler: nil]) {
				filename = destFile;
			} else {
				NSLog(@"Warning: couldn't copy '%@' to '%@'", filename, destFile);
			}
		}
		
		// Notify the workspace of the change
		[[NSWorkspace sharedWorkspace] noteFileSystemChanged: filename];
		[[NSWorkspace sharedWorkspace] noteFileSystemChanged: destFile];
	}
	
	// Update the indexes
	[identsToFilenames setObject: filename
						  forKey: ident];
	[filenamesToIdents removeObjectForKey: oldFilename];
	[filenamesToIdents setObject: ident
						  forKey: filename];
	
	// Organise the story's resources
	NSString* resources = [story objectForKey: @"ResourceFilename"];
	if (resources != nil && [[NSFileManager defaultManager] fileExistsAtPath: resources]) {
		NSString* dir = [self directoryForIdent: ident
										 create: NO];
		BOOL exists, isDir;
		NSFileManager* fm = [NSFileManager defaultManager];
		
		if (dir == nil) {
			NSLog(@"No organised directory for game: cannot store resources");
			return;
		}
		
		exists = [fm fileExistsAtPath: dir
						  isDirectory: &isDir];
		if (!exists || !isDir) {
			NSLog(@"Organised directory for game does not exist");
			return;
		}
		
		NSString* newFile = [dir stringByAppendingPathComponent: @"resource.blb"];
		
		if (![fm copyPath: resources
				   toPath: newFile
				  handler: nil]) {
			NSLog(@"Unable to copy resource file to new location");
		} else {
			resources = newFile;
		}
		
		[story setObject: resources
				  forKey: @"ResourceFilename"];
	} else {
		[story setObject: nil
				  forKey: @"ResourceFilename"];
	}
}

- (void) organiseStory: (ZoomStory*) story {
	NSEnumerator* idEnum = [[story storyIDs] objectEnumerator];
	ZoomStoryID* thisID;
	BOOL organised = NO;
	
	while (thisID = [idEnum nextObject]) {
		NSString* filename = [self filenameForIdent: thisID];
		
		if (filename != nil) {
			[self organiseStory: story
					  withIdent: thisID];
			organised = YES;
		}
	}
	
	if (!organised) {
		NSLog(@"WARNING: attempted to organise story with no IDs");
	}
}

- (void) organiseAllStories {
	// Forces an organisation of all the stories stored in the database.
	// This is useful if, for example, the 'keep games organised' option is switched on/off
	
	// Create the ports for the thread
	NSPort* threadPort1 = [NSPort port];
	NSPort* threadPort2 = [NSPort port];
	
	[[NSRunLoop currentRunLoop] addPort: threadPort1
								forMode: NSDefaultRunLoopMode];
	
	NSConnection* mainThreadConnection = [[NSConnection alloc] initWithReceivePort: threadPort1
																		  sendPort: threadPort2];
	[mainThreadConnection setRootObject: self];
	
	// Create the information dictionary
	NSDictionary* threadDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
		threadPort1, @"threadPort1",
		threadPort2, @"threadPort2",
		mainThreadConnection,  @"mainThread",
		nil];
	
	[storyLock lock];
	if (alreadyOrganising) {
		NSLog(@"ZoomStoryOrganiser: organiseAllStories called while Zoom was already in the process of organising");
		[storyLock unlock];
		return;
	}
	
	alreadyOrganising = YES;
	
	// Run a separate thread to do (some of) the work
	[self retain]; // Released by the thread when it finishes
	[NSThread detachNewThreadSelector: @selector(organiserThread:)
							 toTarget: self
						   withObject: threadDictionary];
	[storyLock unlock];
}

- (void) reorganiseStoriesTo: (NSString*) newStoryDirectory {
	// Changes the story organisation directory
	// Meh. Can just rename the directory, perhaps?
}

// = Reorganising story files =

- (NSData*) retrieveUtf8PathFrom: (NSString*) path {
	// We have to have this function, as we can't call NSFileManager from a thread
	NSFileManager* mgr = [NSFileManager defaultManager];
	
	const char* rep = [mgr fileSystemRepresentationWithPath: path];
	return [NSData dataWithBytes: rep
						  length: strlen(rep)+1];
}

- (NSString*) gameStorageDirectory {
	// We also can't use the user defaults from a thread
	return [[NSUserDefaults standardUserDefaults] objectForKey: ZoomGameStorageDirectory];
}

- (NSDictionary*) storyInfoForFilename: (NSString*) filename {
	[storyLock lock];
	
	ZoomStoryID* storyID = [filenamesToIdents objectForKey: filename];
	ZoomStory* story = nil;
	
	if (storyID) story = [[NSApp delegate] findStory: storyID];

	[storyLock unlock];
	
	return [NSDictionary dictionaryWithObjectsAndKeys: storyID, @"storyID", story, @"story", nil];
}

- (void) renamedIdent: (ZoomStoryID*) ident
		   toFilename: (NSString*) filename {
	filename = [[filename copy] autorelease];
	
	[storyLock lock];
	
	NSString* oldFilename = [identsToFilenames objectForKey: ident];
	ZoomStoryID* oldID = [filenamesToIdents objectForKey: oldFilename];
	
	if (oldFilename) [identsToFilenames removeObjectForKey: ident];
	if (oldID) [filenamesToIdents removeObjectForKey: oldFilename];
	
	[identsToFilenames setObject: filename
						  forKey: ident];
	[filenamesToIdents setObject: ident
						  forKey: filename];
	
	[storyLock unlock];
	
	[self organiserChanged];
}

- (void) organiserThread: (NSDictionary*) dict {
	NSAutoreleasePool* p = [[NSAutoreleasePool alloc] init];
	
	// Retrieve the info from the dictionary
	NSPort* threadPort1 = [dict objectForKey: @"threadPort1"];
	NSPort* threadPort2 = [dict objectForKey: @"threadPort2"];
	
	// Connect to the main thread
	[[NSRunLoop currentRunLoop] addPort: threadPort2
                                forMode: NSDefaultRunLoopMode];
	NSConnection* subThreadConnection = [[NSConnection allocWithZone: [self zone]] initWithReceivePort: threadPort2
																							  sendPort: threadPort1];
	[subThreadConnection setRootObject: self];
	
	// Start things rolling
	[(ZoomStoryOrganiser*)[subThreadConnection rootProxy] startedActing];
	
	NSString* gameStorageDirectory = [[[(ZoomStoryOrganiser*)[subThreadConnection rootProxy] gameStorageDirectory] copy] autorelease];
	NSArray* storageComponents = [gameStorageDirectory pathComponents];
	
	// Get the list of stories we need to update
	// It is assumed any new stories at this point will be organised correctly
	[storyLock lock];
	NSArray* filenames = [[filenamesToIdents allKeys] copy];
	[storyLock unlock];
	
	NSEnumerator* filenameEnum = [filenames objectEnumerator];
	NSString* filename;
	
	NSLog(@"Reorganising stories...");

	NSAutoreleasePool* loopPool = [[NSAutoreleasePool alloc] init];

	while (filename = [filenameEnum nextObject]) {
		[loopPool release]; loopPool = [[NSAutoreleasePool alloc] init];
		
		// First: check that the file exists
		struct stat sb;
		
		// Get the file system path
		NSData* utf8PathData = [(ZoomStoryOrganiser*)[subThreadConnection rootProxy] retrieveUtf8PathFrom: filename];
		const char* utf8Path = [utf8PathData bytes];
		
		[storyLock lock];
		if (stat(utf8Path, &sb) != 0) {
			// The story does not exist: remove from the database and keep moving
			
			ZoomStoryID* oldID = [filenamesToIdents objectForKey: filename];
			
			if (oldID != nil) {
				// Is actually still in the database as that filename
				[filenamesToIdents removeObjectForKey: filename];
				[identsToFilenames removeObjectForKey: oldID];
				
				[(ZoomStoryOrganiser*)[subThreadConnection rootProxy] organiserChanged];
			}
			
			[storyLock unlock];
			continue;
		}
		
		// OK, the story still exists with that filename. Pass this off to the main thread
		// for organisation
		// [(ZoomStoryOrganiser*)[subThreadConnection rootProxy] reorganiseStoryWithFilename: filename];
		// ---  FAILS, creates duplicates sometimes
		
		// There are a few possibilities:
		//
		//		1. The story is outside the organisation directory
		//		2. The story is in the organisation directory, but in the wrong group
		//		3. The story is in the organisation directory, but in the wrong directory
		//		4. There are multiple copies of the story in the directory
		//
		// 2 and 3 here are not exclusive. There may be a story in the organisation directory with the
		// same title, so the 'ideal' location might turn out to be unavailable.
		//
		// In case 1, act as if the story has been newly added, except move the old story to the trash. Finished.
		// In case 2, move the story directory to the new group. Rename if it already exists there (pick
		//		something generic, I guess). Fall through to check case 3.
		// In case 3, pick the 'best' possible name, and rename it
		// In case 4, merge the story directories. (We'll leave this out for the moment)
		//
		// Also a faint chance that the file/directory will disappear while we're operating on it.
		//
		// We have a problem being in a separate thread. NSFileManager can only be called from the
		// main thread :-( We can call Unix file functions, but in order to get the UNIX path, we need to call
		// NSFileManager.

		// Can't lock the story while calling the main thread, or we might deadlock
		[storyLock unlock];
		
		// Get the story information
		NSDictionary* storyInfo = [(ZoomStoryOrganiser*)[subThreadConnection rootProxy] storyInfoForFilename: filename];
		
		ZoomStoryID* storyID = [storyInfo objectForKey: @"storyID"];
		ZoomStory* story = [storyInfo objectForKey: @"story"];
		
		if (storyID == nil || story == nil) {
			// No info (file has gone away?)
			NSLog(@"Organiser: failed to reorganise file '%@' - couldn't find any information for this file", filename);
			continue;
		}
		
		// CHECK FOR CASE 1 - does filename begin with gameStorageDirectory?
		NSArray* filenameComponents = [filename pathComponents];
		BOOL outsideOrganisation = YES;
		
		if ([filenameComponents count] == [storageComponents count]+3) {
			// filenameComponents should have 3 components extra over the storage directory: group/title/game.z5
			
			// Compare the components
			int x;
			outsideOrganisation = NO;
			for (x=0; x<[storageComponents count]; x++) {
				// Note, there's no way to see if we're using a case-sensitive file system or not. We assume
				// we are, as that's the default. People running with HFSX or UFS can just put up with the
				// odd weirdness occuring due to this.
				NSString* c1 = [[filenameComponents objectAtIndex: x] lowercaseString];
				NSString* c2 = [[storageComponents objectAtIndex: x] lowercaseString];
				
				if (![c1 isEqualToString: c2]) {
					outsideOrganisation = YES;
					break;
				}
			}
		}
		
		if (outsideOrganisation) {
			// CASE 1 HAS OCCURED. Organise this story
			NSLog(@"File %@ outside of organisation directory: organising", filename);
			
			[(ZoomStoryOrganiser*)[subThreadConnection rootProxy] organiseStory: story
																	  withIdent: storyID];
			continue;
		}
		
		// CHECK FOR CASE 2: story is in the wrong group
		BOOL inWrongGroup = NO;
		
		[storyLock lock];
		NSString* expectedGroup = [[[story group] copy] autorelease];
		NSString* actualGroup = [filenameComponents objectAtIndex: [filenameComponents count]-3];
		if (expectedGroup == nil || [expectedGroup isEqualToString: @""]) expectedGroup = @"Ungrouped";
		[storyLock unlock];
		
		if (![[actualGroup lowercaseString] isEqualToString: [expectedGroup lowercaseString]]) {
			NSLog(@"Organiser: File %@ not in the expected group (%@ vs %@)", filename, actualGroup, expectedGroup);
			inWrongGroup = YES;
		}
		
		// CHECK FOR CASE 3: story is in the wrong directory
		BOOL inWrongDirectory = NO;
		
		[storyLock lock];
		NSString* expectedDir = [[[story title] copy] autorelease];
		NSString* actualDir = [filenameComponents objectAtIndex: [filenameComponents count]-2];
		[storyLock unlock];
		
		if (![[actualDir lowercaseString] isEqualToString: [expectedDir lowercaseString]]) {
			NSLog(@"Organiser: File %@ not in the expected directory (%@ vs %@)", filename, actualDir, expectedDir);
			inWrongDirectory = YES;
		}
		
		// Deal with these two cases: create the group/move the directory
		if (inWrongGroup) {
			// Create the group directory if required
			NSString* groupDirectory = [gameStorageDirectory stringByAppendingPathComponent: expectedGroup];
			NSData* groupUtf8Data = [(ZoomStoryOrganiser*)[subThreadConnection rootProxy] retrieveUtf8PathFrom: groupDirectory];
			
			// Create the group directory if it doesn't already exist
			// Don't organise this file if there's a file already here

			if (stat([groupUtf8Data bytes], &sb) == 0) {
				if ((sb.st_mode&S_IFDIR) == 0) {
					// Oops, this is a file: can't move anything here
					NSLog(@"Organiser: Can't create group directory at %@ - there's a file in the way", groupDirectory);
					continue;
				}
			} else {
				NSLog(@"Organiser: Creating group directory at %@", groupDirectory);
				int err = mkdir([groupUtf8Data bytes], 0755);
				
				if (err != 0) {
					// strerror & co aren't thread-safe so we can't safely retrieve the actual error number
					NSLog(@"Organiser: Failed to create directory at %@", groupDirectory);
					continue;
				}
			}
		}
		
		if (inWrongGroup || inWrongDirectory) {
			// Move the game (semi-atomically)
			[storyLock lock];
			
			NSString* oldDirectory = [filename stringByDeletingLastPathComponent];
			NSData* oldDirUtf8 = [(ZoomStoryOrganiser*)[subThreadConnection rootProxy] retrieveUtf8PathFrom: oldDirectory];
			
			NSString* groupDirectory = [gameStorageDirectory stringByAppendingPathComponent: expectedGroup];
			NSString* titleDirectory;
			
			NSData* gameDirUtf8Data;
			const char* gameDirUtf8;
			
			int count = 0;
			
			// Work out where to put the game (duplicates might exist)
			do {
				if (count == 0) {
					titleDirectory = [groupDirectory stringByAppendingPathComponent: expectedDir];
				} else {
					titleDirectory = [groupDirectory stringByAppendingPathComponent: [NSString stringWithFormat: @"%@ %i", expectedDir, count]];
				}
				
				gameDirUtf8Data = [(ZoomStoryOrganiser*)[subThreadConnection rootProxy] retrieveUtf8PathFrom: titleDirectory];
				gameDirUtf8 = [gameDirUtf8Data bytes];
				
				if ([[titleDirectory lowercaseString] isEqualToString: [oldDirectory lowercaseString]]) {
					// Nothing to do!
					NSLog(@"Organiser: oops, name difference is due to multiple stories with the same title");
					break;
				}
				
				if (stat(gameDirUtf8, &sb) == 0) {
					// Already exists - try the next name along
					count++;
					continue;
				}
				
				// Doesn't exist at the moment: OK for renaming
				break;
			} while (1);

			if ([[titleDirectory lowercaseString] isEqualToString: [oldDirectory lowercaseString]]) {
				// Still nothing to do
				[storyLock unlock];
				continue;
			}
			
			// Move the game to its new home
			NSLog(@"Organiser: Moving %@ to %@", oldDirectory, titleDirectory);
			
			if (rename([oldDirUtf8 bytes], gameDirUtf8) != 0) {
				[storyLock unlock];
				
				NSLog(@"Organiser: Failed to move %@ to %@ (rename failed)", oldDirectory, titleDirectory);
				continue;
			}

			[storyLock unlock];
			
			// Update filenamesToIdents and identsToFilenames appropriately
			[(ZoomStoryOrganiser*)[subThreadConnection rootProxy] renamedIdent: storyID
																	toFilename: [titleDirectory stringByAppendingPathComponent: [filename lastPathComponent]]];
		}
	}

	[loopPool release];
	
	// Not organising any more
	[storyLock lock];
	alreadyOrganising = NO;
	[storyLock unlock];
	
	// Tidy up
	[self release];
	
	[(ZoomStoryOrganiser*)[subThreadConnection rootProxy] endedActing];
	[subThreadConnection release];
	[p release];
}

@end
