# Contributing

Small tool, small rules.

## Before you open a PR

```bash
swift test          # must stay green
./build.sh          # must produce a launchable, universal dist/Tearoff.app
```

`./build.sh --fast` skips the Intel slice while you iterate; releases are always universal.

If you changed anything visible, regenerate the screenshot so the README matches:

```bash
TEAROFF_SHOT=docs/pads.png swift run -c release Tearoff
```

That renders a fixed set of demo pads, never your real ones.

## What fits here

Tearoff is deliberately small: a pad, a number, one tear a day. Things that fit are bug fixes,
window-behaviour fixes across Spaces and displays, accessibility, localisation, and new paper
stocks or sizes.

Things that don't: reminders and notifications that nag, cloud sync, accounts, analytics of any
kind, and anything that lets you tear more than one sheet in a day. The constraint is the
product. Please open an issue before building a large feature.

## Style

Match the file you're in. The model layer stays free of AppKit and SwiftUI so it remains
testable — put anything that needs a window or a colour in `Sources/Tearoff`.

Comments explain *why*, not what. If a line exists because of an AppKit trap, say which trap.

## Testing UI changes

There is no UI test suite. `TEAROFF_SHOT` renders pads offscreen, which catches layout
regressions; window-level and gesture behaviour has to be checked by hand. Say in the PR
which macOS version you tested on, and whether you tried it with multiple Spaces and a
full-screen app open.
