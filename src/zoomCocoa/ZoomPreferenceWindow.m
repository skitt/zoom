//
//  ZoomPreferenceWindow.m
//  ZoomCocoa
//
//  Created by Andrew Hunter on Sat Dec 20 2003.
//  Copyright (c) 2003 Andrew Hunter. All rights reserved.
//

// Modifications by Collin Pieper to add transparency support

#import "ZoomPreferenceWindow.h"
#import "ZoomStoryOrganiser.h"


static NSToolbarItem* generalSettingsItem;
static NSToolbarItem* gameSettingsItem;
static NSToolbarItem* displaySettingsItem;
static NSToolbarItem* fontSettingsItem;
static NSToolbarItem* colourSettingsItem;
static NSToolbarItem* typographicSettingsItem;

static NSDictionary*  itemDictionary = nil;

@implementation ZoomPreferenceWindow

+ (void) initialize {
	// Create the toolbar items
	generalSettingsItem = [[NSToolbarItem alloc] initWithItemIdentifier: @"generalSettings"];
	gameSettingsItem = [[NSToolbarItem alloc] initWithItemIdentifier: @"gameSettings"];
	displaySettingsItem = [[NSToolbarItem alloc] initWithItemIdentifier: @"displaySettings"];
	fontSettingsItem = [[NSToolbarItem alloc] initWithItemIdentifier: @"fontSettings"];
	colourSettingsItem = [[NSToolbarItem alloc] initWithItemIdentifier: @"colourSettings"];
	typographicSettingsItem = [[NSToolbarItem alloc] initWithItemIdentifier: @"typographicSettings"];
	
	// ... and the dictionary
	itemDictionary = [[NSDictionary dictionaryWithObjectsAndKeys:
		generalSettingsItem, @"generalSettings",
		gameSettingsItem, @"gameSettings",
		displaySettingsItem, @"displaySettings",
		fontSettingsItem, @"fontSettings",
		colourSettingsItem, @"colourSettings",
		typographicSettingsItem, @"typographicSettings",
		nil] retain];
	
	// Set up the items
	[generalSettingsItem setLabel: @"General"];
	[generalSettingsItem setImage: [[[NSImage alloc] initWithContentsOfFile: [[NSBundle mainBundle] pathForImageResource: @"generalSettings"]] autorelease]];
	[gameSettingsItem setLabel: @"Game"];
	[gameSettingsItem setImage: [[[NSImage alloc] initWithContentsOfFile: [[NSBundle mainBundle] pathForImageResource: @"gameSettings"]] autorelease]];
	[displaySettingsItem setLabel: @"Display"];
	[displaySettingsItem setImage: [[[NSImage alloc] initWithContentsOfFile: [[NSBundle mainBundle] pathForImageResource: @"displaySettings"]] autorelease]];
	[fontSettingsItem setLabel: @"Fonts"];
	[fontSettingsItem setImage: [[[NSImage alloc] initWithContentsOfFile: [[NSBundle mainBundle] pathForImageResource: @"fontSettings"]] autorelease]];
	[colourSettingsItem setLabel: @"Colour"];
	[colourSettingsItem setImage: [[[NSImage alloc] initWithContentsOfFile: [[NSBundle mainBundle] pathForImageResource: @"colourSettings"]] autorelease]];
	[typographicSettingsItem setLabel: @"Typography"];
	[typographicSettingsItem setImage: [[[NSImage alloc] initWithContentsOfFile: [[NSBundle mainBundle] pathForImageResource: @"typographicSettings"]] autorelease]];
	
	// And the actions
	[generalSettingsItem setAction: @selector(generalSettings:)];
	[gameSettingsItem setAction: @selector(gameSettings:)];
	[displaySettingsItem setAction: @selector(displaySettings:)];
	[fontSettingsItem setAction: @selector(fontSettings:)];
	[colourSettingsItem setAction: @selector(colourSettings:)];	
	[typographicSettingsItem setAction: @selector(typographicSettings:)];	
}

- (id) init {
	return [self initWithWindowNibName: @"Preferences"];
}

- (void) dealloc {
	if (toolbar) [toolbar release];
	if (prefs) [prefs release];

	[[NSNotificationCenter defaultCenter] removeObserver: self];
	
	[super dealloc];
}

static int familyComparer(id a, id b, void* context) {
	NSString* family1 = a;
	NSString* family2 = b;
	
	return [family1 caseInsensitiveCompare: family2];
}

