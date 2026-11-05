# Logo hover animations: green-screen masters

Nine Higgsfield clips (Seedance 2.5, 5 s, 960×960, no audio) for the masthead logo on the site. Each uses `logo-greenscreen.png` (the wordmark at half the frame's width, letters in Paper) as both its start and end image, so it opens and closes on the static logo. The screen is pure green because none of the brand colours is near it; the prompts limit every clip to Ink, Paper, Acid, Cobalt and Tomato.

| Clip | What happens |
| --- | --- |
| `melt` | The letters melt into Tomato and Acid goo and slurp back |
| `chatter` | The bubble talks: a Tomato tongue, Acid bolts, Cobalt spirals |
| `kaleido` | A Cobalt, Acid and Tomato mandala with cream daisies |
| `bubblegum` | The letters inflate and cycle Acid, Tomato, Cobalt |
| `spiral` | The bubble twists into a hypnotic target and untwists |
| `zipper` | The bubble unzips onto a Cobalt night sky with a Tomato planet |
| `split` | The bubble divides into three arguing bubbles (three takes) and merges back |
| `shuffle` | The letters pop off as cards, shuffle themselves, fan out and flip to Tomato, Cobalt and Acid backs |
| `tv` | The bubble becomes a retro TV flipping channels |

`process.py <name> <url>` downloads a master, measures the screen colour and the still frames at each end, and calls `key.sh`, which writes the transparent files in `site/img/logo/` (VP9-alpha WebM for Chrome and Firefox, HEVC-alpha MOV for Safari), trimmed so a hover always meets a moving clip.

On the site the clip box is a square twice the logo's width, centred on it (`.logo-anim` in `site/index.html`). Each hover plays the next clip in turn.

## The mark at the end of the page

`t-lava.mp4` is the same recipe for the t mark (`t-greenscreen.png`, the mark at half the frame's width in Ink): a cobalt and tomato lava-lamp swirl with cream dots drifting inside the bubble, back to the flat mark at both ends. `./key.sh t-lava.mp4 ../../site/img/logo/tmark 00FF00` keys it untrimmed, so the loop rests on the still mark for a moment between passes. `.mark-loop` in `site/index.html` plays it on a loop as soon as it scrolls near, with no hover, unless motion is reduced; the clip box is 214% of the mark (the mark is 46.7% of the frame).
