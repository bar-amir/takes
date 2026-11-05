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

`t-swirl.mp4` is an endless loop for the t mark: the bubble filled with a cobalt, tomato and cream lava-lamp swirl that keeps flowing and trading colours, never resting on the flat mark. `t-swirl-frame.png` is its start and end image (the mark from `t-greenscreen.png` with the swirl painted in, so the loop closes on itself); the flat frame `t-greenscreen.png` is kept for other clips. `./key.sh t-swirl.mp4 ../../site/img/logo/tmark 00FF00` keys it untrimmed. `.mark-loop` in `site/index.html` plays it on a loop as soon as it scrolls near, with no hover, unless motion is reduced; the clip box is 214% of the mark (the mark is 46.7% of the frame).
