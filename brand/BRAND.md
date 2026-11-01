# Takes brand

The short version of the brand book (Identity & Objects, November 2026). The book itself is kept outside the repo.

## The marks

| File | Use |
|---|---|
| `logo.svg` | Full wordmark in Ink. The letters are cut out, so they take the background colour. |
| `logo-cobalt.svg`, `logo-tomato.svg` | The same wordmark for the Signal (Cobalt on Acid) and Print (Tomato on Paper) editions. |
| `logo-inverted.svg` | Paper bubble on an Ink field, for dark backgrounds. |
| `mark-t.svg` | The compact t: the light t flows into the bubble's tail. Small interfaces, badges, the favicon. Traced from the November 2026 book; swap in the kit's canonical SVG when it lands. |
| `mark.svg` | The earlier compact symbol (bubble with two lines of text), still used by the app icon until it moves to the t. |
| `app-icon.svg`, `app-icon-16.svg` | App icon; the 16 version has one bolder wave. `scripts/make-app-icon.sh` builds `Resources/AppIcon.icns` from them. |

- **Expressive outside, quiet inside.** The wordmark carries the brand on the web, in campaigns and on stickers. The app itself uses system type, Ink accents and native light and dark surfaces; preset and semantic colours keep their meaning.
- Use the full wordmark only where the letters have room: **96 px wide minimum** on screen (192 px at 2x), **25 mm** in print. Below that, use the compact t. Never force the wordmark into 16–32 px.
- Clear space: at least **10% of the artwork's width** on every side. The wordmark's aspect ratio is 1.513 : 1, measured including the tail.
- Keep the continuous upper-right curve and the tail from the s.
- For the t: keep the closed outline, the liquid crossbar and the uninterrupted inner tail. Monochrome in the menu bar; Paper and Ink for the app tile.

## Colour

| Name | Hex | Role |
|---|---|---|
| Ink | `#171714` | Primary text, the everyday mark |
| Paper | `#F3EBDD` | Warm background |
| Acid | `#E8F449` | Recognition |
| Cobalt | `#3045FF` | Campaign field |
| Tomato | `#F0543D` | Print edition |

Ink + Paper carry the identity. Cobalt + Acid add energy. Tomato is a restrained print accent. Use two ink colours plus the background in each piece. Longer reading text stays in Ink on Paper or Cobalt on Acid (and Acid on Cobalt); Tomato on Paper is for large marks only.

## Type

- **DIN Condensed Bold** for headlines: short lines, strong rhythm, generous space. Sentence case by default ("A few ways to say it."); capitals for campaign lines on Cobalt or Acid.
- **Arial** Regular and Bold for reading text and for drafts and takes, which should read like messages, not advertising.
- **JetBrains Mono Medium**, sparingly, for labels, numbers and keyboard cues (replaces Courier New).
- Native product screens keep the system typeface.

## Voice

Direct, reassuring and lightly playful. Explain a real action: "Try a warmer take" and "Paste your choice" beat promises of perfect writing.

Lines from the book: "A few ways to say it." · "Your thought. A few takes." · "A little warmer. Still useful." · "Choice is the product." · "Write what you mean. Choose how it sounds. Paste your take. Keep going." · "Write it rough. Pick your take." · "One draft. A few takes. Your choice." · "Your Mac. Your Claude. Your choice." · "Write. Choose. Paste."

## The device

The cream device with the Cobalt dial (1–5 takes), the seven-segment MODE display (SHrt, SOFt…) and the yellow Return key is a campaign metaphor for the app: one headline, one object, one idea. Paste returns your choice; it never sends it. Motion: set the count, choose the tone, press Return, a new card prints beside the first.

When explaining the interface, use real screenshots (`Takes --snapshot`), not mockups.
