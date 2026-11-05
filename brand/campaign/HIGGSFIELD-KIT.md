# Higgsfield kit: layered UI renders

Status: v1 rendered November 2026 (GPT Image 2.5, high quality, 2K, transparent), encoded to WebP at 1500 px.

Each still is generated from **two references**:

1. **Layout**: the WebGL frame `brand/campaign/frames/<scene>.png`, rendered by `site/js/layers.js`. It fixes the composition: the near-front angle, the simplified UI (no shortcut labels, no secondary buttons), which layer floats in front, and the real text.
2. **Material**: the matching render in `brand/campaign/material-refs/`. It fixes the look: thick, soft, matte cream plastic with bevelled edges, a slight paper grain, warm side light and soft contact shadows, the world of `brand/hero/`.

Model: GPT Image 2.5 (`gpt_image_2_5`), `quality: high`, `resolution: 2k`, `aspect_ratio: 3:2`, `background: transparent`.

## Shared prompt

> Re-render the FIRST reference image with the materials, lighting and finish of the SECOND reference image. Keep the first image's exact composition, camera angle, layer order, depths and all of its text, word for word. Every tile is thick, soft, matte cream plastic with rounded bevelled edges and a faint paper grain. Warm soft light from the upper left, gentle contact shadows between layers. Transparent background: no table, no floor, only the floating UI and its shadows. Do not add any buttons, labels, keyboard shortcuts or text that are not in the first image. Premium, calm, a little playful.

## Per scene

| Scene | Layout ref | Material ref | Add to the shared prompt |
|---|---|---|---|
| takes | `frames/takes.png` | `00-takes.jpg` | "Take 2 floats clearly in front of the others with a bold black outline." |
| compose | `compose.png` | `01-compose.jpg` | "The space bar is glossy cobalt blue (#3045FF)." |
| presets | `presets.png` | `02-presets.jpg` | "The 'Slack message' tile is pulled out of the stack toward the viewer." |
| proofread | `proofread.png` | `03-proofread.jpg` | "Struck words in soft red, fixes in green, as in the first image." |
| coach | `coach.png` | `04-coach.jpg` | "The English coach tray is warm beige; the 'If you send' chip is raised highest." |
| local | `local.png` | `00-takes.jpg` (the bell-jar render adds a dome) | "The 'On this Mac' badge is acid yellow (#E8F449)." |
| instant | `instant.png` | `06-instant.jpg` | "The Return key is a chunky yellow key; the toast is glossy ink black." |
| dictation | `dictation.png` | `07-dictation.jpg` | "The waveform bars are cobalt blue (#3045FF), softly glowing." |

## After generating

- Encode with `cwebp -q 86 -alpha_q 100 -m 6 -resize 1500 0 <render>.png -o site/img/layers/<scene>.webp`. The README and the site point at these files.
- Check every word against the layout frame. Generators misspell; Proofread is the only scene with typos on purpose.
- To change a scene, edit it in `site/js/layers.js`, re-export its frame (`DIRECTION.md` has the command), and re-render with the same prompt.

## Live takes panel: one render per part

The "Choice is the product" scene on the site is built from separate renders of each part, layered in WebGL with
perspective, so the hover keeps the rendered materials. Parts: `base`, `chip`, `draft`, `take1`–`take3`, `ring`
(the selection outline), `paste`.

- Layout: `brand/campaign/frames/parts/<part>.png` (`scripts/export-layers.sh` exports them).
- Material: the textured takes render (`site/img/layers/takes.webp`).
- Prompt: "Render ONLY the single <part> in the FIRST reference image as a physical object, with exactly the material,
  colour and lighting of the matching part in the SECOND reference image … Seen straight on from the front with a very
  slight top-down perspective … Transparent background, no shadow on the ground, nothing else." Aspect: `3:2` for the
  base, `1:1` for takes and the ring, `21:9` for the chip, the draft strip and the paste button.
- Post: `scripts/frame-render.sh part <render.png> site/img/layers/parts/<part>.webp`. The scene draws its own soft
  shadows, stretches the blank base to its tile, and sizes the ring to the takes.
- The page's still (`site/img/layers/takes-front.webp`) is the same scene exported once:
  `layers.html?scene=takes&sprites=img/layers/parts&export=1&w=1500&h=1000`.

### Tone pills: marbled, and (later) flowing

