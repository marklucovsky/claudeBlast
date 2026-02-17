# Project notes for Claude

## Build
- Primary scheme: claudeBlast
- Build:
  xcodebuild -scheme "claudeBlast" -configuration Debug build

## Test
- Tests:
  xcodebuild -project claudeBlast.xcodeproj -scheme "claudeBlast" -destination "platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.2" test

## Rules
- Do not change signing/team settings unless asked.
q- Prefer minimal diffs.
