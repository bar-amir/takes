// Layered UI: the Takes interface as an abstraction of thick, soft tiles floating in depth.
// One engine, several scenes. The "takes" scene is interactive on the site (hover or tap a take to bring it
// to the front); every scene can also render once on a transparent background for exporting stills
// (layers.html?scene=coach&export=1). Text is drawn to canvas textures, so it stays crisp at any size.
import * as THREE from "https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js";

const C = { ink: "#171714", paper: "#F3EBDD", card: "#FDFBF7", strip: "#EFEAE1", tray: "#F4ECDF",
  cobalt: "#3045FF", acid: "#E8F449", tomato: "#F0543D", mute: "#8A8478", red: "#B3261E", green: "#1E6B3A",
  redBg: "rgba(240,84,61,.13)", greenBg: "rgba(30,107,58,.11)" };
const FONT = 'Arial, "Helvetica Neue", Helvetica, sans-serif';
const PX = 100;           // drawing units per world unit
const SCALE = 2.6;        // canvas pixels per drawing unit

// ---------- drawing helpers (coordinates in drawing units: 100 per world unit) ----------
function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}
function text(ctx, s, x, y, { size = 22, weight = 400, color = C.ink, align = "left" } = {}) {
  ctx.font = `${weight} ${size}px ${FONT}`; ctx.fillStyle = color; ctx.textAlign = align; ctx.textBaseline = "alphabetic";
  ctx.fillText(s, x, y); return ctx.measureText(s).width;
}
function wrap(ctx, s, x, y, maxW, { size = 22, lead = 1.4, color = C.ink, weight = 400 } = {}) {
  ctx.font = `${weight} ${size}px ${FONT}`; ctx.fillStyle = color; ctx.textAlign = "left";
  let line = "", yy = y;
  for (const word of s.split(" ")) {
    const t = line ? line + " " + word : word;
    if (ctx.measureText(t).width > maxW && line) { ctx.fillText(line, x, yy); line = word; yy += size * lead; } else line = t;
  }
  if (line) ctx.fillText(line, x, yy);
  return yy;
}
// Runs of [text, kind] where kind is "", "del" (struck, red) or "ins" (green), wrapped like a paragraph.
function diff(ctx, runs, x, y, maxW, { size = 22, lead = 1.5 } = {}) {
  ctx.font = `400 ${size}px ${FONT}`; ctx.textBaseline = "alphabetic"; ctx.textAlign = "left";
  let cx = x, cy = y; const space = ctx.measureText(" ").width;
  for (const [s, kind] of runs) for (const word of s.split(" ").filter(Boolean)) {
    const w = ctx.measureText(word).width;
    if (cx + w > x + maxW) { cx = x; cy += size * lead; }
    if (kind) { ctx.fillStyle = kind === "del" ? C.redBg : C.greenBg; ctx.fillRect(cx - 2, cy - size * .82, w + 4, size * 1.08); }
    ctx.fillStyle = kind === "del" ? C.red : kind === "ins" ? C.green : C.ink; ctx.fillText(word, cx, cy);
    if (kind === "del") { ctx.fillRect(cx, cy - size * .3, w, Math.max(1.5, size / 14)); }
    cx += w + space;
  }
}
function underline(ctx, s, x, y, size, color) { // text with a wavy-ish underline, for flagged phrases
  const w = text(ctx, s, x, y, { size }); ctx.fillStyle = color; ctx.fillRect(x, y + 5, w, 2.2); return w;
}
function dot(ctx, x, y, r, color) { ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fillStyle = color; ctx.fill(); }

