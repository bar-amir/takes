# Takes brand

The short version of the brand book (Product Identity, October 2026). The book itself is kept outside the repo.

## The marks

| File | Use |
|---|---|
| `logo.svg` | Full wordmark in Ink. The letters are cut out, so they take the background colour. |
| `logo-cobalt.svg`, `logo-tomato.svg` | The same wordmark for the Signal (Cobalt on Acid) and Print (Tomato on Paper) editions. |
| `logo-inverted.svg` | Paper bubble on an Ink field, for dark backgrounds. |
| `t-mark.svg` | The compact t: the bubble whose light t flows into the tail. Monochrome, the t is a transparent counter. Panel header (when the target app has no icon), small app roles. Paths: `t-paths.json` (bubble, t). |
| `t-mark-small.svg` | The same t with a heavier bubble rim, for 16–32 px: menu bar, `site/favicon.svg` and `site/favicon.ico`. The t keeps its exact shape. |
| `foil-texture.jpg` | Holographic foil (generated), masked into the t for the Night edition. |
| App icon, disk icon | The Night edition: Paper die-cut rim, Ink bubble, foil t. `scripts/render-foil.swift` draws them; `scripts/make-app-icon.sh` builds `Resources/AppIcon.icns`, `Resources/dmg/` (disk icon and install window) and the site's favicon fallbacks. |
| `social/social-preview.jpg` | 1280×640 share image (generated with Higgsfield GPT Image 2.5 from `logo-anim/logo-greenscreen.png`, `logo-anim/t-swirl-frame.png` and `site/img/hero-og.jpg`): the wordmark as a marbled cobalt, tomato and cream slab on the sunlit paper desk. GitHub's social preview and the site's `og:image` (`site/img/social.jpg`). |

- **Expressive outside, quiet inside.** The wordmark carries the brand on the web, in campaigns and on stickers. The app itself uses system type, Ink accents and native light and dark surfaces; preset and semantic colours keep their meaning.
- Use the full wordmark only where the letters have room: **96 px wide minimum** on screen (192 px at 2x), **25 mm** in print. Below that, use the compact symbol. Never force the wordmark into 16–32 px.
- Clear space: at least **10% of the artwork's width** on every side. The wordmark's aspect ratio is 1.513 : 1, measured including the tail.
- Keep the continuous upper-right curve and the tail from the s.

## Colour

| Name | Hex | Role |
|---|---|---|
| Ink | `#171714` | Primary text, the everyday mark |
| Paper | `#F3EBDD` | Warm background |
| Acid | `#E8F449` | Recognition |
| Cobalt | `#3045FF` | Campaign field |
| Tomato | `#F0543D` | Print edition |

Use two ink colours plus the background in each piece. Longer reading text stays in Ink on Paper or Cobalt on Acid (and Acid on Cobalt); Tomato on Paper is for large marks only.

## Type

- **DIN Condensed Bold**, uppercase, for campaign headlines. Short, clear lines that give the logo an orderly partner.
- **Arial** Regular and Bold for reading text and for drafts and takes, which should read like messages, not advertising.
- **JetBrains Mono** (Medium and Bold, SIL OFL 1.1), sparingly, for labels: TAKE 1/2/3, keycaps, small cues. The site and the app both use it; the app bundles it in `Resources/Fonts`.

## Voice

Direct, reassuring and lightly playful. Explain a real action: "Try a warmer take" and "Paste your choice" beat promises of perfect writing.

Lines from the book: "A few ways to say it." · "Write it rough. Pick your take." · "One draft. A few takes. Your choice." · "Your Mac. Your Claude. Your choice." · "Draft. Preset. Choose. Paste."

When explaining the interface, use real screenshots (`Takes --snapshot`), not mockups.
