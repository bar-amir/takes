-- osascript dmg-layout.applescript <volume name>
-- Lays out the install window: 800 x 480 content, 112 pt icons, the branded background.
-- Positions match scripts/dmg-background.swift.
on run argv
	set volumeName to item 1 of argv
	tell application "Finder"
		tell disk volumeName
			open
			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			set pathbar visible of container window to false
			set the bounds of container window to {160, 120, 960, 628}
			set viewOptions to the icon view options of container window
			set arrangement of viewOptions to not arranged
			set icon size of viewOptions to 112
			set text size of viewOptions to 13
			set label position of viewOptions to bottom
			set shows item info of viewOptions to false
			set background picture of viewOptions to file ".background:background.tiff"
			set position of item "Takes.app" of container window to {240, 230}
			set position of item "Applications" of container window to {560, 230}
			close
			open
			update without registering applications
			delay 2
			close
		end tell
	end tell
end run