// ---------- tiles ----------
function shape(w, h, r) {
  const s = new THREE.Shape(), x = -w / 2, y = -h / 2;
  s.moveTo(x + r, y); s.lineTo(x + w - r, y); s.quadraticCurveTo(x + w, y, x + w, y + r); s.lineTo(x + w, y + h - r);
  s.quadraticCurveTo(x + w, y + h, x + w - r, y + h); s.lineTo(x + r, y + h); s.quadraticCurveTo(x, y + h, x, y + h - r);
  s.lineTo(x, y + r); s.quadraticCurveTo(x, y, x + r, y); return s;
}
function faceTexture(renderer, w, h, r, bg, draw, outline) {
  const cw = Math.round(w * PX), ch = Math.round(h * PX);
  const cv = document.createElement("canvas"); cv.width = Math.round(cw * SCALE); cv.height = Math.round(ch * SCALE);
  const ctx = cv.getContext("2d"); ctx.scale(SCALE, SCALE);
  roundRect(ctx, 0, 0, cw, ch, r * PX); ctx.fillStyle = bg; ctx.fill();
  if (outline) { ctx.lineWidth = outline.width; ctx.strokeStyle = outline.color; roundRect(ctx, outline.width / 2, outline.width / 2, cw - outline.width, ch - outline.width, r * PX - outline.width / 2); ctx.stroke(); }
  ctx.save(); roundRect(ctx, 0, 0, cw, ch, r * PX); ctx.clip(); draw && draw(ctx, cw, ch); ctx.restore();
  const t = new THREE.CanvasTexture(cv); t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = renderer.capabilities.getMaxAnisotropy(); return t;
}
// A tile: a bevelled rounded slab with a drawn face. opts: w, h, r, depth, bg, draw, outline, selectedOutline
function tile(renderer, o) {
  const { w, h, r = 0.18, depth = 0.12, bg = C.card } = o, bev = Math.min(0.05, r * 0.5);
  const g = new THREE.Group();
  const geo = new THREE.ExtrudeGeometry(shape(w - bev * 2, h - bev * 2, Math.max(0.01, r - bev)),
    { depth, bevelEnabled: true, bevelThickness: bev, bevelSize: bev, bevelSegments: 5, curveSegments: 28 });
  const body = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ color: new THREE.Color(o.side || bg) }));
  body.castShadow = true; body.receiveShadow = true; g.add(body);
  const maps = [faceTexture(renderer, w, h, r, bg, o.draw, o.outline)];
  if (o.selectedOutline) maps.push(faceTexture(renderer, w, h, r, bg, o.draw, o.selectedOutline));
  const face = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshLambertMaterial({ map: maps[0], transparent: true }));
  face.position.z = depth + bev + 0.003; face.receiveShadow = true; g.add(face);
  g.userData = { maps, face, body, h, w, top: depth + bev };
  return g;
}
const place = (obj, x, y, z) => (obj.position.set(x, y, z), obj);

// ---------- scenes ----------
// Each scene returns { bounds: [w, h], takes?: [tile groups] } after adding tiles to `root`.
const TAKES = [
  ["Take 1", "Thursday works for me. One ask: I need the specs by Wednesday EOD, otherwise QA slips again."],
  ["Take 2", "Sure, Thursday it is. I'll need the specs by Wednesday EOD so QA doesn't slip again."],
  ["Take 3", "Thursday's fine as long as the specs land by Wed EOD."],
];
const label = (ctx, s, x = 26, y = 44) => text(ctx, s, x, y, { size: 20, weight: 700 });
const measure = (s, size, weight = 700) => { const c = measure.c ||= document.createElement("canvas").getContext("2d"); c.font = `${weight} ${size}px ${FONT}`; return c.measureText(s).width / PX; };
const chip = (renderer, s, { dotColor = C.cobalt, bg = C.tray, w } = {}) => tile(renderer, {
  w: w || 0.66 + measure(s, 22), h: 0.52, r: 0.16, depth: 0.08, bg,
  draw: (c, cw, ch) => { dot(c, 24, ch / 2, 7, dotColor); text(c, s, 42, ch / 2 + 8, { size: 22, weight: 700 }); } });
const pill = (renderer, s, { w = 2, h = 0.6, bg = C.ink, color = C.paper, depth = 0.14 } = {}) => tile(renderer, {
  w, h, r: h / 2, depth, bg, draw: (c, cw, ch) => text(c, s, cw / 2, ch / 2 + 8, { size: 23, weight: 700, color, align: "center" }) });

