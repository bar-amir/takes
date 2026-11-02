# Composite a rigid, detented dial and a clean display over a Kling take.
# usage: comp.py in.mp4 out.mp4
import cv2, numpy as np, subprocess, sys, math

SRC, OUT = sys.argv[1], sys.argv[2]
FPS = 24
CX, CY, A, B, PHI = 1279.6, 337.3, 131.5, 104.8, math.radians(-3.25)
SWITCH = 1.79                     # display cuts SHrt -> SOFt
STEPS = [(3.30, 40.0), (4.15, 65.5)]  # (start time, target angle) for each detent
SNAP = 0.17                       # seconds per snap

def ease_back(x, s=1.4):
    x -= 1
    return x * x * ((s + 1) * x + s) + 1

def angle(t):
    a = 0.0
    for t0, target in STEPS:
        if t >= t0 + SNAP: a = target
        elif t > t0: a = a + (target - a) * ease_back((t - t0) / SNAP)
    return a

cap = cv2.VideoCapture(SRC)
frames = []
while True:
    ok, f = cap.read()
    if not ok: break
    frames.append(f)
H, W = frames[0].shape[:2]
ref, last = frames[0].astype(np.float32), frames[-1].astype(np.float32)

ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
dx, dy = xs - CX, ys - CY
cp, sp = math.cos(PHI), math.sin(PHI)
U = (dx * cp + dy * sp) / A          # unit-circle coords of each pixel
V = (-dx * sp + dy * cp) / B
R = np.sqrt(U * U + V * V)
cap_mask = np.clip((0.955 - R) / 0.025, 0, 1)

def rotated_cap(deg):
    t = math.radians(deg)
    us = U * math.cos(t) - V * math.sin(t)
    vs = U * math.sin(t) + V * math.cos(t)
    mx = (us * A * cp - vs * B * sp + CX).astype(np.float32)
    my = (us * A * sp + vs * B * cp + CY).astype(np.float32)
    return cv2.remap(frames[0], mx, my, cv2.INTER_CUBIC).astype(np.float32)

def blur(x): return cv2.GaussianBlur(x, (0, 0), 10)

# display: the dark glass quad (union of first and last frame), inset slightly
def glass(f):
    hsv = cv2.cvtColor(f, cv2.COLOR_BGR2HSV)
    m = ((hsv[..., 2] < 60) | ((hsv[..., 1] > 120) & (hsv[..., 2] > 120))).astype(np.uint8)
    box = np.zeros_like(m); box[328:426, 1480:1648] = 1
    m = cv2.morphologyEx(m * box, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    return (lab == 1 + np.argmax(st[1:, cv2.CC_STAT_AREA])).astype(np.uint8)
g = cv2.erode(glass(frames[0]) | glass(frames[-1]), np.ones((3, 3), np.uint8))
disp_mask = cv2.GaussianBlur(g.astype(np.float32), (0, 0), 1.2)

def occluder(f, kind):
    hsv = cv2.cvtColor(f, cv2.COLOR_BGR2HSV)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    if kind == "cap":
        # anything not blue, minus small isolated blobs (the printed numerals)
        nb = (~((h > 95) & (h < 135) & (s > 30))).astype(np.uint8) * (cap_mask > 0).astype(np.uint8)
        n, lab, st, _ = cv2.connectedComponentsWithStats(nb)
        big = np.zeros(n, bool); big[1:] = st[1:, cv2.CC_STAT_AREA] > 260
        occ = big[lab].astype(np.uint8)
    else:
        # soft: dark glass -> 0, anything lighter (hand, blur) -> 1; amber digits don't count
        amber = cv2.dilate(((h > 8) & (h < 35) & (s > 150) & (v > 120)).astype(np.uint8), np.ones((3, 3), np.uint8))
        a = np.clip((v.astype(np.float32) - 40) / 45, 0, 1) * (1 - amber)
        a = cv2.dilate(a, np.ones((5, 5), np.uint8))
        return cv2.GaussianBlur(a, (0, 0), 1.5)
    occ = cv2.morphologyEx(occ, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    occ = cv2.morphologyEx(occ, cv2.MORPH_CLOSE, np.ones((11, 11), np.uint8))
    occ = cv2.dilate(occ, np.ones((3, 3), np.uint8))
    return cv2.GaussianBlur(occ.astype(np.float32), (0, 0), 1.5)

enc = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24",
    "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-crf", "12",
    "-pix_fmt", "yuv420p", OUT], stdin=subprocess.PIPE)

cache = {}
for i, f in enumerate(frames):
    t = i / FPS
    out = f.astype(np.float32)
    # dial
    a = round(angle(t), 2)
    if a not in cache: cache[a] = rotated_cap(a)
    rc = cache[a]
    vc = cv2.cvtColor(f, cv2.COLOR_BGR2HSV)[..., 2].astype(np.float32)
    vr = cv2.cvtColor(rc.astype(np.uint8), cv2.COLOR_BGR2HSV)[..., 2].astype(np.float32)
    shade = np.clip((blur(vc * cap_mask) + 1) / (blur(vr * cap_mask) + 1), 0.3, 1.3)[..., None]
    m = (cap_mask * (1 - occluder(f, "cap")))[..., None]
    out = out * (1 - m) + rc * shade * m
    # display
    src = ref if t < SWITCH else last
    m = (disp_mask * (1 - occluder(f, "disp")))[..., None]
    out = out * (1 - m) + src * m
    enc.stdin.write(np.clip(out, 0, 255).astype(np.uint8).tobytes())
enc.stdin.close(); enc.wait()
print("frames", len(frames))
