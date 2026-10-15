# Architecture

Four layers, one direction of dependency.

```
Views/          SwiftUI screens and figure widgets
   ↓
Store/          StudyStore — reads content, writes progress · DeskStore — writes desk sessions
   ↓
Net/            DeskConnection — the Desk API (IP-172), bearer token in the Keychain
   ↓
Models/         ContentModels (bundled, read-only) · ProgressModels (SwiftData) · FSRS
                DeskModels (banks, rules, event chain) · DeskRecords (SwiftData)
   ↓
Resources/      DeckBank.json + Figures/ + Desk/DeskBank-*.json — compiled elsewhere, never edited here
```

Nothing below a layer imports anything above it. There is no dependency-injection
container and no third-party package.

## Three tabs (IP-172)

| Tab | Job | Root |
|---|---|---|
| Curate | Decide: Desk banks and sessions, phone texts | `Views/Desk/DeskHomeView` |
| Library | Read: papers and claims with evidence marked | `Views/Library/LibraryView` |
| Defense | Prepare: Today, Tracks, Thesis guide, Progress | `Views/Defense/DefenseView` |

The four Defense screens keep their own navigation stacks under a segmented
control: the thesis guide drives its path programmatically for deep links.

`Views/Evidence/EvidenceText.swift` is the one highlighting component. Server
offsets (`evidence_start`, `evidence_end`) count Unicode scalars, the indices of
a Python string, so the component indexes `unicodeScalars`, never UTF-16.

## The Desk API (IP-172)

`monad_knowledge/desk_api` on `desk.monad.dubec.dev`. The app reads banks
(`GET /api/banks`, cached under Application Support `DeskBanks/` with their
ETag), sends a locked session (`POST /api/exports`), fetches its receipt
(`GET /api/receipts/<session>`), and reads the Library (`/api/papers`,
`/api/claims`, `/api/search`). On the Mac, `kb desk publish` uploads a bank and
`kb desk pull` imports the inbox. Without a token the app works from what it
bundled and cached.

## Two stores that never mix

The app holds two kinds of state, and keeping them apart is the load-bearing
design decision.

| | Content | Progress |
|---|---|---|
| what | cards, decks, figures, formulas, desk banks | FSRS schedule, review log, curation notes, desk events |
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

## Swipe stacks

The card-note curation pass was removed by IP-172. `CardNote` stays registered
in the SwiftData container so existing stores open without a migration; nothing
writes it.

The phone-text stacks (dwell review, eggs) and the Desk run on one generic deck, `TriageDeckView<Item>` (`Views/Triage/`). An action returns a
`TriageOutcome`: `.saved` advances the deck, `.failed` keeps the card and shows
why, `.edit` presents an editor sheet and advances only after that editor saved.

## Desk (IP-161)

The Desk curates the claim graph offline: Vocabulary, Fidelity and Citation
tasks compiled in the parent repo by `kb desk compile --out
MonadDefense/Resources/Desk/DeskBank-<name>.json`. The bundle is flat, so the
`DeskBank-` prefix is how `DeskStore` finds them. `DeskBank-fixture-*.json` are
copies of `tests/fixtures/desk/` for development; the importer refuses them
because no archive holds their bank.

- `Models/DeskModels.swift` is Foundation only: bank decoding (unknown schema,
  stack or mode, a duplicate task and a proposal in a blind bank reject the
  file), `DeskRules` (a mirror of `domain/desk.py:validate_payload`) and
  `DeskLedger` (the event chain and the `monad-defense/desk/1` export).
- `Models/DeskRecords.swift` holds `DeskSession` and the append-only
  `DeskDecisionEvent`. They are separate from `TriageDecision` and are never
  pruned when a bank leaves the bundle.
- `Store/DeskStore.swift` is the only writer. Every decision is saved
  explicitly before the card advances; a failed save rolls back.

Each task's events form one linear chain: a new event supersedes the task's
current terminal event, and undo is a `retract` event that keeps the retracted
action with an empty payload. The importer therefore never sees two unlinked
terminals, which would block the task. `sequence` is session-wide and
`decided_at` is stored as a string and re-emitted verbatim, so a re-export is a
no-op at import. Only a locked session exports; locking is final. A receipt
(`monad-knowledge/desk-receipt/1`) attaches to its session through the file
importer; without one, application status is unknown.

## Thesis guide

`ThesisGuide.json` is read by `ThesisGuide.loadBundled()` (`Models/GuideModels.swift`)
and is optional: if it is missing or from a newer compiler, the Thesis tab says
so and the rest of the app is unaffected. `Views/Guide/` holds the module list,
the lesson pager and `StepView`; `GuideText.swift` renders step prose, flattening
inline `$…$` maths through the same `MathParser` into one wrapping `Text`.

Each widget id has one view in `Views/Guide/Widgets/`, dispatched by
`GuideWidgetView`. Their numbers come from `Models/GuideMath.swift`, a port of
the decks' `models.js`; both reproduce the companion notebook's pinned values
(posterior means 4.46 / 7.76 / 15.15, widths of Fig. 6.3, horizons 3385 / 124 /
7.48 h). The read position lives in `Store/GuideReadState.swift`, in
`UserDefaults`, never in SwiftData.

## Debug router

`Views/DebugRouter.swift` reads launch arguments and opens a chosen card, a
chosen reader or a chosen card's figures straight from launch. It exists so
`design/screenshots.sh` is reproducible rather than the result of tapping in
the right order. `-DemoGuideStep <step-id>` opens the Thesis tab at one guide
step, and `-DemoWidgetOnly` with it shows only that step's widget.

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
