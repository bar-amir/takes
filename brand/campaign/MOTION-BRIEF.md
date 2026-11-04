# Claude Motion brief: Takes promo

Paste everything under "Brief" into Claude Motion, and attach the assets listed at the end. There are two cuts from one project: a 30-second promo (site, social, launch posts) and a 10-second silent loop (README top, replacing `site/img/takes.png`).

---

## Brief

**Product.** Takes, a free, open-source Mac menu-bar app. In any text field, press Control + Option + Space. Takes rewrites your draft a few ways, side by side. Pick one and it's pasted back where you were typing.

**Look.** Continue the attached hero video exactly: a cream desk device with a cobalt dial, a mode readout and a yellow Return key, printing paper cards on a warm Paper tabletop (#F3EBDD) in late-afternoon window light, with a long soft diagonal shadow. Tactile, calm, a little playful. Palette: Ink #171714, Paper #F3EBDD, Acid #E8F449, Cobalt #3045FF, Tomato #F0543D. Two inks plus the background per shot.

**Type.** Headlines in DIN Condensed Bold (Barlow Condensed as a fallback), uppercase, Ink on Paper or Acid on Cobalt. Small labels in a monospace (Courier New / JetBrains Mono), uppercase, letter-spaced. Short lines, set big, with lots of air. Never more than one line of copy on screen at once.

**Motion.** Physical and unhurried: objects settle with a short, soft overshoot (spring, no bounce-bounce), cards slide out of the slot and land with a tiny paper shadow. Cuts land on the dial's clicks. Real UI segments are framed as a Mac window floating over the same Paper surface, with a soft shadow; never fake UI.

**Sound (30 s cut only).** Dry, close foley: the dial's detent clicks, a soft printer whirr, paper landing, the Return key's thock. A light, warm, minimal beat underneath, ending on the Return key.

### 30-second cut (16:9, 1920 × 1080, also export 1:1 and 9:16)

| # | Time | Shot | On screen |
|---|---|---|---|
| 1 | 0:00–0:03 | Open on the hero device, a single draft card on the desk: "Please review the deck by 3." Slow push-in. | `DOES THIS SOUND RUDE?` |
| 2 | 0:03–0:07 | A hand rolls the mode readout from SHRT to SOFt, turns the dial 1 → 2 → 3 (a click per number). Reuse the hero footage. | label: `MODE · TAKES` |
| 3 | 0:07–0:10 | Return pressed; three cards print and fan out on the table. | `ONE DRAFT. A FEW TAKES.` |
| 4 | 0:10–0:16 | Match-cut from the card fan to the real Takes panel (screen recording) over the same Paper desk: three takes streaming in, "Changes" toggled on take 2, take 1 selected. | label: `CONTROL + OPTION + SPACE` |
| 5 | 0:16–0:19 | Paste: the panel closes, and the chosen take lands in a Slack field (screen recording). | `YOUR CHOICE.` |
| 6 | 0:19–0:25 | Feature montage, about 1 s each: the layered-UI stills on the Paper surface, each with its front layer rising toward the camera (separate the layers for a 2.5D parallax): presets, proofread, English coach, on your Mac, dictation, instant paste. | one mono label per still: `PRESETS` `PROOFREAD` `ENGLISH COACH` `ON YOUR MAC` `DICTATION` `TONE` |
| 7 | 0:25–0:30 | Pull back to the device with the three cards; cut to Cobalt field, Acid wordmark (logo-inverted animation if available), then the line. | `WRITE IT ROUGH. PICK YOUR TAKE.` then `FREE FOR MAC · TAKES` |

### 10-second README loop (16:9, 1280 × 720, silent, seamless loop, MP4 + GIF under 10 MB)

| Time | Shot |
|---|---|
| 0:00–0:02 | A rough draft in a Slack field (screen recording), cursor blinking. Keycaps overlay: ⌃ ⌥ Space. |
| 0:02–0:06 | The Takes panel opens; three takes stream in side by side. |
| 0:06–0:08 | Arrow to take 2, "Changes" on, then Return. |
| 0:08–0:10 | The take is pasted into the Slack field. Hold, then cross-dissolve back to the start. |

No copy apart from the keycap overlay. Real recordings only.

### Don'ts

- No invented UI, no fake Mac windows with made-up controls, no stock people.
- No claims beyond the facts: Takes doesn't send anything itself, has no account, and has no analytics. Don't say "AI that writes for you"; it's "a few ways to say it".
- No third-party logos (Slack, Anthropic, OpenAI) as hero elements; a real Slack window in a screen recording is fine.

---

## Assets to supply

| Asset | Where |
|---|---|
| Hero video (style and the hand/dial footage) | `brand/hero/hero-master.mp4` (13 MB), keyframes `brand/hero/key-0…4.jpg` |
| Feature stills | `site/img/layers/*.webp`: transparent, textured layered UI per feature (2K PNG masters can be re-rendered per `HIGGSFIELD-KIT.md`) |
| Layered UI, live | `site/layers.html?scene=takes`: record the hover moment (a take rising to the front) as a screen capture for shot 4 |
| Wordmark, mark | `brand/logo.svg`, `brand/logo-inverted.svg`, `brand/t-mark.svg` |
| Logo animations | `brand/logo-anim/*.mp4` (green-screened; `chatter.mp4` or `zipper.mp4` suit the end card) |
| Brand summary | `brand/BRAND.md` |
| Screen recordings (record these first) | 1) Slack draft → ⌃⌥Space → 3 takes stream in → Changes on take 2 → Return → pasted. 2) Same at 1280 × 720 for the loop. Record at 2x on a clean desktop with a neutral wallpaper, Dock hidden, menu bar showing only the Takes icon and the clock. Use `Takes --snapshot` stills as fallback frames. |
| Fonts | DIN Condensed Bold (system on macOS), Barlow Condensed 700 and JetBrains Mono 500 (Google Fonts) |
