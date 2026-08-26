# Architecture

Four layers, one direction of dependency.

```
Views/          SwiftUI screens and figure widgets
   ↓
Store/          StudyStore — the one place that reads content and writes progress
   ↓
Models/         ContentModels (bundled, read-only) · ProgressModels (SwiftData) · FSRS
   ↓
Resources/      DeckBank.json + Figures/ — compiled elsewhere, never edited here
```

Nothing below a layer imports anything above it. There is no networking layer,
no dependency-injection container and no third-party package. The whole app is
4,400 lines of Swift.

## Two stores that never mix

The app holds two kinds of state, and keeping them apart is the load-bearing
design decision.

| | Content | Progress |
|---|---|---|
| what | cards, decks, figures, formulas | FSRS schedule, review log, curation notes |
| where | `DeckBank.json` in the app bundle | SwiftData on the device |
| written by | the `edu deck compile` pipeline, in the parent repo | the app, as you study |
| lifetime | replaced whole on every content refresh | survives every content refresh |
| joined by | — | stable card ids |

Progress rows carry a `cardID` and nothing else about the card. A content
refresh therefore rewrites every card without touching a single review. A card
whose id disappears from the bank leaves an orphan row, and
`StudyStore.pruneOrphans()` deletes it at the next launch.

The consequence to remember when authoring: **a card id is a promise**. Change
an id in a deck note and you have thrown away that card's review history, even
if its text did not move.

## StudyStore

`Store/StudyStore.swift` is a `@MainActor @Observable` class, constructed once
in `MonadDefenseApp.init` and passed down the view tree as an environment
value. It owns:

- the decoded `DeckBank`, plus `cardsByID` and `decksBySlug` lookups built once
  at launch,
- every read and write of the SwiftData context,
- the six session builders,
- the curation notes and their two export formats,
- the statistics feeds the Stats tab renders.

Views hold no model logic. They ask the store for a `StudySession` and render
what comes back.

### The six session modes

Each is a different answer to "what should I study now", and each is a pure
function of the bank plus the progress rows.

| mode | pool | order |
|---|---|---|
| `review` | cards due now, topped up with new ones | due date, oldest first |
| `quiz` | `mcq` and `formula` cards, optionally one track | half weakest, half random, then shuffled |
| `fundamentals` | the `core` track | weakest first, then shuffled |
| `committee` | every card with `defense: true` | weakest first, then shuffled |
| `deck` | one deck | shuffled |
| `explore` | a card and everything it links to | declaration order |

"Weakest" means lowest FSRS retrievability, with an unseen card counting as
zero. The quiz deliberately mixes half-random cards in: a pure weakest-first
queue becomes a rut, and drills the same dozen cards until they are the only
ones you know.

`explore` is the mode that grades nothing. Following a link is reading, not
rehearsal, and letting curiosity move the schedule would corrupt it.

## FSRS

`Models/FSRS.swift` is a self-contained FSRS-5 implementation — the default
19-weight parameter vector, desired retention 0.9, decay −0.5, learning steps
at 1 min and 10 min, one 10-min relearning step, and intervals capped at one
year.

It is written as a pure `enum` of static functions over an `FSRSSnapshot`
value. Nothing in it touches SwiftData, so it is testable in isolation, and
`CardProgress` converts to and from the snapshot at the boundary.

There is no parameter optimiser. A single-user bank of 433 cards does not
produce enough review history to fit 19 weights better than the published
defaults do.

## Figures

`Figure` is an enum with one case per figure kind, decoded by a `kind`
discriminator string. `Views/FigureView.swift` switches on it and each case
renders through its own widget under `Views/Widgets/`.

An unknown `kind` decodes to `.unsupported(String)` rather than throwing. That
choice matters: a bank compiled by a newer pipeline than the installed app
should degrade to "this card has a picture you cannot see yet", never to a
`fatalError` at launch.

Three properties hold across every kind:

- **Nothing is a raster except `image`.** Plots, diagrams, tables and sequence
  charts are drawn with native shapes, so they scale with the reader's type
  size and are correct in dark mode by construction.
- **Nothing scrolls sideways.** A table of up to three columns lays out as a
  grid; beyond that each row becomes a stacked block.
- **Nothing is computed at runtime.** Plot curves arrive pre-sampled. The app
  carries no expression evaluator, so a malformed expression is a compile
  failure in the parent repo rather than a blank chart on the phone.

`FrameScrubber` knows nothing about plots. It drives any figure expressible as
an ordered set of states, which is what makes the next animated kind cheap.

## Maths

`Views/MathTypeset.swift` parses a restricted LaTeX subset into a node tree and
lays it out with SwiftUI: greek letters, `\frac`, `\sqrt`, sub- and
superscripts, `\sum` with limits, accents, `\mathrm`, `\mathbf`, and the usual
relations. Fractions and big operators sit on the maths axis rather than the
text baseline. A long formula shrinks to fit before it becomes a horizontal
scroller.

Anything it cannot parse falls back to the raw source in monospace. A formula
that renders as its own LaTeX is ugly. One that crashes the session is worse.

## The card graph

A card declares `see_also:`, and the compiler makes every link **symmetric**.
There are therefore no one-way streets: from CSI you reach OFDM, and from OFDM
you can walk back.

`RelatedCards` opens a read-only reader on the target, which can be walked
onward to any depth. It grades nothing, for the reason given under `explore`.

## Curation

`Views/CurateView.swift` and `CurationPassView.swift` sweep the whole bank with
the answers open. One verdict per card — `keep`, `more`, `fix`, `cut` — plus a
free-text note, stored as one `CardNote` row per card, upserted on edit.

`StudyStore.curationExportJSON` emits `monad-defense/curation/1`, which
`monad-knowledge edu deck curation` reads in the parent repo. The Markdown twin
is for pasting into a note. Both carry the `bank_version` the verdicts were
made against, so a stale export is detectable rather than silently applied to
cards that have since changed.

See [CONTENT.md](CONTENT.md) for the loop this closes.

## Debug router

`Views/DebugRouter.swift` reads launch arguments and opens a chosen card, a
chosen reader or a chosen card's figures straight from launch. It exists so
`design/screenshots.sh` is reproducible rather than the result of tapping in
the right order.

The whole file sits inside `#if DEBUG` and therefore cannot exist in a release
build. A launch argument that jumps into arbitrary app state is a debugging
affordance, not a feature, and shipping one would be an invitation.

## Staleness

The content refresh is deliberately **not** an Xcode build phase. The build
stays fast, offline, and independent of the parent repo and its Python
environment.

The cost of that choice is that a stale bank is invisible. So the bank carries
its `generated_at`, and `StalenessNotice` prints one quiet line on the Today
screen once the age passes fourteen days. Never a modal: a stale bank is still
a usable bank, and interrupting a session to say so would be worse than the
staleness.
