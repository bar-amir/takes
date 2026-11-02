# Start frame = d.png with e1's dial cap turned back two clicks (1 at the tick).
# End frame = e1.png untouched. Prints the measured step angle.
import cv2, numpy as np, math

d = cv2.imread('gen/d.png'); e = cv2.imread('gen/e1.png')
H, W = d.shape[:2]
CX, CY, A, B, PHI = 1799.2, 475.2, 186.3, 147.9, math.radians(-2.7)

ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
dx, dy = xs - CX, ys - CY
cp, sp = math.cos(PHI), math.sin(PHI)
U = (dx * cp + dy * sp) / A
V = (-dx * sp + dy * cp) / B
R = np.sqrt(U * U + V * V)
cap = np.clip((0.955 - R) / 0.025, 0, 1)

# numerals: light blobs on the blue cap, away from the centre logo
hsv = cv2.cvtColor(e, cv2.COLOR_BGR2HSV)
white = ((hsv[..., 1] < 80) & (hsv[..., 2] > 170) & (R < 0.93) & (R > 0.55)).astype(np.uint8)
n, lab, st, cen = cv2.connectedComponentsWithStats(white)
angs = []
for k in range(1, n):
    if st[k, cv2.CC_STAT_AREA] < 25: continue
    x, y = cen[k]
    u = ((x - CX) * cp + (y - CY) * sp) / A; v = (-(x - CX) * sp + (y - CY) * cp) / B
    angs.append((math.degrees(math.atan2(v, u)), st[k, cv2.CC_STAT_AREA]))
angs.sort()
print("numerals (deg, area):", [(round(a, 1), int(s)) for a, s in angs])
step = (angs[-1][0] - angs[0][0]) / 4
print("step:", round(step, 2), "tick at:", round(np.mean([a for a, _ in angs]), 1))

def rotated(src, deg):
    t = math.radians(deg)
    us = U * math.cos(t) - V * math.sin(t); vs = U * math.sin(t) + V * math.cos(t)
    mx = (us * A * cp - vs * B * sp + CX).astype(np.float32)
    my = (us * A * sp + vs * B * cp + CY).astype(np.float32)
    return cv2.remap(src, mx, my, cv2.INTER_CUBIC).astype(np.float32)

blur = lambda x: cv2.GaussianBlur(x, (0, 0), 10)
rc = rotated(e, 2 * step)                       # counter-clockwise two clicks
vd = cv2.cvtColor(d, cv2.COLOR_BGR2HSV)[..., 2].astype(np.float32)
vr = cv2.cvtColor(rc.astype(np.uint8), cv2.COLOR_BGR2HSV)[..., 2].astype(np.float32)
shade = np.clip((blur(vd * cap) + 1) / (blur(vr * cap) + 1), 0.3, 1.3)[..., None]
m = cap[..., None]
start = np.clip(d * (1 - m) + rc * shade * m, 0, 255).astype(np.uint8)
cv2.imwrite('gen/s2.png', start)
cv2.imwrite('insp/s2-crop.png', np.hstack([start[250:720, 1500:2150], e[250:720, 1500:2150]]))
open('gen/step.txt', 'w').write(str(step))
