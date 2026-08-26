# DeckBank.json — the content contract

`MonadDefense/Resources/DeckBank.json` is the whole of the app's content. The
app decodes it once at launch and never writes to it.

The file is **generated**. It is compiled from Obsidian deck notes by
`monad-knowledge edu deck compile` in the parent repo, and editing it by hand
is always the wrong move — the next compile overwrites the edit. This document
exists so the format is readable from this side of the boundary, and so a
change on either side can be checked against a written contract.

Authoring workflow: [CONTENT.md](CONTENT.md).
Decoder: `MonadDefense/Models/ContentModels.swift`.

## Versioning

```json
{
  "schema_version": 1,
  "bank_version": "65485b8af517",
  "generated_at": "2026-08-24T15:08:50+00:00",
  "decks": [ … ],
  "cards": [ … ]
}
```

| field | meaning |
|---|---|
| `schema_version` | the format below. The app refuses to launch on a value it does not know. |
| `bank_version` | content digest. Identifies which bank a curation export was made against. |
| `generated_at` | ISO 8601 compile time. Drives the staleness notice. |

`DeckBank.supportedSchemaVersion` in the app is the other half of
`schema_version`. Raising one without raising the other is a launch-time
`fatalError`, which is deliberate: a silently mis-decoded bank is worse than a
refusal.

Keys are `snake_case` in the file and decoded with
`.convertFromSnakeCase`. Nothing in the app spells them out.

## Deck

```json
{
  "slug": "core-abbreviations",
  "title": "Fundamentals · Abbreviations",
  "track": "core",
  "difficulty": "basics",
  "defense": false,
  "deck_version": 2,
  "tags": ["edu-deck", "core", "vocabulary"],
  "card_count": 49,
  "intro": "…"
}
```

`track` is a closed set — `core`, `WS501`, `LOC502`, `CRD503`, `PRB504`,
`FM505`, `SIM507`, `thesis`, `chapters`. Declaration order in the Swift enum is
reading order: vocabulary, then the courses that vocabulary lets you read, then
the thesis, then the document chapter by chapter. A new track needs a case in
`Track`, with its tint and its SF Symbol.

`difficulty` is `basics` | `core` | `advanced`, and it is `Comparable` — deck
lists sort by it.

`intro` is present in the file and currently unread by the app. It is the
deck's own framing, kept in the bank so a future deck screen can show it
without a recompile.

## Card

Fields common to all three kinds:

| field | type | notes |
|---|---|---|
| `id` | string | **stable, forever.** Progress is keyed on it. Changing an id discards that card's review history. |
| `kind` | `flash` \| `mcq` \| `formula` | |
| `deck` | string | a deck `slug` |
| `track`, `difficulty` | enum | as above |
| `defense` | bool | `true` puts the card in the Committee Room pool |
| `anchors` | [string] | **validated** knowledge-base ids — argument-chain links `<chapter>.<slug>` and hypothesis slugs. An unresolvable anchor fails `edu deck validate`. |
| `sources` | [string] | free-form provenance. Never validated. |
| `tags` | [string] | |
| `title` | string? | the `###` heading above the card — a short name where the prompt is a whole question |
| `see_also` | [string]? | card ids. **Symmetric by construction** — the compiler writes the reverse link too. |
| `figures` | [Figure]? | any kind of card may carry any kind of figure |

Per-kind fields:

| kind | fields |
|---|---|
| `flash` | `front`, `back`, `why` |
| `mcq` | `question`, `choices`, `correct` (0-based index), `explanation` |
| `formula` | `question`, `latex`, `reading`, `fields` (`symbol` + `meaning` rows), `explanation` |

MCQ distractors are **intentionally false near-miss claims**. Several encode
documented mis-citation traps — a number attributed to the wrong paper, a
formula credited to authors who never derived it. They are preserved as
sparring partners, so the wrong option has to be *tempting* to do its job.

### The LaTeX quoting trap

Write `latex:` in a **single-quoted** YAML scalar in the deck note. A
double-quoted scalar processes backslash escapes, so `"\mathrm{Var}"` reaches
the compiler as a parse error rather than a formula.

## Figures

One list, discriminated by `kind`. An unrecognised `kind` decodes to
`unsupported` rather than failing the bank, so an older app degrades on a newer
bank instead of refusing to launch.

### `plot`

