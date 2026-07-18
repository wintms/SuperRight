![Repository Icon](https://github.com/wintms/SuperRight/blob/main/SuperRight/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png)
# SuperRight

SuperRight is a native, configurable macOS Finder Sync extension that adds practical actions to Finder's contextual menu.

## Features

- Context-aware behavior for Finder backgrounds, files, folders, and multiple selections
- Create files from built-in or custom templates, with optional naming and automatic opening
- Template variables: `{{filename}}`, `{{directory}}`, `{{path}}`, `{{date}}`, `{{time}}`, and `{{user}}`
- Copy absolute paths, names, relative paths, file URLs, or shell-escaped paths
- Open the current folder in a configurable terminal or editor
- Reorder or hide menu sections
- Manage the Finder folders where SuperRight appears
- First-run setup, extension diagnostics, and Chinese/English localization

Supported terminals include Terminal, iTerm2, Warp, Ghostty, WezTerm, Alacritty, and kitty. Supported editors include Visual Studio Code, Cursor, Zed, Sublime Text, Xcode, Nova, and Fleet.

## Requirements

- macOS 13 or later
- Xcode 27 or later for this project configuration

## Run

1. Open `SuperRight.xcodeproj` in Xcode.
2. Select the `SuperRight` scheme and run the app.
3. Complete the first-run guide: enable the Finder extension and select one or more folders.
4. If the menu does not appear immediately, relaunch Finder with `killall Finder`.

The main app can configure menu visibility/order, the default terminal and editor, file templates, monitored folders, and creation behavior. The Diagnostics tab shows the most recent extension response, action, and error.

## Privacy and storage

The host app runs outside App Sandbox in the real user environment. macOS requires Finder Sync app extensions to retain the App Sandbox entitlement, so the extension uses a direct-distribution absolute-path read/write exception for `/` and can perform Finder actions on the real filesystem. This entitlement is not suitable for Mac App Store distribution. The host app and Finder extension share configuration through an App Group.

If the App Group is unavailable, both processes fall back to the real user's `~/Library/Application Support/SuperRight` directory. Production builds should still configure the App Group for durable, isolated cross-process sharing.

Before signing, replace all example identifiers with identifiers owned by your Apple Developer account:

- `com.example.SuperRight`
- `com.example.SuperRight.FinderExtension`
- `com.example.SuperRightTests`
- `group.com.example.SuperRight`

Update the App Group value in both entitlement files and `MonitoringConfiguration.appGroupIdentifier` together.

## Tests

Run the unit tests from Xcode or with:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project SuperRight.xcodeproj \
  -scheme SuperRight \
  -destination 'platform=macOS,arch=arm64' \
  test
```

Tests cover plain-text templates, variable expansion, duplicate names, invalid names, Word package creation, and backward-compatible settings decoding.

## Distribution

The project targets direct distribution outside the Mac App Store:

1. Replace the example bundle and App Group identifiers.
2. Select the same Apple Developer team for the app, extension, and tests.
3. Enable the App Group for the app and extension identifiers in the developer portal.
4. Archive with a Developer ID Application certificate.
5. Notarize the archive and staple the notarization ticket before distribution.

An automatic updater still needs a real signed release feed and public release URL. Configure that only after the production identifiers, signing keys, and hosting location are finalized; the app deliberately does not ship with a placeholder download endpoint.
