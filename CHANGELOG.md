# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-09-12

First release.

### Added
- Tear-off pads on the desktop layer: any count from 1 to 999, three sizes, six paper stocks.
- Drag-to-tear gesture with one tear per calendar day, enforced; resistance and a shake when
  you pull at a pad you've already torn today.
- Undo for today's tear only; earlier days cannot be rewritten.
- Seven-day dot history and a streak that survives until you actually miss a day.
- Completion face with a `COMPLETE` stamp, and **Start Over** to run the same goal again.
- Menu-bar item with a badge counting the pads still due today, per-pad actions,
  **Keep Pads On Top**, **Hide All Pads**, **Gather Pads on This Desktop** and **Open at Login**.
- Pads remember their position, survive a display being unplugged, and recover to a visible
  screen if their saved origin no longer exists.
- JSON persistence in `~/Library/Application Support/Tearoff/pads.json`, with an unreadable
  file moved to `pads.json.corrupt` rather than overwritten.

[1.0.0]: https://github.com/CoderMayhem/tearoff/releases/tag/v1.0.0
