# Logo hover animations: green-screen masters

Five Higgsfield clips (Seedance 2.5, 5 s, 960×960, no audio) for the masthead logo on the site. Each uses `logo-greenscreen.png` (the wordmark at half the frame's width, letters in Paper) as both its start and end image, so it opens and closes on the static logo. The screen is pure green because none of the brand colours is near it; the prompts limit every clip to Ink, Paper, Acid, Cobalt and Tomato.

| Clip | What happens |
| --- | --- |
| `melt` | The letters melt into Tomato and Acid goo and slurp back |
| `chatter` | The bubble talks: a Tomato tongue, Acid bolts, Cobalt spirals |
| `kaleido` | A Cobalt, Acid and Tomato mandala with cream daisies |
| `bubblegum` | The letters inflate and cycle Acid, Tomato, Cobalt |
| `spiral` | The bubble twists into a hypnotic target and untwists |

`process.py <name> <url>` downloads a master, measures the screen colour and the still frames at each end, and calls `key.sh`, which writes the transparent files in `site/img/logo/` (VP9-alpha WebM for Chrome and Firefox, HEVC-alpha MOV for Safari), trimmed so a hover always meets a moving clip.

On the site the clip box is a square twice the logo's width, centred on it (`.logo-anim` in `site/index.html`). Each hover plays the next clip in turn.
