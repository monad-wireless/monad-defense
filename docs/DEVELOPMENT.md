# Development

## Requirements

| | |
|---|---|
| Xcode | 26 or later |
| iOS | 26 deployment target |
| Swift | 6.0, `SWIFT_STRICT_CONCURRENCY = complete` |
| Dependencies | none |

No package manager, no `Podfile`, no `Package.resolved`. A clone builds with
nothing installed but Xcode.

## Build

```bash
xcodebuild -project MonadDefense.xcodeproj -scheme MonadDefense \
  -destination 'generic/platform=iOS Simulator' build
```

Or open `MonadDefense.xcodeproj` and press ⌘R.

A simulator build needs no configuration at all.

## Signing for a device

Copy the example config and put your team id in it:

```bash
cp Configuration/Local.xcconfig.example Configuration/Local.xcconfig
$EDITOR Configuration/Local.xcconfig
```

`Configuration/Local.xcconfig` is gitignored. `Base.xcconfig` includes it with
`#include?`, so its absence is not an error.

Why a file rather than the Xcode signing pane: Xcode writes `DEVELOPMENT_TEAM`
back into `project.pbxproj` whenever it signs. A team id set there returns in a
later commit no matter how often it is removed, and every clone then fails to
sign until somebody edits a tracked file. Setting it in an ignored config makes
that impossible.

`MONAD_BUNDLE_ID` is overridable in the same file. Change it to install
alongside somebody else's build rather than colliding with it. `design/screenshots.sh`
reads the effective value out of `xcodebuild -showBuildSettings`, so it follows
the override.

## Adding a file

Just add it. `project.pbxproj` uses a `PBXFileSystemSynchronizedRootGroup`
(objectVersion 77), so everything under `MonadDefense/` is picked up
automatically — a new source file or resource needs no project edit.

The project file is hand-authored and readable. Object ids are sequential
`A000…0010` upward rather than Xcode's random hex, so a diff on it is a diff a
person can read. Keep it that way: if Xcode has churned it, prefer reverting and
hand-editing over committing the churn.

`Configuration/` sits **outside** the synchronized group on purpose, so an
`.xcconfig` can never be mistaken for a bundled resource.

## Layout

```
MonadDefense/
  MonadDefenseApp.swift     @main — builds the SwiftData container and the store
  Models/                   ContentModels · ProgressModels · FSRS
  Store/StudyStore.swift    the only reader of content and writer of progress
  Views/                    screens
  Views/Widgets/            one figure widget per file
  Resources/                DeckBank.json + Figures/ — generated, never hand-edited
  Assets.xcassets/          icon and accent colour
Configuration/              Base.xcconfig (tracked) + Local.xcconfig (ignored)
design/                     icon sources (SVG) and the screenshot script
docs/                       this directory
```

Layer rules are in [ARCHITECTURE.md](ARCHITECTURE.md). The short version: views
hold no model logic, and nothing below a layer imports anything above it.

## Conventions

- **No third-party dependencies.** The maths typesetter, the figure renderers
  and the FSRS scheduler are all in this repo. Adding a package needs a reason
  that survives "it is 4,400 lines of Swift and it has no network layer".
- **One widget per file** under `Views/Widgets/`. A widget takes a payload
  struct and knows nothing about which card kind sent it — `FrameScrubber`
  drives any figure expressible as an ordered set of states, which is what makes
  the next animated kind cheap.
- **Comments say why, not what.** The existing ones carry the reasoning behind
  choices that look arbitrary from the outside. Match that.
- **Correct in both appearances.** Every colour comes from `Views/Theme.swift`
  or the asset catalogue. A hardcoded colour is a dark-mode bug waiting.
- **Never hand-edit `Resources/`.** It is compiled output. See
  [CONTENT.md](CONTENT.md).

## Screenshots

```bash
./design/screenshots.sh [simulator-udid]
```

Defaults to an iPhone 17 Pro on iOS 26. It builds, installs, then captures each
shot by relaunching the app with launch arguments that open one specific card:

| argument | opens |
|---|---|
| `-DemoCards a,b,c` | a session over those card ids, in order |
| `-DemoReveal` | every card with its answer already showing |
| `-DemoReader <id>` | the read-only card reader — what following a graph link leads to |
| `-DemoFigures <id>` | only that card's figures, on a plain ground |

That is what makes a screenshot reproducible rather than the result of tapping
in the right order. The router is `Views/DebugRouter.swift` and the whole file
sits inside `#if DEBUG`, so it cannot exist in a release build. A launch
argument that jumps into arbitrary app state is a debugging affordance, not a
feature.

The script also drives the simulator's appearance and content size, because a
figure-bearing card is long and a README screenshot has to fit on one screen.

## Icon

`design/icon-{light,dark,tinted}.svg` are hand-authored. Rasterise to
`MonadDefense/Assets.xcassets/AppIcon.appiconset/` at 1024×1024 after an edit.

The mark is a sibling of the `monad-app` icon: the same M in ink navy
(`#0F142F`), the same three arcs in periwinkle (`#5B6ECC`). monad-app's arcs
radiate outward — a measurement leaving. These are mirrored to open toward the
M, and the accent roles are swapped, so the two read as a family while staying
distinguishable at dock size.

`Views/Theme.swift` carries the same palette for the places the asset catalogue
cannot reach.

## Tests

There are none, and that is a stated gap rather than an oversight. The two
pieces that would repay a test target are `FSRS` (a pure function over a value
type, already isolated from SwiftData for exactly this reason) and
`MathTypeset`'s parser. Neither is covered today.