```json
{
  "kind": "plot",
  "caption": "…",
  "x_label": "subcarrier index",
  "y_label": "phase (radians)",
  "frames": [ { "value": 0.02, "curves": [ { "label": "…", "dashed": false,
                "points": [[1.0, 20.0], [1.07, 18.59], …] } ] } ],
  "markers": [ { "axis": "x", "value": 3.2, "label": "crossover" } ],
  "parameter": {
    "label": "oscillator mismatch",
    "unit": null,
    "values": [0.0, 0.02, 0.06, 0.12],
    "scenarios": ["matched crystals", "a few ppm apart",
                  "typical commodity pair", "a bad pair"]
  }
}
```

Curves are declared as **expressions in the deck note and sampled at compile
time**. `points` are the samples. The app therefore draws points and carries no
expression evaluator, and a curve undefined anywhere on its declared domain
fails the compile rather than rendering a hole.

`parameter` makes the plot interactive. The compiler samples one frame per
value and the app scrubs between them with a slider, or animates them on
demand. Interactivity costs the phone nothing, and the slider can only land on
a state the author chose to show. Where `scenarios` is given, each frame's
caption is its scenario name instead of its number.

A plot without a parameter has exactly one frame, which keeps the drawing path
uniform.

`markers` draw reference lines. `axis: "x"` is vertical.

### `diagram`

```json
{
  "kind": "diagram",
  "caption": "…",
  "aspect": 1.9,
  "nodes": [ { "id": "ap1", "label": "AP", "x": 0.3, "y": 0.2,
               "w": 0.16, "h": 0.1, "shape": "rounded", "emphasis": false } ],
  "edges": [ { "source": "sta1", "target": "ap1", "label": null,
               "dashed": false, "arrow": "both" } ]
}
```

Positions are in the unit square with the origin at **top-left**. `shape` is
`box` | `rounded` | `ellipse` | `note` | `lane`; `arrow` is `none` | `end` |
`both`. Drawn with native shapes — no raster and no vector parser — so it
scales with the reader's type size and is correct in dark mode by construction.

### `image`

```json
{ "kind": "image", "asset": "csi-waterfall-walk-monad05.png",
  "caption": "…", "alt": "…" }
```

`asset` is a filename inside the bundled `Figures/` directory. This kind exists
for the one case a drawn figure cannot serve: showing what real measured data
actually looks like. `alt` is a full prose description, not a label.

### `table`

```json
{ "kind": "table", "caption": "…",
  "columns": ["Sub-band", "Channels", "DFS?", "For a capture"],
  "rows": [["U-NII-1", "36–48", "No", "Safe for long unattended runs"]],
  "emphasis": [0] }
```

`emphasis` is a list of row indices to highlight. Cell text may carry `**bold**`.
Up to three columns the figure lays out as a grid; beyond that each row becomes
a stacked block. It never scrolls sideways.

### `sequence`

```json
{ "kind": "sequence", "caption": "…",
  "actors": ["Initiator", "Responder"],
  "messages": [ { "source": "Initiator", "target": "Responder",
                  "label": "FTM request", "dashed": true,
                  "self_message": false } ] }
```

Positions are computed from message order, so the picture is of **time** rather
than of position: a protocol exchange cannot come out crooked, and a reordered
one needs no re-authoring.

## Adding a figure kind

Both sides move, in this order:

1. The compiler in the parent repo learns to emit it, and `edu deck validate`
   learns to reject a malformed one.
2. A `case` in `Figure` here, with its payload struct in `ContentModels.swift`.
3. A branch in `Views/FigureView.swift` and one new file under
   `Views/Widgets/`.
4. Bump `schema_version` on both sides only if an **existing** kind changed
   shape. A purely additive kind needs no bump — older apps render it as
   `unsupported`, which is the designed behaviour.

## Curation export

The reverse direction. `monad-defense/curation/1`, emitted by the Curate tab
and read by `monad-knowledge edu deck curation`:

```json
{
  "schema": "monad-defense/curation/1",
  "bank_version": "65485b8af517",
  "exported_at": "2026-08-26T12:00:00Z",
  "cards_total": 433,
  "cards_curated": 87,
  "notes": [ { "card_id": "abbr-0011", "verdict": "fix", "note": "…",
               "deck": "core-abbreviations", "track": "core",
               "prompt": "…", "updated": "2026-08-26T11:58:00Z" } ]
}
```

`verdict` is `keep` | `more` | `fix` | `cut`. The `bank_version` is carried so a
stale export is detectable, rather than being applied to cards that have since
changed.