Each take's tone note (`tone1`–`tone3`) is a marbled pill in the About logo's material, each in its own colours:
cobalt, tomato and cream; tomato, acid and cream; cobalt, acid and cream. Raised cream lettering, no dot.

- Layout: `layers.html?scene=takes&part=tone1&export=1&w=1200&h=1200` (the drawn ink pill, for proportions and text).
- Material: `Resources/About/logo-still.png`.
- Prompt: "Render ONLY the single pill-shaped tag in the FIRST reference image as a physical object, in exactly the
  material and finish of the SECOND reference image (the marbled logo slab): a thick, glossy, slightly domed slab of
  marbled resin, the marbling made of flowing swirls of <colours> like a lava lamp … Its text "<tone>" is raised cream
  glossy lettering embossed on the marble … No dot … The background is a perfectly flat, uniform pure green (#00FF00)
  chroma key …" GPT Image 2.6, `quality: high`, `resolution: 2k`, `aspect_ratio: 21:9`, `background: opaque` (a green
  screen rather than transparency, so the same still can start and end a loop clip).
- Post: key the green (`ffmpeg -i <render>.png -vf "chromakey=0x<key>:0.14:0.05,despill=type=green:mix=0.7,format=rgba"`,
  reading the key colour from a corner), then `scripts/frame-render.sh part <keyed>.png site/img/layers/parts/tone<n>.webp`.
- Loop clips (not yet made): Seedance 2.5, `omni_reference`, the still as both `start_image` and `end_image`, 5 s, 21:9,
  720p, no audio, prompt: the pill and its letters stay perfectly still, only the marbling flows like a lava lamp,
  flat green background, last frame equals first. Scale the master to the render's width, apply the still's crop
  (the `crop=` that `frame-render.sh` detects on the keyed still), and save it as `site/img/layers/parts/tone<n>.mp4`
  (H.264, yuv420p, about 700 px wide, no alpha: the page keys the green in a shader and cuts to the still's edge).
  Then add `data-clips` to the `.layers` element in `site/index.html`; without it the page never asks for the clips.

## Features carousel: one render per piece

Each carousel slide is a live WebGL scene like the takes panel: every piece (a key, a chip, a card, a tile) is its own
transparent render, placed in depth and casting a soft shadow on the pieces below, with the camera following the
cursor a little. The pieces themselves stay still. Pieces per scene are the names given to `place()` in `site/js/layers.js`:

| Scene | Pieces |
|---|---|
| shortcut | field, key-control, key-option, key-space, chip (reuses the takes chip) |
| presets | chip1 (Polish email, selected: Ink with an Acid dot), chip2–chip5 (greyed), instruction, do, avoid |
| proofread | card, fix1–fix3 |
| coach | draft, tray, fix1–fix3 |
| local | panel (the Engine card, Ink with the found line in Acid), menu, badge |
| instant | field, toast, return |
| dictation | card, pill, wave |
| tone | reply, take, note |
| languages | de, es, en |

- Layout: `brand/campaign/frames/pieces/<scene>/<piece>.png` (`scripts/export-layers.sh`).
- Material: that scene's earlier wide render (the angled carousel stills in `slides-sheet.jpg`), so the pieces keep
  the same finish.
- Settings: `quality: medium`, `resolution: 2k`, transparent; medium was enough for every piece's text.
- Prompt: "Render ONLY the single piece in the FIRST reference image as a physical object, with the material, colour
  and lighting of the matching piece in the SECOND reference image … Seen straight on with a very slight top-down
  perspective. Keep all text word for word … Transparent background, no ground shadow, nothing else."
- Post: `scripts/frame-render.sh part <render.png> site/img/slides/parts/<scene>/<piece>.webp`.
- Stills: `STILLS="<scenes>" scripts/export-layers.sh` exports each live scene once (1200 × 1000, the stage's aspect),
  saved as `site/img/slides/stills/<scene>.webp` (1200 × 1035: the stage is 13% taller than the card at each end, so pieces
  can float past the card's edges). The page shows it until the live scene loads, so the swap is seamless;
  if the renders fail to load, the still stays and the canvas is removed.
- Card surfaces: `site/img/slides/bg/1–9.webp` are crops of the hero tabletop (`brand/hero/key-*.jpg`), flipped, tinted
  and blended half into the card colour, one per slide, with a CSS gradient for the hero's diagonal light.
- The page keeps a WebGL context only for slides on screen; the others are freed and fall back to their still.
