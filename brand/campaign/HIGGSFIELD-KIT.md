# Higgsfield kit: layered UI stills

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