const SCENES = {
  takes(renderer, root) {
    root.add(place(tile(renderer, { w: 10.4, h: 6.6, r: 0.34, depth: 0.16, bg: C.card }), 0, 0, 0));
    root.add(place(chip(renderer, "Slack message"), -3.85, 2.75, 0.55));
    root.add(place(tile(renderer, { w: 9.6, h: 0.9, r: 0.16, depth: 0.08, bg: C.strip,
      draw: (c, cw, ch) => { text(c, "Your draft", 24, 34, { size: 15, weight: 700, color: C.mute });
        text(c, "ya thursday works but i need the specs by wed eod otherwise qa slips again", 24, 66, { size: 21 }); } }), 0, 1.85, 0.55));
    const takes = TAKES.map(([t, body], i) => {
      const card = tile(renderer, { w: 3.0, h: 2.9, r: 0.22, depth: 0.22, bg: C.card,
        outline: { width: 2, color: "#E3DED4" }, selectedOutline: { width: 5, color: C.ink },
        draw: (c) => { label(c, t); wrap(c, body, 26, 92, 248, { size: 22, lead: 1.42 }); } });
      card.userData.home = new THREE.Vector3(-3.15 + i * 3.15, -0.45, 0.95);
      root.add(place(card, ...card.userData.home.toArray())); return card;
    });
    root.add(place(pill(renderer, "Paste take ↵", { w: 2.1 }), 3.95, -2.65, 0.75));
    return { bounds: [10.6, 6.8], takes };
  },
  compose(renderer, root) {
    root.add(place(tile(renderer, { w: 9.4, h: 5.2, r: 0.32, depth: 0.16 }), 0, 0.5, 0));
    root.add(place(tile(renderer, { w: 8.6, h: 1.9, r: 0.18, depth: 0.08, bg: C.card, outline: { width: 2, color: "#E3DED4" },
      draw: (c) => { wrap(c, "ya thursday works but i need the specs by wed eod otherwise qa slips again, also can someone own the release notes this time", 28, 52, 800, { size: 24 }); } }), 0, 1.65, 0.32));
    [["Slack message", C.cobalt, C.tray], ["Proofread", C.green, C.card], ["Shorter", C.tomato, C.card]].reduce((x, [s, d, bg]) => {
      const t = chip(renderer, s, { dotColor: d, bg }); const w = t.userData.w;
      root.add(place(t, x + w / 2, -0.2, s === "Slack message" ? 0.62 : 0.3)); return x + w + 0.2; }, -4.1);
    root.add(place(pill(renderer, "Write 3 takes ↵", { w: 2.5 }), 3.0, -1.35, 0.3));
    const key = (s, w, bg = C.card, color = C.ink) => tile(renderer, { w, h: 1.05, r: 0.2, depth: 0.42, bg,
      draw: (c, cw, ch) => text(c, s, cw / 2, ch / 2 + 14, { size: 40, weight: 400, color, align: "center" }) });
    root.add(place(key("⌃", 1.05), -2.6, -2.75, 1.0));
    root.add(place(key("⌥", 1.05), -1.4, -2.75, 1.0));
    root.add(place(key("", 3.2, C.cobalt), 0.83, -2.75, 1.0));
    return { bounds: [10.6, 8.4] };
  },
  coach(renderer, root) {
    root.add(place(tile(renderer, { w: 10, h: 1.3, r: 0.2, depth: 0.1, bg: C.strip,
      draw: (c) => { text(c, "Your draft", 26, 40, { size: 16, weight: 700, color: C.mute });
        let x = 26; x += underline(c, "If you will send", x, 92, 24, C.tomato); x += text(c, " me the file ", x, 92, { size: 24 });
        x += underline(c, "until tomorrow", x, 92, 24, C.tomato); x += text(c, ", I will check it and ", x, 92, { size: 24 });
        underline(c, "make you a feedback", x, 92, 24, C.tomato); } }), 0, 2.45, 0));
    root.add(place(tile(renderer, { w: 10, h: 3.9, r: 0.3, depth: 0.14, bg: C.tray,
      draw: (c, cw, ch) => { text(c, "English coach", 30, 52, { size: 24, weight: 700 }); text(c, "3 notes on your draft", 210, 52, { size: 21, color: C.mute });
        text(c, "Conditionals", 30, ch - 34, { size: 20, weight: 700 });
        text(c, "A future condition takes the present after “if”.", 170, ch - 34, { size: 20, color: "#4A463F" }); } }), 0, -0.55, 0.3));
    const fix = (a, b, sel) => tile(renderer, { w: 1.0 + measure(a, 22, 400) + measure(b, 22, 700), h: 0.66, r: 0.18, depth: 0.1, bg: C.card,
      outline: sel ? { width: 4, color: C.ink } : { width: 2, color: "#E3DED4" },
      draw: (c, cw, ch) => { const y = ch / 2 + 8; const w1 = text(c, a, 22, y, { size: 22, color: C.red });
        c.fillStyle = C.red; c.fillRect(22, y - 7, w1, 2); text(c, "→", 34 + w1, y, { size: 22, color: C.mute });
        text(c, b, 70 + w1, y, { size: 22, weight: 700, color: C.green }); } });
    root.add(place(fix("If you will send", "If you send", true), -2.15, 0.05, 1.25));
    root.add(place(fix("until tomorrow", "by tomorrow"), 2.55, 0.05, 0.75));
    root.add(place(fix("make you a feedback", "give you feedback"), -1.05, -0.95, 0.75));
    return { bounds: [10.4, 6.6] };
  },
  proofread(renderer, root) {
    root.add(place(tile(renderer, { w: 7.4, h: 4.2, r: 0.3, depth: 0.16, outline: { width: 2, color: "#E3DED4" },
      draw: (c, cw, ch) => { label(c, "Proofread", 34, 56);
        diff(c, [["Thanks for the", ""], ["quick", ""], ["reveiw", "del"], ["review!", "ins"], ["I'll send the", ""], ["final", ""], ["deck", ""],
          ["tommorow", "del"], ["tomorrow", "ins"], ["once", ""], ["its", "del"], ["it's", "ins"], ["approved.", ""]], 34, 120, cw - 70, { size: 30, lead: 1.6 });
        text(c, "3 fixes", 34, ch - 34, { size: 21, color: C.mute }); } }), -0.9, 0, 0));
    const f = (a, b) => tile(renderer, { w: 1.0 + measure(a, 22, 400) + measure(b, 22, 700), h: 0.62, r: 0.18, depth: 0.1, bg: C.card,
      outline: { width: 2, color: "#E3DED4" }, draw: (c, cw, ch) => { const y = ch / 2 + 8; const w1 = text(c, a, 20, y, { size: 22, color: C.red });
        c.fillStyle = C.red; c.fillRect(20, y - 7, w1, 2); text(c, "→", 32 + w1, y, { size: 22, color: C.mute }); text(c, b, 66 + w1, y, { size: 22, weight: 700, color: C.green }); } });
    root.add(place(f("reveiw", "review"), 4.0, 1.75, 1.1));
    root.add(place(f("tommorow", "tomorrow"), 4.4, 0.85, 0.75));
    root.add(place(f("its", "it's"), 4.1, 0.0, 0.45));
    return { bounds: [11.8, 5.2] };
  },
  presets(renderer, root) {
    root.add(place(tile(renderer, { w: 5.6, h: 4.8, r: 0.3, depth: 0.14,
      draw: (c, cw) => { text(c, "Instruction", 30, 52, { size: 17, weight: 700, color: C.mute });
        wrap(c, "Clear and friendly. Short lines, no corporate filler.", 30, 90, cw - 60, { size: 23 });
        text(c, "Do", 30, 196, { size: 17, weight: 700, color: C.green });
        text(c, "Lead with the ask", 30, 230, { size: 22 }); text(c, "Keep my emoji", 30, 266, { size: 22 });
        text(c, "Avoid", 30, 330, { size: 17, weight: 700, color: C.red });
        text(c, "“Just circling back”", 30, 364, { size: 22 }); text(c, "Exclamation marks", 30, 400, { size: 22 }); } }), 2.0, 0, 0));
    [["Slack message", C.cobalt], ["Polish email", C.ink], ["Proofread", C.green], ["Shorter", C.tomato], ["Friendlier", C.acid]].forEach(([s, d], i) => {
      const sel = i === 0; const t = chip(renderer, s, { dotColor: d, bg: sel ? C.tray : C.card, w: 2.7 });
      root.add(place(t, -3.3 + (sel ? 0.3 : 0), 1.6 - i * 0.78, sel ? 1.15 : 0.35 + i * 0.02));
    });
    return { bounds: [10.6, 5.8] };
  },
  local(renderer, root) {
    root.add(place(tile(renderer, { w: 8.8, h: 4.6, r: 0.3, depth: 0.16,
      draw: (c) => { text(c, "Model", 34, 56, { size: 18, weight: 700, color: C.mute }); } }), 0, 0, 0));
    root.add(place(tile(renderer, { w: 5.2, h: 2.9, r: 0.24, depth: 0.1, outline: { width: 2, color: "#E3DED4" },
      draw: (c, cw) => { const row = (y, a, b, on) => { if (on) { c.fillStyle = C.tray; roundRect(c, 12, y - 40, cw - 24, 60, 12); c.fill(); }
          text(c, a, 36, y, { size: 24, weight: on ? 700 : 400 }); text(c, b, cw - 70, y, { size: 20, color: C.mute, align: "right" });
          if (on) text(c, "✓", cw - 40, y, { size: 24, weight: 700, color: C.cobalt, align: "center" }); };
        row(66, "llama3.2", "Ollama", true); row(146, "qwen3:8b", "Ollama"); row(226, "gemma-3-12b", "LM Studio"); } }), -0.9, -0.35, 0.55));
    const badge = tile(renderer, { w: 2.5, h: 0.78, r: 0.39, depth: 0.14, bg: C.acid,
      draw: (c, cw, ch) => text(c, "On this Mac", cw / 2, ch / 2 + 8, { size: 23, weight: 700, align: "center" }) });
    root.add(place(badge, 2.75, 1.25, 1.2));
    return { bounds: [9.4, 5.4] };
  },
  instant(renderer, root) {
    root.add(place(tile(renderer, { w: 9.6, h: 2.2, r: 0.3, depth: 0.14, outline: { width: 2, color: "#E3DED4" },
      draw: (c, cw, ch) => { text(c, "Message #launch", 30, 48, { size: 17, weight: 700, color: C.mute });
        wrap(c, "Running about 5 minutes late, sorry! Start without me and I'll catch up.", 30, 100, cw - 60, { size: 26 }); } }), 0, -0.6, 0));
    const toast = tile(renderer, { w: 3.6, h: 0.86, r: 0.43, depth: 0.14, bg: C.ink,
      draw: (c, cw, ch) => { dot(c, 40, ch / 2, 13, C.acid); text(c, "Pasted · ⌘Z to undo", 66, ch / 2 + 8, { size: 23, weight: 700, color: C.paper }); } });
    toast.rotation.z = 0.035; root.add(place(toast, 1.9, 1.25, 1.0));
    const ret = tile(renderer, { w: 1.3, h: 1.3, r: 0.36, depth: 0.36, bg: "#F2D23C",
      draw: (c, cw, ch) => text(c, "↵", cw / 2, ch / 2 + 16, { size: 48, weight: 700, align: "center" }) });
    root.add(place(ret, -3.9, 1.35, 0.7));
    return { bounds: [10, 4.6] };
  },
  dictation(renderer, root) {
    root.add(place(tile(renderer, { w: 8.8, h: 3.6, r: 0.3, depth: 0.16,
      draw: (c, cw) => { wrap(c, "can we push the call to four, the build is still running", 34, 66, cw - 70, { size: 27 });
        c.fillStyle = C.cobalt; c.fillRect(34 + 0, 140, 3, 34); } }), 0, 0, 0));
    root.add(place(pill(renderer, "● Dictating", { w: 2.4, h: 0.7, bg: C.tray, color: C.ink }), 2.6, -1.0, 0.75));
    const bars = [0.35, 0.7, 1.1, 0.8, 1.35, 0.6, 0.95, 0.45, 0.75, 0.3];
    bars.forEach((hgt, i) => { const b = tile(renderer, { w: 0.2, h: hgt, r: 0.1, depth: 0.12, bg: C.cobalt });
      root.add(place(b, -2.9 + i * 0.32, -1.0, 0.75)); });
    return { bounds: [9.4, 4.4] };
  },
};

