# MySJTU iOS

An iOS app for Shanghai Jiao Tong University students, built with SwiftUI.

## Features

- Course schedule and campus-related information
- Canvas GraphQL integration
- Widget extension (`MySJTUWidget`)
- Apple Watch app (`MySJTUWatch`)

## Project Structure

- `MySJTU/` – main iOS app source code
- `MySJTUTests/` – unit tests
- `MySJTUUITests/` – UI tests
- `MySJTUWidget/` – Widget extension
- `MySJTUWatch/` – watchOS app
- `Shared/` – shared code used by multiple targets

## Requirements

- macOS
- Xcode (recommended: latest stable)
- iOS/watchOS SDKs supported by your installed Xcode

## Build and Run

1. Open `MySJTU.xcodeproj` in Xcode.
2. Select the `MySJTU` scheme.
3. Choose a simulator or device and run.

## Test

From Xcode:

- Product → Test

From command line:

```bash
xcodebuild test -project MySJTU.xcodeproj -scheme MySJTU -destination 'platform=iOS Simulator,name=iPhone 15'
```
