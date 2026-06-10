# client-ipad

SwiftUI iPad app. Project is defined declaratively in `project.yml` — regenerate the Xcode project after editing it:

```sh
xcodegen generate
open Photoboot.xcodeproj
```

`Photoboot.xcodeproj/` is gitignored; only `project.yml` and source files are committed.

## Requirements

- Xcode 16+
- iPadOS 17+ deployment target
- Free Apple ID for personal device signing (re-deploy before each event — 7-day cert)
