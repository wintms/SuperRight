# SuperRight

SuperRight is a native macOS Finder Sync extension that adds practical actions to Finder's contextual menu.

## Features

- Create an empty text file (`.txt`)
- Create a Markdown file (`.md`)
- Create a Word document (`.docx`)
- Create a JSON file (`.json`)
- Open the current directory in Terminal or iTerm2
- Open the current directory in Visual Studio Code or Warp
- Copy the current path
- Configure monitored Finder directories in the main app

## Requirements

- macOS 15 or later (built and tested with the macOS 27 SDK)
- Xcode 27 or later

## Run

1. Open `SuperRight.xcodeproj` in Xcode.
2. Select the `SuperRight` scheme and run the app.
3. Click **Enable Finder Extension** in the app.
4. In **System Settings > General > Login Items & Extensions > Finder**, enable SuperRight.
5. Relaunch Finder if the menu does not appear immediately:

   ```sh
   killall Finder
   ```

The menu appears as **SuperRight** when right-clicking a Finder window background, folder, or file.

Use the **Finder monitored directories** list in the main app to add or remove folders. Changes are applied to the extension immediately. The configuration is stored locally at `~/Library/Application Support/SuperRight/monitoring.json`.

## Distribution

This project targets direct distribution outside the Mac App Store:

1. Replace `com.example.SuperRight` and the extension bundle identifier with identifiers owned by your developer account.
2. Select your Apple Developer team for both targets.
3. Archive the `SuperRight` scheme with a **Developer ID Application** certificate.
4. Notarize the archive and staple the notarization ticket before distributing it.

The Finder extension remains sandboxed, as required for app extensions, but has narrowly declared temporary exceptions for file-system access and for opening Terminal/iTerm2. Both the app and extension use Hardened Runtime for Developer ID distribution.