// ---------- mount ----------
export function mount(el, name, { interactive = false, exportMode = false } = {}) {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: exportMode });
  renderer.setClearColor(0x000000, 0); renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.setPixelRatio(exportMode ? 1 : Math.min(devicePixelRatio, 2));
  el.appendChild(renderer.domElement); renderer.domElement.style.display = "block";

  const scene = new THREE.Scene(), root = new THREE.Group(); scene.add(root);
  scene.add(new THREE.AmbientLight(0xffffff, 2.45));
  const sun = new THREE.DirectionalLight(0xfff6ea, 0.95); sun.position.set(-4, 5.5, 13); sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048); sun.shadow.radius = 9; sun.shadow.blurSamples = 20; sun.shadow.bias = -0.0004;
  Object.assign(sun.shadow.camera, { left: -9, right: 9, top: 7, bottom: -7, near: 1, far: 40 }); scene.add(sun);
  const { bounds, takes } = SCENES[name](renderer, root);
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(40, 30), new THREE.ShadowMaterial({ opacity: 0.15 }));
  floor.position.z = -0.02; floor.receiveShadow = true; scene.add(floor);

  // Near-front view with a gentle turn, so the layers read as depth without losing the UI's front.
  const camera = new THREE.PerspectiveCamera(26, 1, 0.1, 100);
  const base = { x: -0.2, y: 0.24 };
  root.rotation.set(base.x, base.y, 0); floor.rotation.copy(root.rotation);
  function fit() {
    const w = el.clientWidth || 800, h = el.clientHeight || 520; renderer.setSize(w, h, false);
    renderer.domElement.style.width = "100%"; renderer.domElement.style.height = "100%";
    camera.aspect = w / h; const t = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
    const d = Math.max(bounds[1] / 2 / t, bounds[0] / 2 / (t * camera.aspect)) * (exportMode ? 1.22 : 1.12);
    camera.position.set(0, 0, d + 1); camera.lookAt(0, 0, 0); camera.updateProjectionMatrix();
  }
  fit();

  let active = -1, pointer = { x: 0, y: 0 }, tilt = { x: 0, y: 0 };
  const setActive = (i) => { if (i === active || i < 0) return; active = i; takes?.forEach((t, j) => t.userData.face.material.map = t.userData.maps[j === i ? 1 : 0]); };
  // Moves each take toward its pose: the active one lifted toward the viewer, the others sunk slightly. k = 1 snaps.
  const pose = (k) => takes?.forEach((t, i) => { const on = i === active, home = t.userData.home;
    const tz = home.z + (on ? 1.9 : -0.3), ty = home.y + (on ? 0.15 : 0), ts = on ? 1.08 : 0.97;
    const tx = home.x - (on ? 1.9 * Math.sin(base.y) : 0); // lift straight toward the viewer, not along the turned axis
    t.position.x += (tx - t.position.x) * k; t.position.z += (tz - t.position.z) * k; t.position.y += (ty - t.position.y) * k; const s = t.scale.x + (ts - t.scale.x) * k; t.scale.set(s, s, 1); });
  setActive(exportMode ? 1 : 0);

  if (exportMode) { pose(1); renderer.render(scene, camera); return { renderer }; }

  if (interactive && takes) {
    const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
    const hit = (e) => { const r = el.getBoundingClientRect();
      ndc.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
      pointer = { x: ndc.x, y: ndc.y }; ray.setFromCamera(ndc, camera);
      const hits = ray.intersectObjects(takes.flatMap((t) => [t.userData.body, t.userData.face]));
      return hits.length ? takes.findIndex((t) => t.children.includes(hits[0].object)) : -1; };
    el.addEventListener("pointermove", (e) => { const i = hit(e); setActive(i); el.style.cursor = i >= 0 ? "pointer" : ""; });
    el.addEventListener("pointerdown", (e) => setActive(hit(e)));
    el.addEventListener("pointerleave", () => { pointer = { x: 0, y: 0 }; });
    el.addEventListener("keydown", (e) => { if (e.key === "ArrowRight") setActive(Math.min(2, active + 1)); if (e.key === "ArrowLeft") setActive(Math.max(0, active - 1)); });
  }

  let visible = true, last = performance.now();
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; if (visible) { last = performance.now(); requestAnimationFrame(frame); } }).observe(el);
  new ResizeObserver(fit).observe(el);
  function frame(now) {
    if (!visible) return;
    const k = reduce ? 1 : 1 - Math.exp(-Math.min(0.05, (now - last) / 1000) * 9); last = now;
    if (!reduce) { tilt.x += (pointer.y * -0.05 - tilt.x) * k; tilt.y += (pointer.x * 0.08 - tilt.y) * k; }
    root.rotation.set(base.x + tilt.x, base.y + tilt.y, 0); floor.rotation.copy(root.rotation);
    pose(k);
    renderer.render(scene, camera); requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
  return { renderer, setActive };
}
