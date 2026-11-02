# Keyframes for the hero video, all from one cap (the reference end frame's), with the rim
# index lines removed and the numerals aligned to the body tick.
#   k0  SHrt, dial on 1, one draft card        (start)
#   k1  SOFt, dial on 1
#   k2  SOFt, dial on 2
#   k3  SOFt, dial on 3
#   k4  SOFt, dial on 3, three cards            (end)
import cv2, numpy as np, math

d = cv2.imread('gen/d.png'); e = cv2.imread('gen/e1.png')
H, W = d.shape[:2]
CX, CY, A, B, PHI = 1799.2, 475.2, 186.3, 147.9, math.radians(-2.7)
import os; TICK = float(os.environ["TICK"])
NUM = {1: 153.8, 2: 126.9, 3: 98.9}          # numeral angles on the reference cap

ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
dx, dy = xs - CX, ys - CY
cp, sp = math.cos(PHI), math.sin(PHI)
U = (dx * cp + dy * sp) / A
V = (-dx * sp + dy * cp) / B
R = np.sqrt(U * U + V * V)
ANG = np.degrees(np.arctan2(V, U))
cap = np.clip((0.955 - R) / 0.025, 0, 1)

def rotated(src, deg):
    # +deg turns the content counter-clockwise on screen (content angles decrease by deg)
    t = math.radians(deg)
    us = U * math.cos(t) - V * math.sin(t); vs = U * math.sin(t) + V * math.cos(t)
    mx = (us * A * cp - vs * B * sp + CX).astype(np.float32)
    my = (us * A * sp + vs * B * cp + CY).astype(np.float32)
    return cv2.remap(src, mx, my, cv2.INTER_CUBIC)

def clean_rim(im):
    # the stray white index line sits on the rim at the tick; fill that sector from 20 degrees away
    sector = ((R > 0.9) & (R < 1.13) & (ANG > 84) & (ANG < 112)).astype(np.float32)
    sector = cv2.GaussianBlur(sector, (0, 0), 3)[..., None]
    donor = rotated(im, -20).astype(np.float32)
    return np.clip(im * (1 - sector) + donor * sector, 0, 255).astype(np.uint8)

blur = lambda x: cv2.GaussianBlur(x, (0, 0), 10)
def with_cap(base, src, deg):
    rc = rotated(src, deg)
    vb = cv2.cvtColor(base, cv2.COLOR_BGR2HSV)[..., 2].astype(np.float32)
    vr = cv2.cvtColor(rc, cv2.COLOR_BGR2HSV)[..., 2].astype(np.float32)
    shade = np.clip((blur(vb * cap) + 1) / (blur(vr * cap) + 1), 0.3, 1.3)[..., None]
    m = cap[..., None]
    return np.clip(base * (1 - m) + rc * shade * m, 0, 255).astype(np.uint8)

def glass(f):
    hsv = cv2.cvtColor(f, cv2.COLOR_BGR2HSV)
    m = ((hsv[..., 2] < 60) | ((hsv[..., 1] > 120) & (hsv[..., 2] > 120))).astype(np.uint8)
    box = np.zeros_like(m); box[459:597, 2072:2308] = 1
    m = cv2.morphologyEx(m * box, cv2.MORPH_CLOSE, np.ones((13, 13), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    return (lab == 1 + np.argmax(st[1:, cv2.CC_STAT_AREA])).astype(np.uint8)

d, e = clean_rim(d), clean_rim(e)
g = cv2.erode(glass(d) | glass(e), np.ones((3, 3), np.uint8))
gm = cv2.GaussianBlur(g.astype(np.float32), (0, 0), 1.2)[..., None]
d_soft = np.clip(d * (1 - gm) + e * gm, 0, 255).astype(np.uint8)   # d with the SOFt readout

frames = {
    'k0': with_cap(d,      e, NUM[1] - TICK),
    'k1': with_cap(d_soft, e, NUM[1] - TICK),
    'k2': with_cap(d_soft, e, NUM[2] - TICK),
    'k3': with_cap(d_soft, e, NUM[3] - TICK),
    'k4': with_cap(e,      e, NUM[3] - TICK),
}
for k, f in frames.items(): cv2.imwrite(f'gen/{k}.png', f)
crops = [cv2.resize(frames[k][250:760, 1480:2400], (552, 306)) for k in frames]
cv2.imwrite('insp/keyframes.png', np.vstack([np.hstack(crops[:3]), np.hstack(crops[3:] + [np.full_like(crops[0], 243)])]))
cv2.imwrite('insp/k-tick.png', np.hstack([frames[k][560:700, 1700:1900] for k in frames]))
print({k: round(NUM[int(k[1]) if k[1] in '123' else 3] - TICK, 2) for k in ['k1', 'k2', 'k3']})
