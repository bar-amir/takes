# Campaign visuals: creative direction

Status: draft v1 (November 2026). Companion to `brand/BRAND.md`, the short version of the brand book.

## The idea

**The interface, abstracted into layers.** Every feature is shown as the real Takes UI, simplified to what matters (a draft, three takes, a chip, a fix) and pulled apart into thick, soft tiles floating in depth, seen from a near-front angle on a transparent background. Shortcut labels, secondary buttons and counters are left out: it's an abstraction of the app, not a screenshot.

The materials come from the hero video's world: cream, matte, slightly tactile plastic and paper, with warm light and soft contact shadows. That keeps the stills, the hero and the site one family.

Three layers of production:

| Asset | Made with | Where |
|---|---|---|
| Live hero of the product section | WebGL (`site/js/layers.js`, scene `takes`). Point at a take and it comes to the front; arrow keys do the same. | Site, "Choice is the product" |
| Composition frames | The same engine, exported on transparent backgrounds (`site/layers.html?scene=…&export=1`) | `brand/campaign/frames/*.png` |
| Final stills | Higgsfield, from the frame (layout) plus a material reference (look), as in `HIGGSFIELD-KIT.md` | `site/img/layers/*.webp`, the README grid and the site |

Earlier explorations, kept for reference: the desk-object concepts (`desk-concepts-sheet.jpg`) and the first 3D UI renders (`material-refs-sheet.jpg`), which were too literal (every button and shortcut) but set the material target.

Reference points (Mobbin): Cycle's feature grid uses one chunky 3D object per feature (a yellow search key, ⌘ K keycaps). Arc and Craft put product crops in coloured frames. Takes goes between the two: real UI, made into objects.

## Visual language

- **Set.** One continuous Paper tabletop (`#F3EBDD`). A single warm window light from the upper right, a long soft diagonal shadow across the top of the frame, shallow depth of field.
- **Objects.** Cream, slightly textured plastic (the device body), knurled steel, cobalt caps, a yellow Return key, Paper cards with typed Arial-like text. Accents only from the palette: Cobalt for "chosen", Tomato for "corrected", Acid for "recognised".
- **Composition.** One hero object, off-centre, with lots of empty Paper (a third or more of the frame), so the image can sit beside text or under a caption. Three-quarter top-down angle, the same as the hero.
- **Tone.** Cute but grown-up: small, tidy, a bit toy-like, never cartoonish. No people (the hand belongs to the hero video only), no screens, no logos besides the t on the dial.
- **Words in images.** Only short, real-sounding draft lines on cards ("Thursday it is."). Never feature names or marketing copy inside the picture: that lives in HTML, where it's accessible and translatable.

## Scenes per feature

| Feature | Scene | File |
|---|---|---|
| Takes (compare, choose) | The panel: draft strip, three takes, one lifted to the front | `site/img/layers/takes.webp` (live WebGL on the site) |
| Shortcut, draft panel | The draft field and preset chips, with ⌃ ⌥ and a cobalt space bar in front | `compose.webp` |
| Presets | A stack of preset tiles, Slack message pulled out, beside its instruction and Do / Avoid | `presets.webp` |
| Proofread | A take with each fix marked, the three fixes floating beside it | `proofread.webp` |
| English coach | The draft with flagged phrases, the coach tray with its fix chips lifted out | `coach.webp` |
| Local model, privacy | The model menu with a local model picked and an acid "On this Mac" badge | `local.webp` |
| Write and paste right away | A pasted message, a "Pasted" toast, a yellow Return key | `instant.webp` |
| Dictation | A draft being spoken, a cobalt waveform, the Dictating pill | `dictation.webp` |

Still to make: Context and tone (a take with its tone note as a separate tile) and Any language (the same take in three scripts, stacked).

## Formats and sizes

| Placement | Ratio | Export | Notes |
|---|---|---|---|
| Site, `.split` columns | 3:2 | 1500 × 997 WebP, transparent | `class="concept"`, no frame, `loading="lazy"` |
| Site hero | 16:9 | existing `hero.mp4`, `hero.jpg` | unchanged |
| README feature grid | 3:2 | 1500 × 997 WebP, transparent, under 220 KB | two per row in a `<table>`; reads on GitHub light and dark |
| README top | 16:9 GIF/MP4 | 1280 × 720, under 10 MB | the Claude Motion cut (see `MOTION-BRIEF.md`) or a 10 s real-use capture; keep `takes.png` until then |
| Social / OG | 1.91:1 | 1200 × 630 | crop the hero or `takes.jpg`, wordmark top-left |
| GitHub social preview | 2:1 | 1280 × 640 | the hero frame `brand/hero/key-4.jpg` with the wordmark |
| App Store–style stills (later) | 16:10 | 2880 × 1800 | concept left, real screenshot right |

## Production notes

- Frames: run `python3 -m http.server` in `site/`, open `layers.html?scene=<name>` to tune, then export with headless Chrome: `--headless=new --use-angle=swiftshader --enable-unsafe-swiftshader --window-size=1500,1000 --default-background-color=00000000 --screenshot=brand/campaign/frames/<name>.png "http://localhost:8000/layers.html?scene=<name>&export=1&w=1500&h=1000"`.
- Stills: see `HIGGSFIELD-KIT.md`. Check every word by eye after generating.
- `BRAND.md` says to explain the interface with real screenshots, not mockups. These scenes are deliberately abstract and use the app's real wording. Keep real `Takes --snapshot` screenshots for docs and release notes.