- (NSMenu*) fontMenu: (BOOL) fixed {
	// Constructs a menu of fonts
	// (Apple want us to use the font selection panel, but it feels clunky for the 'simple' view: there's no good way to associate
	// it with the style we're selecting. Plus we want to select families, not individual fonts)
	NSFontManager* mgr = [NSFontManager sharedFontManager];

	NSMenu* result = [[NSMenu alloc] init];
	
	// Iterate through the available font families and create menu items
	NSEnumerator* familyEnum = [[[mgr availableFontFamilies] sortedArrayUsingFunction: familyComparer
																			  context: nil] objectEnumerator];
	NSString* family;
	
	while (family = [familyEnum nextObject]) {
		// Get the font
		NSFont* sampleFont = [mgr fontWithFamily: family
										  traits: 0
										  weight: 5
											size: 13.0];
		
		if (!sampleFont) continue;
		if (fixed && ![sampleFont isFixedPitch]) {
			// Skip this font
			continue;
		}
		
		// Construct the item
		NSMenuItem* fontItem = [[NSMenuItem alloc] init];
		[fontItem setAttributedTitle: 
			[[[NSAttributedString alloc] initWithString: family
											 attributes: [NSDictionary dictionaryWithObject: sampleFont
																					 forKey: NSFontAttributeName]] autorelease]];
		
		// Add to the menu
		[result addItem: [fontItem autorelease]];
	}
	
	// Return the result
	return [result autorelease];
}

- (void) windowDidLoad {
	// Set the toolbar
	toolbar = [[NSToolbar allocWithZone: [self zone]] initWithIdentifier: @"preferencesToolbar2"];
		
	[toolbar setDelegate: self];
	[toolbar setDisplayMode: NSToolbarDisplayModeIconAndLabel];
	[toolbar setAllowsUserCustomization: NO];
	
	[[self window] setToolbar: toolbar];
	
	[[self window] setContentSize: [generalSettingsView frame].size];
	[[self window] setContentView: generalSettingsView];

	if ([toolbar respondsToSelector: @selector(setSelectedItemIdentifier:)]) {
		[toolbar setSelectedItemIdentifier: @"generalSettings"];
	}
	
	
	[fonts setDataSource: self];
	[fonts setDelegate: self];
	[colours setDataSource: self];
	[colours setDelegate: self];
	
	// Set up the various font menus
	[proportionalFont setMenu: [self fontMenu: NO]];
	[fixedFont setMenu: [self fontMenu: YES]];
	[symbolicFont setMenu: [self fontMenu: NO]];
	
	[[NSNotificationCenter defaultCenter] addObserver: self
											 selector: @selector(storyProgressChanged:)
												 name: ZoomStoryOrganiserProgressNotification
											   object: [ZoomStoryOrganiser sharedStoryOrganiser]];
}

// == Setting the pane that's being displayed ==

- (void) switchToPane: (NSView*) preferencePane {
	if ([[self window] contentView] == preferencePane) return;
	
	// Select the appropriate item in the toolbar
	if ([toolbar respondsToSelector: @selector(setSelectedItemIdentifier:)]) {
		NSString* selected = nil;
		
		if (preferencePane == generalSettingsView) {
			selected = @"generalSettings";
		} else if (preferencePane == gameSettingsView) {
			selected = @"gameSettings";
		} else if (preferencePane == displaySettingsView) {
			selected = @"displaySettings";
		} else if (preferencePane == fontSettingsView) {
			selected = @"fontSettings";
		} else if (preferencePane == colourSettingsView) {
			selected = @"colourSettings";
		} else if (preferencePane == typographicalSettingsView) {
			selected = @"typographicSettings";
		}
		
		if (selected != nil) {
			[toolbar setSelectedItemIdentifier: selected];
		}
	}
	
	// Work out the various frame sizes
	NSRect currentFrame = [[[self window] contentView] frame];
	NSRect oldFrame = currentFrame;
	NSRect windowFrame = [[self window] frame];
	
	currentFrame.origin.y    -= [preferencePane frame].size.height - currentFrame.size.height;
	currentFrame.size.height  = [preferencePane frame].size.height;
	
	// Grr, complicated, as OS X provides no way to work out toolbar proportions except in 10.3
	windowFrame.origin.x    += (currentFrame.origin.x - oldFrame.origin.x);
	windowFrame.origin.y    += (currentFrame.origin.y - oldFrame.origin.y);
	windowFrame.size.width  += (currentFrame.size.width - oldFrame.size.width);
	windowFrame.size.height += (currentFrame.size.height - oldFrame.size.height);
	
	[[self window] setContentView: [[[NSView alloc] init] autorelease]];
	[[self window] setFrame: windowFrame
					display: YES
					animate: YES];
	[[self window] setContentView: preferencePane];
}

