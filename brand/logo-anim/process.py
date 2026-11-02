# process.py <name> <url> : download a green-screen master, report key colour, edge clearance and still head/tail, key it trimmed, write a contact strip.
import sys, subprocess, urllib.request, numpy as np, os, json
name, url = sys.argv[1], sys.argv[2]
raw = f'raw/{name}.mp4'
if not os.path.exists(raw): urllib.request.urlretrieve(url, raw)
w, h = map(int, subprocess.run(['ffprobe','-v','error','-select_streams','v','-show_entries','stream=width,height','-of','csv=p=0',raw],capture_output=True,text=True).stdout.strip().split(','))
b = subprocess.run(['ffmpeg','-loglevel','error','-i',raw,'-f','rawvideo','-pix_fmt','rgb24','-'],capture_output=True).stdout
fr = np.frombuffer(b,np.uint8).reshape(-1,h,w,3).astype(int)
bg = np.median(np.concatenate([fr[:, :20, :20].reshape(-1,3), fr[:, -20:, -20:].reshape(-1,3)]), 0).astype(int)
fg = np.abs(fr-bg).sum(-1) >= 120
ys, xs = np.where(fg.any(0))
clear = min(xs.min(), ys.min(), w-1-xs.max(), h-1-ys.max())
g = fr[:, ::6, ::6].mean(-1)
d0 = np.abs(g-g[0]).mean((1,2)); dn = np.abs(g-g[-1]).mean((1,2))
fps = 24
s = max(0, int(np.argmax(d0 > 1.0)) - 2); e = len(g) - int(np.argmax(dn[::-1] > 1.0)) + 2
ss, to = s/fps, min(e, len(g))/fps
hexk = '%02X%02X%02X' % tuple(bg)
print(f'{name}: {w}x{h} key #{hexk} edge clearance {clear}px  keep {ss:.2f}s-{to:.2f}s of {len(g)/fps:.2f}s')
subprocess.run(['./key.sh', raw, f'keyed/{name}', hexk], env={**os.environ, 'SS': f'{ss:.2f}', 'TO': f'{to:.2f}'}, check=True)
subprocess.run(['ffmpeg','-y','-loglevel','error','-i',raw,'-vf','fps=1.6,scale=240:240,tile=8x1','-frames:v','1',f'strips/{name}.png'])
