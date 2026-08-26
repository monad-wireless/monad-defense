# Content workflow

The app ships its content and never authors it. Cards are written as Obsidian
notes in the parent repo and compiled into this one.

```
obsidian/monad-knowledge/edu/decks/*.md        ← where cards are written
        │
        │  monad-knowledge edu deck compile
        ▼
MonadDefense/Resources/DeckBank.json           ← what the app reads
MonadDefense/Resources/Figures/*.png
        │
        │  Xcode build
        ▼
   the app on the phone
        │
        │  Curate tab → export JSON
        ▼
monad-knowledge edu deck curation <export>     ← a worklist over the deck notes
        │
        └──────────────────► back to the deck notes
```

Both halves of that loop live in the parent repo. This repo holds the app and
the compiled output.

The format itself: [DECK-BANK.md](DECK-BANK.md).

## Refresh the bank

From the parent repo root:

```bash
uv run monad-knowledge edu deck spine --apply   # re-render the RQ deck
uv run monad-knowledge edu deck validate        # anchors and figures must resolve
uv run monad-knowledge edu deck compile         # → DeckBank.json + Figures/
```

Then rebuild the app in Xcode.

Run the three in that order. `spine` writes a deck note, so validating before
it has run validates the previous one.

`compile` writes to `repos/monad-defense/MonadDefense/Resources/DeckBank.json`
by default, and rebuilds `Figures/` from the declared set on every run — an
image dropped from a deck note therefore stops shipping rather than lingering
in the app bundle.

`compile` **refuses to write an empty bank**. The commonest cause of one is a
wrong vault path, and the failure is otherwise silent: the app would ship with
no content, and every review already done would be orphan-pruned at the next
launch.

### The other read-side commands

| command | what it answers |
|---|---|
| `edu deck list` | which decks exist, with their track, level and card count |
| `edu deck coverage` | which thesis claims the bank drills, and which it leaves undrilled |
| `edu deck spine --check` | has a research question drifted from `thesis/Foundation.md`? Writes nothing. |
| `edu deck booklet` | the A5 reading-edition PDF of the same corpus |

`coverage` is **advisory**. A claim may legitimately have no card, so an
uncovered claim is a finding rather than a failure. An unresolvable *anchor*,
by contrast, fails `validate` outright, with a nearest-match suggestion.

## Two rules that cost real work when broken

**A card id is a promise.** Progress is keyed on the id and nothing else. Change
an id in a deck note and that card's whole review history is discarded at the
next launch, even if its text never moved. Rewrite the text freely; leave the
id alone.

**The research-question deck is generated, not written.** `edu deck spine`
renders it from `thesis/Foundation.md`, which is the same declaration
`write spine` renders into the thesis's `spine.tex`. A rehearsed question
therefore cannot drift from the asked one. Editing that deck note by hand is
undone by the next `spine --apply`.

## The curation loop

The **Curate** tab sweeps the whole bank with the answers open — one verdict per
card (`keep` / `more` / `fix` / `cut`) plus a free-text note. It is also
reachable from any session's toolbar. Nothing is graded and nothing moves in the
FSRS queue: curating is editorial work, not study.

Export as JSON, Markdown or clipboard, then map the verdicts back to the deck
notes that own each card:

```bash
uv run monad-knowledge edu deck curation ~/Downloads/defense-curation-<date>.json
uv run monad-knowledge edu deck curation <file> --verdict cut,fix --out worklist.md
```

Edit the deck notes, recompile, rebuild.

The export carries the `bank_version` its verdicts were made against, so a stale
export is detectable rather than silently applied to cards that have since
changed.

Verdicts live on the device in SwiftData and survive a content refresh, like
review progress. Clearing them is explicit, from the Curate tab.

## Staleness

The refresh is deliberately **not** an Xcode build phase. The build stays fast,
offline, and independent of the parent repo and its Python environment.

The cost is that a stale bank is invisible. So the app states its content's age:
`StalenessNotice` prints one quiet line on the Today screen once the bank passes
fourteen days old. It is never a modal — a stale bank is still a usable bank.
