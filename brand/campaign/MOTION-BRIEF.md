# Claude Motion brief: Takes promo (v2, for 0.6.0)

How to make the Takes promo in Claude Motion. Section 1 is what you do; section 2 is the brief to paste into Motion; section 3 lists the files to attach. It replaces v1, which predated the 0.6.0 redesign and pointed at feature images that have since been removed.

Three cuts come from one Motion project:

| Cut | Length | Format | Use |
|---|---|---|---|
| **A. Promo** | 40 s | 16:9 1920 × 1080, plus 1:1 and 9:16 | Site hero, launch posts (Show HN, Product Hunt), X, LinkedIn |
| **B. English coach** | 15 s | 9:16 and 1:1 | Social: one advanced feature, for people writing in a second language |
| **C. README loop** | 10 s, silent, seamless | 16:9 1280 × 720, MP4 + GIF under 10 MB | Top of the README |

---

## 1. Steps

1. **Record the real flows** (section 4). Motion can't run the app; every UI moment in the promo must be a real recording, never invented UI. About 15 minutes.
2. **Open Claude Motion** in the other account and start a new project.
3. **Attach the kit**: the recordings from step 1, plus the `takes-promo-kit/` folder (real screens from `Takes --snapshot`, the hero video, the marble end-card clip, the logo files, `BRAND.md`).
4. **Paste section 2** as the first message. Ask for **Cut A first**, as a draft at the clips' resolution.
5. **Review against the checklist** (section 5), give notes, then ask for Cuts B and C from the same project.
6. **Upscale** once the edit works: re-render the Higgsfield clips at 1080p (section 6) and swap them in.

---

## 2. Brief (paste into Motion)