// == Toolbar delegate functions ==

- (NSToolbarItem *)toolbar: (NSToolbar *) toolbar
     itemForItemIdentifier: (NSString *)  itemIdentifier
 willBeInsertedIntoToolbar: (BOOL)        flag {
    return [itemDictionary objectForKey: itemIdentifier];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar {
    return [NSArray arrayWithObjects:
		@"generalSettings", @"gameSettings", @"displaySettings", @"fontSettings", @"typographicSettings", @"colourSettings", NSToolbarFlexibleSpaceItemIdentifier,
		nil];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar {
    return [NSArray arrayWithObjects:
		NSToolbarFlexibleSpaceItemIdentifier, @"generalSettings", @"gameSettings", @"displaySettings", @"fontSettings", @"typographicSettings", @"colourSettings", NSToolbarFlexibleSpaceItemIdentifier,
		nil];
}

- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar {
    return [NSArray arrayWithObjects:
		@"generalSettings", @"gameSettings", @"displaySettings", @"fontSettings", @"colourSettings", @"typographicSettings",
		nil];	
}

// == Toolbar actions ==

- (void) generalSettings: (id) sender {
	[self switchToPane: generalSettingsView];
}

- (void) gameSettings: (id) sender {
	[self switchToPane: gameSettingsView];
}

- (void) displaySettings: (id) sender {
	[self switchToPane: displaySettingsView];
}

- (void) fontSettings: (id) sender {
	[self switchToPane: fontSettingsView];
}

- (void) colourSettings: (id) sender {
	[self switchToPane: colourSettingsView];
}

- (void) typographicSettings: (id) sender {
	[self switchToPane: typographicalSettingsView];
}

// == Setting the preferences that we're editing ==

- (void) setButton: (NSPopUpButton*) button
	  toFontFamily: (NSString*) family {
	NSMenuItem* familyItem = nil;
	NSEnumerator* itemEnum = [[[button menu] itemArray] objectEnumerator];
	NSMenuItem* curItem;
	
	while (curItem = [itemEnum nextObject]) {
		if ([[curItem title] caseInsensitiveCompare: family] == NSEqualToComparison) {
			familyItem = curItem;
			break;
		}
	}
	
	if (familyItem) {
		[button selectItem: familyItem];
	}
}

- (void) setSimpleFonts {
	// Sets our display from the 'simple' fonts the user has selected
	
	// Select the fonts
	[self setButton: proportionalFont 
	   toFontFamily: [prefs proportionalFontFamily]];
	[self setButton: fixedFont
	   toFontFamily: [prefs fixedFontFamily]];
	[self setButton: symbolicFont 
	   toFontFamily: [prefs symbolicFontFamily]];
	
	// Set the size display
	float fontSize = [prefs fontSize];
	[fontSizeSlider setFloatValue: fontSize];
	[fontSizeDisplay setStringValue: [NSString stringWithFormat: @"%.1fpt", fontSize]];
	
	// Set the font preview
	[fontPreview setFont: [[prefs fonts] objectAtIndex: 0]];
}

- (void) setPreferences: (ZoomPreferences*) preferences {
	if (prefs) [prefs release];
	prefs = [preferences retain];
	
	[displayWarnings setState: [prefs displayWarnings]?NSOnState:NSOffState];
	[fatalWarnings setState: [prefs fatalWarnings]?NSOnState:NSOffState];
	[speakGameText setState: [prefs speakGameText]?NSOnState:NSOffState];
	[scrollbackLength setFloatValue: [prefs scrollbackLength]];
	[keepGamesOrganised setState: [prefs keepGamesOrganised]?NSOnState:NSOffState];
	[autosaveGames setState: [prefs autosaveGames]?NSOnState:NSOffState];
	[reorganiseGames setEnabled: [prefs keepGamesOrganised]];
	[confirmGameClose setState: [prefs confirmGameClose]?NSOnState:NSOffState];
	
	// a kind of chessy way to get the current alpha setting
	float red, green, blue, alpha;
	NSColor * color = [[prefs colours] objectAtIndex:0];
	[color getRed:&red green:&green blue:&blue alpha:&alpha];
	[transparencySlider setFloatValue:(alpha * 100.0)];
	
	[interpreter selectItemAtIndex: [prefs interpreter]-1];
	[revision setStringValue: [NSString stringWithFormat: @"%c", [prefs revision]]];
	
	[self setSimpleFonts];
	
	[organiseDir setString: [prefs organiserDirectory]];
	
	[showMargins setState: [prefs textMargin] > 0?NSOnState:NSOffState];
	[useScreenFonts setState: [prefs useScreenFonts]?NSOnState:NSOffState];
	[useHyphenation setState: [prefs useHyphenation]?NSOnState:NSOffState];
	
	[marginWidth setEnabled: [prefs textMargin] > 0];
	if ([prefs textMargin] > 0) {
		[marginWidth setFloatValue: [prefs textMargin]];
	}
}

// == Table data source ==

- (int)numberOfRowsInTableView: (NSTableView *)aTableView {
	if (aTableView == fonts) return [[prefs fonts] count];
	if (aTableView == colours) return [[prefs colours] count];
	
	return 0;
}

static void appendStyle(NSMutableString* styleName,
						NSString* newStyle) {
	if ([styleName length] == 0) {
		[styleName appendString: newStyle];
	} else {
		[styleName appendString: @"-"];
		[styleName appendString: newStyle];
	}
}

- (id)              tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
						  row:(int)rowIndex {
	if (aTableView == fonts) {
		// Fonts table
		NSArray* fontArray = [prefs fonts];
		
		if ([[aTableColumn identifier] isEqualToString: @"Style"]) {
			NSMutableString* name = [[@"" mutableCopy] autorelease];
			
			if (rowIndex&1) appendStyle(name, @"bold");
			if (rowIndex&2) appendStyle(name, @"italic");
			if (rowIndex&4) appendStyle(name, @"fixed");
			if (rowIndex&8) appendStyle(name, @"symbolic");
			
			if ([name isEqualToString: @""]) name = [[@"roman" mutableCopy] autorelease];
			
			return name;
		} else if ([[aTableColumn identifier] isEqualToString: @"Font"]) {
			NSString* fontName;
			NSFont* font = [fontArray objectAtIndex: rowIndex];
			
			fontName = [NSString stringWithFormat: @"%@ (%.2gpt)", 
				[font fontName],
				[font pointSize]];
			
			NSAttributedString* res;
			
			res = [[[NSAttributedString alloc] initWithString: fontName
												   attributes: [NSDictionary dictionaryWithObject: font
																						   forKey: NSFontAttributeName]]
				autorelease];
			
			return res;
		}
		
		return @" -- ";
	}
	
	if (aTableView == colours) {
		if ([[aTableColumn identifier] isEqualToString: @"Colour name"]) {
			switch (rowIndex) {
				case 0: return @"Black";
				case 1: return @"Red";
				case 2: return @"Green";
				case 3: return @"Yellow";
				case 4: return @"Blue";
				case 5: return @"Magenta";
				case 6: return @"Cyan";
				case 7: return @"White";
				case 8: return @"Light grey";
				case 9: return @"Medium grey";
				case 10: return @"Dark grey";
				default: return @"Unused colour";
			}
			
		} else if ([[aTableColumn identifier] isEqualToString: @"Colour"]) {
			NSColor* theColour = [[prefs colours] objectAtIndex: rowIndex];
			NSAttributedString* res;
			
			res = [[NSAttributedString alloc] initWithString: @"Sample"
												  attributes: [NSDictionary dictionaryWithObjectsAndKeys:
													  theColour, NSForegroundColorAttributeName,
													  theColour, NSBackgroundColorAttributeName,
													  nil]];
			
			return [res autorelease];
		}
		
		return @" -- ";
	}
	
	return @" -- ";
}

// == Table delegate ==

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
	if ([aNotification object] == fonts) {
		int selFont = [fonts selectedRow];
		
		if (selFont < 0) {
			return;
		}

		NSFont* font = [[prefs fonts] objectAtIndex: selFont];
		
		// Display font panel
		[[NSFontPanel sharedFontPanel] setPanelFont: font
										 isMultiple: NO];
		[[NSFontPanel sharedFontPanel] setEnabled: YES];
		[[NSFontPanel sharedFontPanel] setAccessoryView: nil];
		[[NSFontPanel sharedFontPanel] orderFront: self];
		[[NSFontPanel sharedFontPanel] reloadDefaultFontFamilies];
	} else if ([aNotification object] == colours) {
		int selColour = [colours selectedRow];
		
		if (selColour < 0) {
			return;
		}
		
		NSColor* colour = [[prefs colours] objectAtIndex: selColour];
		
		// Display colours
		[[NSColorPanel sharedColorPanel] setColor: colour];
		[[NSColorPanel sharedColorPanel] setAccessoryView: nil];
		[[NSColorPanel sharedColorPanel] orderFront: self];
	}
}

// == Font panel delegate ==

- (void) changeFont:(id) sender {
	// Change the selected font in the font table
	int selFont = [fonts selectedRow];
	
	if (selFont < 0) return;
	
	NSMutableArray* prefFonts = [[prefs fonts] mutableCopy];
	NSFont* newFont;
	
	newFont = [sender convertFont: [prefFonts objectAtIndex: selFont]];

	if (newFont) {
		[prefFonts replaceObjectAtIndex: selFont
						 withObject: newFont];
		[prefs setFonts: prefFonts];
		
		[fonts reloadData];
	}
	
	[prefFonts release];
	
	[self setSimpleFonts];
}

- (void)changeColor:(id)sender {	
	int selColour = [colours selectedRow];
	
	if (selColour < 0) {
		return;
	}
	
	NSColor* selected_colour = [[NSColorPanel sharedColorPanel] color];
	NSColor* colour = [[selected_colour colorUsingColorSpaceName: NSCalibratedRGBColorSpace] colorWithAlphaComponent:(([transparencySlider floatValue] / 100.0))];
	
	NSMutableArray* cols = [[prefs colours] mutableCopy];
	
	if (colour) {
		[cols replaceObjectAtIndex: selColour
						withObject: colour];
		[prefs setColours: cols];
		
		[colours reloadData];
	}
	
	[cols release];
}

- (void)changeTransparency:(id)sender {
	NSMutableArray* cols = [[prefs colours] mutableCopy];
	
	int i;
	for(  i = 0; i < [cols count]; i++ )
	{
		NSColor * color = [cols objectAtIndex: i];
	
		NSColor*  transparent_color = [[color colorUsingColorSpaceName: NSCalibratedRGBColorSpace] colorWithAlphaComponent:([transparencySlider floatValue] / 100.0)];
		
		[cols replaceObjectAtIndex: i
						withObject: transparent_color];
	}

	[prefs setColours: cols];
		
	[colours reloadData];
	
	[cols release];
}

// == Various actions ==

- (IBAction) interpreterChanged: (id) sender {
	[prefs setInterpreter: [interpreter indexOfSelectedItem]+1];
}

- (IBAction) revisionChanged: (id) sender {
	[prefs setRevision: [[revision stringValue] characterAtIndex: 0]];
}

- (IBAction) displayWarningsChanged: (id) sender {
	[prefs setDisplayWarnings: [sender state]==NSOnState];
}

- (IBAction) fatalWarningsChanged: (id) sender {
	[prefs setFatalWarnings: [sender state]==NSOnState];
}

- (IBAction) speakGameTextChanged: (id) sender {
	[prefs setSpeakGameText: [sender state]==NSOnState];
}

- (IBAction) scrollbackChanged: (id) sender {
	[prefs setScrollbackLength: [sender floatValue]];
}

- (IBAction) autosaveChanged: (id) sender {
	[prefs setAutosaveGames: [sender state]==NSOnState];
}

- (IBAction) confirmGameCloseChanged: (id) sender {
	[prefs setConfirmGameClose: [sender state]==NSOnState];
}

- (IBAction) keepOrganisedChanged: (id) sender {
	[prefs setKeepGamesOrganised: [sender state]==NSOnState];
	[reorganiseGames setEnabled: [sender state]==NSOnState];
	if ([sender state]==NSOffState) {
		[autosaveGames setState: NSOffState];
		[prefs setAutosaveGames: NO];
	}
}

- (void) changeOrganiserDirTo: (NSOpenPanel *)sheet
				   returnCode: (int)returnCode
				  contextInfo: (void *)contextInfo {
	if (returnCode != NSOKButton) return;
	
	[[ZoomStoryOrganiser sharedStoryOrganiser] reorganiseStoriesTo: [sheet directory]];
	[prefs setOrganiserDirectory: [sheet directory]];
	[organiseDir setString: [prefs organiserDirectory]];
}

- (IBAction) changeOrganiseDir: (id) sender {
	NSOpenPanel* dirChooser = [NSOpenPanel openPanel];
	
	[dirChooser setAllowsMultipleSelection: NO];
	[dirChooser setCanChooseDirectories: YES];
	[dirChooser setCanChooseFiles: NO];
	[dirChooser setCanCreateDirectories: YES];
	
	NSString* path = [prefs organiserDirectory];
	
	[dirChooser beginSheetForDirectory: path
								  file: nil
								 types: nil
						modalForWindow: [self window]
						 modalDelegate: self
						didEndSelector: @selector(changeOrganiserDirTo:returnCode:contextInfo:)
						   contextInfo: nil];
}

- (IBAction) resetOrganiseDir: (id) sender {
	if ([prefs keepGamesOrganised]) {
		[[ZoomStoryOrganiser sharedStoryOrganiser] reorganiseStoriesTo: [ZoomPreferences defaultOrganiserDirectory]];
	}
	[prefs setOrganiserDirectory: nil];
	[organiseDir setString: [prefs organiserDirectory]];
}


- (IBAction) simpleFontsChanged: (id) sender {
	// This action applies to all the font controls
	
	// Set the size, if it has changed
	float newSize = floorf([fontSizeSlider floatValue]);
	if (newSize != [prefs fontSize]) [prefs setFontSize: newSize];
	
	// Set the families, if they've changed
	NSString* propFamily = [[proportionalFont selectedItem] title];
	NSString* fixedFamily = [[fixedFont selectedItem] title];
	NSString* symbolicFamily = [[symbolicFont selectedItem] title];
	
	if (![propFamily isEqualToString: [prefs proportionalFontFamily]]) [prefs setProportionalFontFamily: propFamily];
	if (![fixedFamily isEqualToString: [prefs fixedFontFamily]]) [prefs setFixedFontFamily: fixedFamily];
	if (![symbolicFamily isEqualToString: [prefs symbolicFontFamily]]) [prefs setSymbolicFontFamily: symbolicFamily];
	
	// Update the display
	[self setSimpleFonts];
}

// = Typographical changes =

- (IBAction) marginsChanged: (id) sender {
	// Work out the new margin size
	float oldSize = [prefs textMargin];
	float newSize;
	
	if ([showMargins state] == NSOffState) {
		newSize = 0;
		[marginWidth setEnabled: NO];
	} else if ([showMargins state] == NSOnState && oldSize <= 0) {
		newSize = 10.0;
		[marginWidth setEnabled: YES];
	} else {
		newSize = floorf([marginWidth floatValue]);
		[marginWidth setEnabled: YES];
	}
	
	if (newSize != oldSize) {
		[prefs setTextMargin: newSize];
	}
}

- (IBAction) screenFontsChanged: (id) sender {
	BOOL newState = [useScreenFonts state]==NSOnState;
	
	if (newState != [prefs useScreenFonts]) {
		[prefs setUseScreenFonts: newState];
	}	
}

- (IBAction) hyphenationChanged: (id) sender {
	BOOL newState = [useHyphenation state]==NSOnState;
	
	if (newState != [prefs useHyphenation]) {
		[prefs setUseHyphenation: newState];
	}
}

// = Story progress meter =

- (void) storyProgressChanged: (NSNotification*) not {
	NSDictionary* userInfo = [not userInfo];
	BOOL activated = [[userInfo objectForKey: @"ActionStarting"] boolValue];
	
	if (activated) {
		indicatorCount++;
	} else {
		indicatorCount--;
	}
	
	if (indicatorCount <= 0) {
		indicatorCount = 0;
		[organiserIndicator stopAnimation: self];
	} else {
		[organiserIndicator startAnimation: self];
	}
}

- (IBAction) reorganiseGames: (id) sender {
	// Can't use this if keepGamesOrganised is off
	if (![prefs keepGamesOrganised]) return;
	
	// Reorganise all the stories
	[[ZoomStoryOrganiser sharedStoryOrganiser] organiseAllStories];
}

@end
