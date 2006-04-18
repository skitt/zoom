//
//  ZoomStory.m
//  ZoomCocoa
//
//  Created by Andrew Hunter on Tue Jan 13 2004.
//  Copyright (c) 2004 Andrew Hunter. All rights reserved.
//

#import "ZoomStory.h"
#import "ZoomStoryID.h"

#import "ZoomMetadata.h"
#import "ZoomBlorbFile.h"
#import "ZoomPreferences.h"

#include "ifmetabase.h"

NSString* ZoomStoryDataHasChangedNotification = @"ZoomStoryDataHasChangedNotification";
NSString* ZoomStoryExtraMetadata = @"ZoomStoryExtraMetadata";

NSString* ZoomStoryExtraMetadataChangedNotification = @"ZoomStoryExtraMetadataChangedNotification";

@implementation ZoomStory

+ (void) initialize {
	NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];
	
	[defs registerDefaults: 
		[NSDictionary dictionaryWithObjectsAndKeys:
			[NSDictionary dictionary], ZoomStoryExtraMetadata,
			nil]];
}

+ (NSString*) nameForKey: (NSString*) key {
	// FIXME: internationalisation (this FIXME applies to most of Zoom, which is why it hasn't happened yet)
	static NSDictionary* keyNameDict = nil;
	
	if (keyNameDict == nil) {
		keyNameDict = [NSDictionary dictionaryWithObjectsAndKeys:
			@"Title", @"title",
			@"Headline", @"headline",
			@"Author", @"author",
			@"Genre", @"genre",
			@"Group", @"group",
			@"Year", @"year",
			@"Zarfian rating", @"zarfian",
			@"Teaser", @"teaser",
			@"Comments", @"comment",
			@"My Rating", @"rating",
			@"Description", @"description",
			@"Cover picture number", @"coverpicture",
			nil];
		
		[keyNameDict retain];
	}
	
	return [keyNameDict objectForKey: key];
}

+ (NSString*) keyForTag: (int) tag {
	switch (tag) {
		case 0: return @"title";
		case 1: return @"headline";
		case 2: return @"author";
		case 3: return @"genre";
		case 4: return @"group";
		case 5: return @"year";
		case 6: return @"zarfian";
		case 7: return @"teaser";
		case 8: return @"comment";
		case 9: return @"rating";
		case 10: return @"description";
		case 11: return @"coverpicture";
	}
	
	return nil;
}