> **Product.** Takes, a free, open-source Mac menu-bar app. In any text box, press Control + Option + Space. Takes shows a few ways to say your draft side by side: shorter, warmer or more formal. Pick one and it's pasted back where you were typing. It also proofreads, and an optional English coach spots the English mistakes you repeat and turns them into short lessons from your own sentences. It uses your own Claude or ChatGPT plan, an API key, or a model on your Mac.
>
> **The idea in one line.** "One draft. A few takes. Your choice."
>
> **Look.** Continue the attached hero video's world exactly: a cream desk device with a cobalt dial, a mode readout and a yellow Return key, printing paper cards onto a warm paper tabletop (#F3EBDD) in late-afternoon window light, with a long soft diagonal shadow. Tactile, calm, a little playful. Palette: Ink #171714, Paper #F3EBDD, Acid #E8F449, Cobalt #3045FF, Tomato #F0543D. Two inks plus the background per shot. Tomato means "corrected", Cobalt means "chosen", Acid means "recognised".
>
> **Real UI.** Every app moment is one of the attached screen recordings or real screenshots, shown as a Mac window floating over the same paper surface with a soft shadow. Never draw, invent or alter UI. You may crop, zoom slowly into a region, or lift one element (a take card, a fix chip) toward the camera as a 2.5D layer cut from the real frame.
>
> **Type.** Headlines in Barlow Condensed Bold (DIN Condensed Bold if available), uppercase, Ink on Paper or Acid on Cobalt. Small labels in JetBrains Mono Medium, uppercase, letter-spaced, like the app's TAKE 1 / TAKE 2 labels. Short lines, set big, with lots of air. At most one line of copy on screen at a time.
>
> **Motion.** Physical and unhurried: objects settle with one short, soft overshoot, never a bouncy spring. Cards slide out of the slot and land with a small paper shadow. Cuts land on the dial's clicks and the Return key. UI windows rise 8–12 px into place and fade in over about 250 ms; nothing whooshes.
>
> **Sound (Cut A and B).** Dry, close foley: the dial's detent clicks, a soft printer whirr, paper landing, the Return key's thock, quiet keyboard typing for the draft. A light, warm, minimal beat underneath, ending on the Return key. No voice-over.
>
> **Voice of the copy.** Direct, reassuring, lightly playful. Explain a real action ("Pick a take", "Paste it back"), never promise perfect writing. Use only the lines below, word for word.
>
> ### Cut A: promo, 40 s
>
> | # | Time | Shot | On screen |
> |---|---|---|---|
> | 1 | 0:00–0:03 | Hero device on the desk with one draft card, "Please review the deck by 3." Slow push-in. (Hero video) | `DOES THIS SOUND RUDE?` |
> | 2 | 0:03–0:07 | A hand rolls the mode readout to SOFt and turns the dial to 3, a click per number. (Hero video) | label `MODE · TAKES` |
> | 3 | 0:07–0:10 | Return pressed; three cards print and fan out. (Hero video) | `ONE DRAFT. A FEW TAKES.` |
> | 4 | 0:10–0:14 | Match-cut from the card fan to recording R1: a rough draft in a message box, the keycaps ⌃ ⌥ Space appear as physical cream keys in the lower third as they're pressed, the Takes panel opens. | label `CONTROL + OPTION + SPACE` |
> | 5 | 0:14–0:19 | R1 continues: three takes stream in side by side. Slow zoom toward take 2; hold ⌥ shows the word changes. | label `TAKE 1 · TAKE 2 · TAKE 3` |
> | 6 | 0:19–0:22 | R1 ends: Return, the panel closes, the take lands in the message box. | `YOUR CHOICE.` |
> | 7 | 0:22–0:29 | English coach (R3, or screens 08 → 09 → 11): the draft with its slips; the three fix chips lift out of the frame one by one toward the camera, struck words in Tomato, fixes in Ink ("If you will send → If you send", "until tomorrow → by tomorrow", "make you a feedback → give you feedback"); then the coach overview. | label `ENGLISH COACH`, then `LEARN FROM YOUR OWN SENTENCES.` |
> | 8 | 0:29–0:34 | Quick montage, about 1 s each, each a real screen with one element lifted: proofread (12), presets (14), tone (13), a model on your Mac (16), dictation (15). | one mono label per shot: `PROOFREAD` `PRESETS` `TONE` `ON YOUR MAC` `DICTATION` |
> | 9 | 0:34–0:37 | The menu-bar popover "Takes lives up here" (02) over the paper desk, pointing up. | `ANY APP. ONE SHORTCUT.` |
> | 10 | 0:37–0:40 | End card: the marble logo clip (`clips/end-card-marble-loop-*.mp4`), the line set below it. | `WRITE IT ROUGH. PICK YOUR TAKE.` then `FREE FOR MAC` |
>
> ### Cut B: English coach, 15 s (9:16 first)
>
> | # | Time | Shot | On screen |
> |---|---|---|---|
> | 1 | 0:00–0:03 | A paper card on the desk with the draft "If you will send me the file until tomorrow, I will make you a feedback." Tomato underlines draw under the three slips. | `WRITING IN YOUR SECOND LANGUAGE?` |
> | 2 | 0:03–0:07 | Screen 08: "Your takes fixed 3 English slips." The three chips lift toward the camera. | — |
> | 3 | 0:07–0:11 | Screen 09, then the lesson (11): the reason line ("A future condition takes the present after if") set big. | `IT NOTICES WHAT YOU REPEAT.` |
> | 4 | 0:11–0:15 | The overview (10), then the end card. | `OFF UNTIL YOU TURN IT ON.` then `TAKES · FREE FOR MAC` |
>
> ### Cut C: README loop, 10 s (silent, seamless)
>
> R2 only: draft in a message box → ⌃ ⌥ Space keycaps → three takes stream in → arrow to take 2 → Return → pasted → cross-dissolve to the start. No copy apart from the keycap overlay.
>
> ### Don'ts
>
> - No invented or redrawn UI, no fake Mac windows, no stock people, no faces. Hands only from the hero video.
> - No claims beyond the facts. Takes has no account and no analytics, and sends your draft only to the model you picked. Don't say "AI that writes for you"; it's "a few ways to say it". Don't say "free forever"; say "free" or "free and open source".
> - No third-party logos as hero elements (Slack, Anthropic, OpenAI, Apple). A real message box in a recording is fine.
> - The English coach is optional and off by default; never show it as always on.

---

## 3. Attach (the `takes-promo-kit/` folder)

| File | What it's for |
|---|---|
| `recordings/R1-basic-flow.mov` | Shots A4–A6 (you record it, section 4) |
| `recordings/R2-loop.mov` | Cut C |
| `recordings/R3-coach.mov` (optional) | Shot A7 and Cut B, live instead of stills |
| `brand/hero-master.mp4` | The world, shots A1–A3 |
| `clips/end-card-marble-loop-480p.mp4` | End card (Higgsfield draft, 480p; loops on its first frame) |
| `brand/social-preview.jpg` | End card still, also the fallback if the clip doesn't work |
| `brand/logo.svg`, `logo-inverted.svg`, `t-mark.svg` | Wordmark and mark |
| `brand/BRAND.md` | Colours, type, voice |
| `screens/01…17-*.png` | Real screens rendered by `Takes --snapshot` with sample data (2x). Use for the montage and as fallbacks for any recording |

Screens in the kit:

| # | Screen | # | Screen |
|---|---|---|---|
| 01 | First-run opening | 10 | Coach overview (what you repeat, 30 days) |
| 02 | "Takes lives up here" menu-bar popover | 11 | Coach lesson from your own sentences |
| 03 | Compose (draft and presets) | 12 | Proofread, fixes marked |
| 04 | Takes streaming in | 13 | Tone notes on each take |
| 05 | Three takes | 14 | Presets |
| 06 | Changes view (⌥ held) | 15 | Dictation |
| 07 | "Pasted" toast (write and paste right away) | 16 | Model menu, a model on this Mac |
| 08 | English coach invitation ("Your takes fixed 3 English slips") | 17 | Menu-bar menu |
| 09 | Coach notes under the takes | | |

Regenerate the screens any time with `build/Takes.app/Contents/MacOS/Takes --snapshot <folder>` (see `docs/development.md`).

---

## 4. Recordings to make first

Set up once:
- A neutral wallpaper (a flat warm beige is ideal), the Dock hidden, Do Not Disturb on, and the menu bar showing only Takes, battery and the clock.
- Display at a scaled resolution near 1440 × 900, so the panel is large in frame. Record with ⌘⇧5, "Record Selected Portion", at 2x.
- The engine you record with should be fast (Sonnet or GPT, "Low" effort) so the takes stream in under 4 seconds.
- A message box to type into. A plain TextEdit window works; so does Slack or Messages (it's fine if the app is visible, just not as a hero logo).

| Recording | Steps | Length |
|---|---|---|
| **R1 basic flow** | Type the draft `please review the deck by 3` into the message box. Wait a beat. Press ⌃ ⌥ Space. Let three takes stream in with the "Slack message" preset. Press → once, hold ⌥ for two seconds, release. Press Return. Hold on the pasted text for two seconds. | ~15 s |
| **R2 loop** | Same as R1, but frame the message box and the panel tighter (1280 × 720 region), and keep the cursor still at the end so it can loop. | ~10 s |
| **R3 coach** (optional) | With the coach off, type `If you will send me the file until tomorrow, I will check it and make you a feedback.` Press ⌃ ⌥ Space and wait for the invitation under the takes; hover each chip. Then press "Turn on coach", run it again and open the coach notes (⌘;). | ~20 s |

---

## 5. Review checklist

- [ ] Every app moment is a real recording or a kit screen; no UI was redrawn or retouched.
- [ ] Text on screen matches section 2 word for word; no spelling changes to drafts or takes.
- [ ] At most one line of copy at a time; headlines uppercase Barlow/DIN, labels JetBrains Mono.
- [ ] Two inks plus the background per shot; Tomato only for corrections, Cobalt only for "chosen".
- [ ] The coach is shown as something you turn on.
- [ ] The 9:16 and 1:1 versions keep the UI readable (crop to the takes, not the whole panel).
- [ ] Cut C loops without a visible jump and is under 10 MB as a GIF.

---

## 6. Higgsfield clips (organic shots)

Made in advance as 480p drafts (MiniMax H3 Max, 5 s, start and end on the same frame so each loops). Re-render at 768p (MiniMax) or 1080p (Seedance 2.5, `omni_reference`, about 80 credits per 5 s) once the edit is approved.

| Clip | Status | Start/end frame | Prompt |
|---|---|---|---|
| End card | **Done, 480p** (`clips/end-card-marble-loop-480p.mp4`) | `brand/social/social-preview.jpg` at 16:9 | Locked-off camera with a very slow, gentle push-in. The glossy marbled resin speech-bubble logo lies still on the sunlit paper desk. Inside the slab, the cobalt, tomato and cream marble bands flow slowly like a lava lamp, while the cream raised letters stay perfectly still and unchanged. Soft highlights glide across the clear coat as the warm window light shifts slightly. No new objects, no text changes, no hands. Ends on the same framing as it starts. |
| Coach card | To make (7.5 credits at 480p) | A still of a paper card on the hero desk with the draft line typed on it (generate with GPT Image 2.5 from `brand/hero/key-0.jpg`) | A tomato-red pencil line slowly underlines "If you will send", then "until tomorrow", then "make you a feedback", one after another, as if by an invisible hand. The paper and the typed words stay perfectly still and unchanged. Warm window light, soft shadow. |
| Keycaps | To make (7.5 credits at 480p) | Three chunky cream keycaps (⌃, ⌥ and a cobalt Space bar) on the paper desk (crop from the carousel's shortcut scene) | The three keys press down one after another and spring back with a soft, short travel, as if typed by an invisible finger; a faint shadow shifts under each. Nothing else moves. |
| Cards fan | Optional | `brand/hero/key-4.jpg` | The three printed take cards slide a few millimetres apart on the desk and settle, the middle one lifting slightly as if chosen. Locked-off camera. |

Check every word in a generated clip by eye; generators misspell. If a clip changes any text, cut it.
