# Campaign visuals: creative direction

Status: draft v1 (November 2026). Companion to `brand/BRAND.md`, the short version of the brand book.

## The idea

**Takes is a small desk object.** The hero video already sets up a world: a cream device with a cobalt dial, a mode readout and a yellow Return key, printing paper cards on a warm Paper tabletop in late-afternoon light. Every campaign image stays in that world. Each feature becomes one tactile object or gesture on the same desk, so a page of features reads as one still-life series, not a collage of UI crops.

This splits the work cleanly between two kinds of visual:

| Job | Visual | Rule |
|---|---|---|
| Explain **how the interface works** | Real screenshot (`Takes --snapshot`) | Per BRAND.md: never a mockup. Keep `site/img/takes.png` as the one product shot. |
| Sell **what a feature means** | Concept still from the desk world | One idea per frame, no fake UI, no screens. |

Reference points (Mobbin): Cycle's feature grid uses one chunky 3D object per feature (a yellow search key, ⌘ K keycaps, a mask for incognito). Superr uses tiny hand-drawn objects per feature. Arc and Craft put product crops in coloured frames. Takes takes the Cycle approach and pushes it further into photography, to match the hero.

## Visual language

- **Set.** One continuous Paper tabletop (`#F3EBDD`). A single warm window light from the upper right, a long soft diagonal shadow across the top of the frame, shallow depth of field.
- **Objects.** Cream, slightly textured plastic (the device body), knurled steel, cobalt caps, a yellow Return key, Paper cards with typed Arial-like text. Accents only from the palette: Cobalt for "chosen", Tomato for "corrected", Acid for "recognised".
- **Composition.** One hero object, off-centre, with lots of empty Paper (a third or more of the frame), so the image can sit beside text or under a caption. Three-quarter top-down angle, the same as the hero.
- **Tone.** Cute but grown-up: small, tidy, a bit toy-like, never cartoonish. No people (the hand belongs to the hero video only), no screens, no logos besides the t on the dial.
- **Words in images.** Only short, real-sounding draft lines on cards ("Thursday it is."). Never feature names or marketing copy inside the picture: that lives in HTML, where it's accessible and translatable.

## Concepts per feature

| Feature | Concept | File |
|---|---|---|
| Takes (compare, choose) | Three cards fanned out of the slot, the chosen one clipped with a cobalt paper clip | `site/img/concepts/takes.jpg` |
| Menu bar + shortcut | Oversized ⌃ ⌥ keycaps and a cobalt space bar, device behind | `shortcut.jpg` |
| Presets | A row of swappable dial caps, each embossed with a preset name | `presets.jpg` |
| Proofread | One card with its typos fixed in Tomato pencil, pencil beside it | `proofread.jpg` |
| English coach | A flashcard box; one card out: "on time / in time", three tally marks, an Acid star | `english-coach.jpg` |
| Local model, privacy | The device under a glass bell jar, no cables | `on-your-mac.jpg` |
| Write and paste right away | Yellow Return pressed, a card already sliding out | `instant.jpg` |
| Dictation | A small cream desk mic with a cobalt grille, a draft card in front | `dictation.jpg` |
| Context and tone | A pinned incoming message, the reply card under it, a little gauge pointing toward WARM | `tone.jpg` |

Still to make: **Any language** (a card with the same line in three scripts, stacked) and **menu-bar discovery** (the device's t mark glowing in a tiny menu-bar strip running along the table's edge) for onboarding and the site's "How it works".

## Formats and sizes

| Placement | Ratio | Export | Notes |
|---|---|---|---|
| Site, `.split` columns | 3:2 | 1440 × 960 JPEG (2x of 720) | `class="concept"`, no shadow or frame, `loading="lazy"` |
| Site hero | 16:9 | existing `hero.mp4`, `hero.jpg` | unchanged |
| README feature grid | 3:2 | 1024 × 683 JPEG, under 120 KB each | two per row in a `<table>`; GitHub caps width at about 880 px |
| README top | 16:9 GIF/MP4 | 1280 × 720, under 10 MB | the Claude Motion cut (see `MOTION-BRIEF.md`) or a 10 s real-use capture; keep `takes.png` until then |
| Social / OG | 1.91:1 | 1200 × 630 | crop the hero or `takes.jpg`, wordmark top-left |
| GitHub social preview | 2:1 | 1280 × 640 | the hero frame `brand/hero/key-4.jpg` with the wordmark |
| App Store–style stills (later) | 16:10 | 2880 × 1800 | concept left, real screenshot right |

## Production notes

- Generated with GPT Image 2.5 on Higgsfield, using `brand/hero/key-2.jpg` as the style reference. Prompts all begin with the same "same world, materials, lighting and camera as the reference photo" preamble, then describe one object.
- The v1 set is drafts at low quality (1024 × 688). Re-render the picks at high quality and 2K before launch (about 2.75 credits each on Higgsfield), and fix text glitches: `proofread.jpg` garbles the correction, and the ⌥ glyph in `shortcut.jpg` is off.
- Check every card's text by eye: generators misspell. Proofread is the one image where typos are on purpose.