+ (ZoomStory*) defaultMetadataForFile: (NSString*) filename {
	// Gets the standard metadata for the given file
	BOOL isDir;
	
	if (![[NSFileManager defaultManager] fileExistsAtPath: filename
											  isDirectory: &isDir]) return nil;
	if (isDir) return nil;
	
	// Get the ID for this file
	NSData* fileData = [NSData dataWithContentsOfFile: filename];
	ZoomStoryID* fileID = [[ZoomStoryID alloc] initWithZCodeStory: fileData];
	ZoomMetadata* fileMetadata = nil;
	
	// If this file is a blorb file, then extract the IFmd chunk
	const unsigned char* bytes = [fileData bytes];
	
	if (bytes[0] == 'F' && bytes[1] == 'O' && bytes[2] == 'R' && bytes[3] == 'M') {
		ZoomBlorbFile* blorb = [[ZoomBlorbFile alloc] initWithData: fileData];
		NSData* ifMD = [blorb dataForChunkWithType: @"IFmd"];
		
		if (ifMD != nil) {
			fileMetadata = [[ZoomMetadata alloc] initWithData: ifMD];
		} else {
			NSLog(@"Warning: found a game with an IFmd chunk, but was not able to parse it");
		}
		
		[blorb release];
	}
	
	// If we've got an ifMD chunk, then see if we can extract the story from it
	ZoomStory* result = nil;
	
	if (fileMetadata) {
		result = [[fileMetadata findStory: fileID] copy];
		
		if (result == nil) {
			NSLog(@"Warning: found a game with an IFmd chunk, but which did not appear to contain any relevant metadata (looked for ID: %@)", fileID); 
		}
	}
	
	// If there's no result, then make up the data from the filename
	if (result == nil) {
		result = [[ZoomStory alloc] init];
		
		// Add the ID
		[result addID: fileID];
		
		// Behaviour is different for stories that are organised
		NSString* orgDir = [[[ZoomPreferences globalPreferences] organiserDirectory] stringByStandardizingPath];
		BOOL storyIsOrganised = NO;
		
		NSString* mightBeOrgDir = [[[filename stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
		mightBeOrgDir = [mightBeOrgDir stringByStandardizingPath];
		
		if ([orgDir caseInsensitiveCompare: mightBeOrgDir] == NSOrderedSame) storyIsOrganised = YES;
		if (![[[[filename lastPathComponent] stringByDeletingPathExtension] lowercaseString] isEqualToString: @"game"]) storyIsOrganised = NO;
		
		// Build the metadata
		NSString* groupName;
		NSString* gameName;
		
		if (storyIsOrganised) {
			gameName = [[filename stringByDeletingLastPathComponent] lastPathComponent];
			groupName = [[[filename stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] lastPathComponent];
		} else {
			gameName = [[filename stringByDeletingPathExtension] lastPathComponent];
			groupName = @"";
		}
		
		[result setTitle: gameName];
		[result setGroup: groupName];
	}
	
	// Clean up
	[fileID release];
	[fileMetadata release];
	
	// Return the result
	return [result autorelease];
}

// = Initialisation =

- (id) init {
	[NSException raise: @"ZoomCannotInitialiseStoryException"
				format: @"Cannot initialise a ZoomStory object without a corresponding metabase"];
	
	self = [super init];
	
	if (self) {
		story = nil;
		needsFreeing = YES;
		
		extraMetadata = nil;
		
		[[NSNotificationCenter defaultCenter] addObserver: self
												 selector: @selector(extraDataChanged:)
													 name: ZoomStoryExtraMetadataChangedNotification
												   object: nil];		
	}
	
	return self;
}

- (id) initWithStory: (IFStory) s {
	self = [super init];
	
	if (self) {
		story = s;
		needsFreeing = NO;
		
		extraMetadata = nil;
		
		[[NSNotificationCenter defaultCenter] addObserver: self
												 selector: @selector(extraDataChanged:)
													 name: ZoomStoryExtraMetadataChangedNotification
												   object: nil];
	}
	
	return self;
}

- (void) dealloc {
	if (needsFreeing) {
		IFStory_Free(story);
		free(story);
	}
	
	if (extraMetadata) [extraMetadata release];
	
	[[NSNotificationCenter defaultCenter] removeObserver: self];
	
	[super dealloc];
}

// = Accessors =
- (struct IFStory*) story {
	return story;
}

- (void) addID: (ZoomStoryID*) newID {
	int ident;
	int foundID = -1;
	
	IFID oldId = IFMB_IdForStory(story);
	
	if (IFMB_CompareIds(oldId, [newID ident]) != 0) {
		IFID newIdArray[2] = { oldId, [newID ident] };
		IFID newStoryId = IFMB_CompoundId(2, newIdArray);
		
		IFMB_CopyStory(NULL, story, newStoryId);
		IFMB_FreeId(newStoryId);
	}
}

- (NSString*) title {
	return [self objectForKey: @"title"];
}

- (NSString*) headline {
	return [self objectForKey: @"headline"];
}

- (NSString*) author {
	return [self objectForKey: @"author"];
}

- (NSString*) genre {
	return [self objectForKey: @"genre"];
}

- (int) year {
	NSString* stringYear = [self objectForKey: @"year"];
	
	if (stringYear)
		return [stringYear intValue];
	else
		return 0;
}

- (NSString*) group {
	return [self objectForKey: @"group"];
}

- (unsigned) zarfian {
	NSString* zarfian = [[self objectForKey: @"zarfian"] lowercaseString];
	
	if ([zarfian isEqualToString: @"merciful"]) {
		return IFMD_Merciful;
	} else if ([zarfian isEqualToString: @"polite"]) {
		return IFMD_Polite;
	} else if ([zarfian isEqualToString: @"tough"]) {
		return IFMD_Tough;
	} else if ([zarfian isEqualToString: @"nasty"]) {
		return IFMD_Nasty;
	} else if ([zarfian isEqualToString: @"cruel"]) {
		return IFMD_Cruel;
	}

	return IFMD_Unrated;
}

- (NSString*) teaser {
	return [self objectForKey: @"teaser"];
}

- (NSString*) comment {
	return [self objectForKey: @"comment"];
}

- (float)     rating {
	NSString* rating = [self objectForKey: @"rating"];
	
	if (rating) {
		return [rating floatValue];
	} else {
		return -1;
	}
}

- (int) coverPicture {
	NSString* coverPicture = [self objectForKey: @"coverpicture"];
	
	if (coverPicture) {
		return [coverPicture intValue];
	} else {
		return -1;
	}
}

- (NSString*) description {
	return [self objectForKey: @"description"];
}

// = Setting data =

// Setting data
- (void) setTitle: (NSString*) newTitle {
	[self setObject: newTitle
			 forKey: @"title"];
}

- (void) setHeadline: (NSString*) newHeadline {
	[self setObject: newHeadline
			 forKey: @"headline"];
}

- (void) setAuthor: (NSString*) newAuthor {
	[self setObject: newAuthor
			 forKey: @"author"];
}

- (void) setGenre: (NSString*) genre {
	[self setObject: genre
			 forKey: @"genre"];
}

- (void) setYear: (int) year {
	if (year > 0) {
		[self setObject: [NSString stringWithFormat: @"%i", year]
				 forKey: @"year"];
	} else {
		[self setObject: nil
				 forKey: @"year"];
	}
}

- (void) setGroup: (NSString*) group {
	[self setObject: group
			 forKey: @"group"];
}

- (void) setZarfian: (unsigned) zarfian {
	NSString* narf = nil; /* Are you pondering what I'm pondering? */
	
	switch (zarfian) {
		case IFMD_Merciful: narf = @"Merciful"; break;
		case IFMD_Polite: narf = @"Polite"; break;
		case IFMD_Tough: narf = @"Tough"; break;
		case IFMD_Nasty: narf = @"Nasty"; break;
		case IFMD_Cruel: narf = @"Cruel"; break;
	}
	
	[self setValue: narf
			forKey: @"zarfian"];
}

- (void) setTeaser: (NSString*) teaser {
	[self setObject: teaser
			 forKey: @"teaser"];
}

- (void) setComment: (NSString*) comment {
	[self setObject: comment
			 forKey: @"comment"];
}

- (void) setRating: (float) rating {
	if (rating >= 0) {
		[self setObject: [NSString stringWithFormat: @"%g", rating]
				 forKey: @"rating"];
	} else {
		[self setObject: nil
				 forKey: @"rating"];
	}
}

- (void) setCoverPicture: (int) coverpicture {
	if (coverpicture >= 0) {
		[self setObject: [NSString stringWithFormat: @"%i", coverpicture]
				 forKey: @"coverpicture"];
	} else {
		[self setObject: nil
				 forKey: @"coverpicture"];
	}
}

- (void) setDescription: (NSString*) description {
	[self setObject: description
			 forKey: @"description"];
}

// = NSCopying =
/*
- (id) copyWithZone: (NSZone*) zone {
	IFMDStory* newStory = IFStory_Alloc();
	IFStory_Copy(newStory, story);
	
	ZoomStory* res;
	
	res = [[ZoomStory alloc] initWithStory: newStory];
	res->needsFreeing = YES;
	
	return res;
}
*/

// = Story pseudo-dictionary methods =
- (void) loadExtraMetadata {
	if (extraMetadata != nil) return;
	
	NSDictionary* dict = [[NSUserDefaults standardUserDefaults] objectForKey: ZoomStoryExtraMetadata];
	
	// We retrieve the data for the first story ID only. Assuming nothing funny has happened, it
	// will be the same for all IDs associated with this story.
	if (dict == nil || ![dict isKindOfClass: [NSDictionary class]]) {
		extraMetadata = [[NSMutableDictionary alloc] init];
	} else {
		extraMetadata = [[dict objectForKey: [[[self storyIDs] objectAtIndex: 0] description]] mutableCopy];
	}
	
	if (extraMetadata == nil) {
		extraMetadata = [[NSMutableDictionary alloc] init];
	}
}

- (void) storeExtraMetadata {
	// Make a mutable copy of the metadata dictionary
	NSMutableDictionary* newExtraData = [[[[NSUserDefaults standardUserDefaults] objectForKey: ZoomStoryExtraMetadata] mutableCopy] autorelease];
	
	if (newExtraData == nil || ![newExtraData isKindOfClass: [NSMutableDictionary class]]) {
		newExtraData = [[[NSMutableDictionary alloc] init] autorelease];
	}
	
	// Add the data for all our story IDs
	NSEnumerator* idEnum = [[self storyIDs] objectEnumerator];
	ZoomStoryID* storyID;
	
	while (storyID = [idEnum nextObject]) {
		[newExtraData setObject: extraMetadata
						 forKey: [storyID description]];
	}
	
	// Store in the defaults
	[[NSUserDefaults standardUserDefaults] setObject: newExtraData
											  forKey: ZoomStoryExtraMetadata];
	
	// Notify the other stories about the change
	[[NSNotificationCenter defaultCenter] postNotificationName: ZoomStoryExtraMetadataChangedNotification
														object: self];
}

- (void) extraDataChanged: (NSNotification*) not {
	// Respond to notifications about changing metadata
	if (extraMetadata) {
		[extraMetadata release];
		extraMetadata = nil;
		
		// (Reloading prevents a potential bug in the future. It's not absolutely required right now)
		[self loadExtraMetadata];
	}
}

- (NSString*) newKeyForOld: (NSString*) key {
	if ([key isEqualToString: @"title"]) {
		return @"bibliographic.title";
	} else if ([key isEqualToString: @"headline"])  {
		return @"bibliographic.headline";
	} else if ([key isEqualToString: @"author"]) {
		return @"bibliographic.author";
	} else if ([key isEqualToString: @"genre"]) {
		return @"bibliographic.genre";
	} else if ([key isEqualToString: @"group"]) {
		return @"bibliographic.group";
	} else if ([key isEqualToString: @"year"]) {
		return @"bibliographic.firstpublished";
	} else if ([key isEqualToString: @"zarfian"]) {
		return @"bibliographic.forgiveness";
	} else if ([key isEqualToString: @"teaser"]) {
		return @"zoom.teaser";
	} else if ([key isEqualToString: @"comment"]) {
		return @"zoom.comment";
	} else if ([key isEqualToString: @"rating"]) {
		return @"zoom.rating";
	} else if ([key isEqualToString: @"description"]) {
		return @"bibliographic.description";
	} else if ([key isEqualToString: @"coverpicture"]) {
		return @"zcode.coverpicture";
	}

	int x;
	
	for (x=0; x<[key length]; x++) {
		if ([key characterAtIndex: x] == '.') return key;
	}
	
	return [NSString stringWithFormat: @"zoom.extra.%@", key];
}

- (id) objectForKey: (id) key {
	if (![key isKindOfClass: [NSString class]]) {
		[NSException raise: @"ZoomKeyNotString" 
					format: @"Metadata key is not a string"];
		return nil;
	}
	
	id newKey = [self newKeyForOld: key];
	IFChar* value = IFMB_GetValue(story, [newKey UTF8String]);
	
	if (value != nil) {
		int len = IFMB_StrLen(value);
		unichar* characters = malloc(sizeof(unichar)*len);
		int x;
		
		for (x=0; x<len; x++) characters[x] = value[x];
		
		NSString* result = [NSString stringWithCharacters: characters
												   length: len];
		
		free(characters);
		return result;
	} else {
		[self loadExtraMetadata];
		return [extraMetadata objectForKey: key];
	}
}

- (void) setObject: (id) value
			forKey: (id) key {
	if ([key isEqualToString: @"rating"] && [value isKindOfClass: [NSNumber class]]) {
		[self setRating: [value floatValue]];
		return;
	}
	
	if (![value isKindOfClass: [NSString class]] && value != nil) {
		[NSException raise: @"ZoomBadValue" format: @"Metadata value is not a string"];
		return;
	}
	if (![key isKindOfClass: [NSString class]]) {
		[NSException raise: @"ZoomKeyNotString" format: @"Metadata key is not a string"];
		return;
	}
	
	IFChar* metaValue = nil;
	
	if (value != nil) {
		metaValue = malloc(sizeof(IFChar)*([value length]+1));
		
		unichar* characters = malloc(sizeof(unichar)*[value length]);
		int x;
		
		[value getCharacters: characters];
		
		for (x=0; x<[value length]; x++) {
			metaValue[x] = characters[x];
		}
		
		free(characters);
	}
	
	IFMB_SetValue(story, [key UTF8String], metaValue);
	if (metaValue) free(metaValue);
	
	[self heyLookThingsHaveChangedOohShiney];
}

// Searching
- (BOOL) containsText: (NSString*) text {
	// List of strings to check against
	NSArray* stringsToCheck = [[NSArray alloc] initWithObjects: 
		[self title], [self headline], [self author], [self genre], [self group], nil];
	
	// List of words to match against (we take off a word for each match)
	NSMutableArray* words = [[text componentsSeparatedByString: @" "] mutableCopy];
	
	// Loop through each string to check against
	NSEnumerator* searchEnum = [stringsToCheck objectEnumerator];
	NSString* string;
	
	while ([words count] > 0 && (string = [searchEnum nextObject])) {
		int num;
		
		for (num=0; num<[words count]; num++) {
			if ([(NSString*)[words objectAtIndex: num] length] == 0 || 
				[string rangeOfString: [words objectAtIndex: num]
							  options: NSCaseInsensitiveSearch].location != NSNotFound) {
				// Found this word
				[words removeObjectAtIndex: num];
				num--;
				continue;
			}
		}
	}

	// Finish up
	BOOL success = [words count] <= 0;
	
	[words release];
	[stringsToCheck release];
	
	// Is true if there are no words left to match
	return success;
}

// = Sending notifications =
- (void) heyLookThingsHaveChangedOohShiney {
	[[NSNotificationCenter defaultCenter] postNotificationName: ZoomStoryDataHasChangedNotification
														object: self];
}

// Identifying and comparing stories
- (NSArray*) storyIDs {
	NSMutableArray* idArray = [NSMutableArray array];
	
	int ident;
	int count;
	
	IFID singleId[1] = { IFMB_IdForStory(story) };
	IFID* ids = IFMB_SplitId(singleId[0], &count);
	
	if (ids == NULL) {
		ids = singleId;
		count = 1;
	}
	
	for (ident = 0; ident < count; ident++) {
		ZoomStoryID* theId = [[ZoomStoryID alloc] initWithIdent: ids[ident]];
		if (theId) {
			[idArray addObject: theId];
			[theId release];
		}
	}
	
	return idArray;
}

- (BOOL) hasID: (ZoomStoryID*) storyID {
	NSArray* ourIds = [self storyIDs];
	
	return [ourIds containsObject: storyID];
}

- (BOOL) isEquivalentToStory: (ZoomStory*) eqStory {
	if (eqStory == self) return YES; // Shortcut
	
	NSArray* theirIds = [eqStory storyIDs];
	NSArray* ourIds = [self storyIDs];
	
	NSEnumerator* idEnum = [theirIds objectEnumerator];
	ZoomStoryID* thisId;
	
	while (thisId = [idEnum nextObject]) {
		if ([ourIds containsObject: thisId]) return YES;
	}
	
	return NO;
}

@end
