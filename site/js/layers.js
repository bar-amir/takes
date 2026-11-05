// Layered UI: the Takes interface as an abstraction of thick, soft tiles floating in depth.
// One engine, several scenes. The "takes" scene is interactive on the site (hover or tap a take to bring it
// to the front); every scene can also render once on a transparent background for exporting stills
// (layers.html?scene=coach&export=1), the layout frames for the Higgsfield stills in brand/campaign/HIGGSFIELD-KIT.md. Text is drawn to canvas textures, so it stays crisp at any size.
import * as THREE from "https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js";

const C = { ink: "#171714", paper: "#F3EBDD", card: "#F5EEE2", strip: "#ECE4D5", tray: "#EADFCB",
  cobalt: "#3045FF", acid: "#E8F449", tomato: "#F0543D", mute: "#8A8478", red: "#B3261E", green: "#1E6B3A",
  redBg: "rgba(240,84,61,.13)", greenBg: "rgba(30,107,58,.11)" };
const ASSET_V = "3"; // bump when the rendered pieces change, so browsers fetch the new files
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
  return { y: yy, x: x + ctx.measureText(line).width }; // where the text ends
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
// A rounded frame with a hole: the selection outline around a take, exported as its own sprite.
function ringTile(w, h, r, band, color) {
  const sh = shape(w, h, r), hole = shape(w - band * 2, h - band * 2, Math.max(0.02, r - band)); sh.holes.push(hole);
  const geo = new THREE.ExtrudeGeometry(sh, { depth: 0.1, bevelEnabled: true, bevelThickness: 0.02, bevelSize: 0.015, bevelSegments: 3, curveSegments: 28 });
  const m = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ color })); m.castShadow = true; const g = new THREE.Group(); g.add(m);
  g.userData = { w, h }; return g;
}
const sized = (obj, k) => { obj.scale.setScalar(k); return obj; }; // a piece drawn larger than its tile
const place = (obj, x, y, z, name) => { obj.position.set(x, y, z); if (name) obj.name = name; return obj; };

// ---------- scenes ----------
// Each scene returns { bounds: [w, h], takes?: [tile groups] } after adding tiles to `root`.
const TAKES = [
  ["Take 1", "Thursday works for me. One ask: I need the specs by Wednesday EOD, otherwise QA slips again."],
  ["Take 2", "Sure, Thursday it is. I'll need the specs by Wednesday EOD so QA doesn't slip again."],
  ["Take 3", "Thursday's fine as long as the specs land by Wed EOD."],
];
const label = (ctx, s, x = 26, y = 44) => text(ctx, s, x, y, { size: 20, weight: 700 });
const measure = (s, size, weight = 700) => { const c = measure.c ||= document.createElement("canvas").getContext("2d"); c.font = `${weight} ${size}px ${FONT}`; return c.measureText(s).width / PX; };
const chip = (renderer, s, { dotColor = C.cobalt, bg = C.tray, color = C.ink, w } = {}) => tile(renderer, {
  w: w || 0.66 + measure(s, 22), h: 0.52, r: 0.16, depth: 0.08, bg,
  draw: (c, cw, ch) => { dot(c, 24, ch / 2, 7, dotColor); text(c, s, 42, ch / 2 + 8, { size: 22, weight: 700, color }); } });
const pill = (renderer, s, { w = 2, h = 0.6, bg = C.ink, color = C.paper, depth = 0.14 } = {}) => tile(renderer, {
  w, h, r: h / 2, depth, bg, draw: (c, cw, ch) => text(c, s, cw / 2, ch / 2 + 8, { size: 23, weight: 700, color, align: "center" }) });

const SCENES = {
  takes(renderer, root) {
    root.add(place(tile(renderer, { w: 10.4, h: 6.6, r: 0.34, depth: 0.16, bg: C.card }), 0, 0, 0, "base"));
    root.add(place(chip(renderer, "Slack message"), -3.85, 2.75, 0.55, "chip"));
    root.add(place(tile(renderer, { w: 9.6, h: 0.9, r: 0.16, depth: 0.08, bg: C.strip,
      draw: (c, cw, ch) => { text(c, "Your draft", 24, 34, { size: 15, weight: 700, color: C.mute });
        text(c, "ya thursday works but i need the specs by wed eod otherwise qa slips again", 24, 66, { size: 21 }); } }), 0, 1.85, 0.55, "draft"));
    const takes = TAKES.map(([t, body], i) => {
      const card = tile(renderer, { w: 3.0, h: 2.9, r: 0.22, depth: 0.22, bg: C.card,
        outline: { width: 2, color: "#E3DED4" }, selectedOutline: { width: 5, color: C.ink },
        draw: (c) => { label(c, t); wrap(c, body, 26, 92, 248, { size: 22, lead: 1.42 }); } });
      card.userData.home = new THREE.Vector3(-3.15 + i * 3.15, -0.45, 0.95);
      root.add(place(card, ...card.userData.home.toArray(), "take" + (i + 1))); return card;
    });
    root.add(place(pill(renderer, "Paste take ↵", { w: 2.1 }), 3.95, -2.65, 0.75, "paste"));
    const ring = place(ringTile(3.12, 3.02, 0.26, 0.07, C.ink), 0, -0.45, 1.0, "ring"); ring.visible = false; root.add(ring);
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
        underline(c, "make you a feedback", x, 92, 24, C.tomato); } }), 0.2, 3.5, 0.9, "draft"));
    root.add(place(tile(renderer, { w: 10, h: 3.9, r: 0.3, depth: 0.14, bg: C.tray,
      draw: (c, cw, ch) => { text(c, "English coach", 30, 52, { size: 24, weight: 700 }); text(c, "3 notes on your draft", 210, 52, { size: 21, color: C.mute });
        text(c, "Conditionals", 30, ch - 34, { size: 20, weight: 700 });
        text(c, "A future condition takes the present after “if”.", 170, ch - 34, { size: 20, color: "#4A463F" }); } }), 0, -0.85, 0, "tray"));
    const fix = (a, b, sel) => tile(renderer, { w: 1.0 + measure(a, 22, 400) + measure(b, 22, 700), h: 0.66, r: 0.18, depth: 0.1, bg: C.card,
      outline: sel ? { width: 4, color: C.ink } : { width: 2, color: "#E3DED4" },
      draw: (c, cw, ch) => { const y = ch / 2 + 8; const w1 = text(c, a, 22, y, { size: 22, color: C.red });
        c.fillStyle = C.red; c.fillRect(22, y - 7, w1, 2); text(c, "→", 34 + w1, y, { size: 22, color: C.mute });
        text(c, b, 70 + w1, y, { size: 22, weight: 700, color: C.green }); } });
    root.add(sized(place(fix("If you will send", "If you send", true), -2.4, 0.05, 1.9, "fix1"), 1.2));
    root.add(sized(place(fix("until tomorrow", "by tomorrow"), 2.9, -0.45, 1.2, "fix2"), 1.2));
    root.add(sized(place(fix("make you a feedback", "give you feedback"), -0.6, -1.45, 1.5, "fix3"), 1.2));
    return { bounds: [10.4, 6.6] };
  },
  proofread(renderer, root) {
    root.add(place(tile(renderer, { w: 7.4, h: 4.2, r: 0.3, depth: 0.16, outline: { width: 2, color: "#E3DED4" },
      draw: (c, cw, ch) => { label(c, "Proofread", 34, 56);
        diff(c, [["Thanks for the", ""], ["quick", ""], ["reveiw", "del"], ["review!", "ins"], ["I'll send the", ""], ["final", ""], ["deck", ""],
          ["tommorow", "del"], ["tomorrow", "ins"], ["once", ""], ["its", "del"], ["it's", "ins"], ["approved.", ""]], 34, 120, cw - 70, { size: 30, lead: 1.6 });
        text(c, "3 fixes", 34, ch - 34, { size: 21, color: C.mute }); } }), -0.9, 0, 0, "card"));
    const f = (a, b) => tile(renderer, { w: 1.0 + measure(a, 22, 400) + measure(b, 22, 700), h: 0.62, r: 0.18, depth: 0.1, bg: C.card,
      outline: { width: 2, color: "#E3DED4" }, draw: (c, cw, ch) => { const y = ch / 2 + 8; const w1 = text(c, a, 20, y, { size: 22, color: C.red });
        c.fillStyle = C.red; c.fillRect(20, y - 7, w1, 2); text(c, "→", 32 + w1, y, { size: 22, color: C.mute }); text(c, b, 66 + w1, y, { size: 22, weight: 700, color: C.green }); } });
    root.add(sized(place(f("reveiw", "review"), 3.7, 2.0, 1.0, "fix1"), 1.25));
    root.add(sized(place(f("tommorow", "tomorrow"), 4.3, 0.45, 1.7, "fix2"), 1.25));
    root.add(sized(place(f("its", "it's"), 3.4, -1.3, 2.3, "fix3"), 1.25));
    return { bounds: [11.8, 5.2], zoom: 1.06 };
  },
  presets(renderer, root) {
    ["Polish email", "Slack message", "Proofread", "Shorter", "Friendlier"].forEach((s, i) => {
      const sel = i === 0; const t = chip(renderer, s, { dotColor: sel ? C.acid : "#C4BDAF", bg: sel ? C.ink : C.card, color: sel ? C.paper : C.mute, w: 2.6 });
      root.add(place(t, -3.3 + (sel ? 0.35 : 0), 2.4 - i * 0.95, sel ? 1.8 : 0.3 + i * 0.1, "chip" + (i + 1)));
    });
    root.add(place(tile(renderer, { w: 6.2, h: 1.55, r: 0.22, depth: 0.14,
      draw: (c, cw) => { text(c, "Instruction", 30, 44, { size: 18, weight: 700, color: C.mute });
        wrap(c, "Polite and clear. Open with the point, close with a thank-you.", 30, 100, cw - 60, { size: 28 }); } }), 1.4, 1.9, 0.5, "instruction"));
    const rules = (title, color, items) => (c) => { dot(c, 36, 44, 8, color); text(c, title, 54, 52, { size: 24, weight: 700, color });
      items.forEach((it, i) => text(c, it, 30, 112 + i * 52, { size: 24 })); };
    root.add(place(tile(renderer, { w: 3.0, h: 2.2, r: 0.22, depth: 0.14, draw: rules("Do", C.green, ["Full sentences", "One ask per email"]) }), -0.15, -0.9, 1.2, "do"));
    root.add(place(tile(renderer, { w: 3.0, h: 2.2, r: 0.22, depth: 0.14, draw: rules("Avoid", C.red, ["Slang", "Exclamation marks"]) }), 2.45, -1.55, 1.9, "avoid"));
    return { bounds: [10.6, 5.4], offsetY: -0.35 };
  },
  shortcut(renderer, root) {
    root.add(place(tile(renderer, { w: 9.0, h: 3.4, r: 0.26, depth: 0.16, outline: { width: 2, color: "#E3DED4" },
      draw: (c) => { text(c, "Message #design", 30, 44, { size: 18, weight: 700, color: C.mute });
        const w = text(c, "ya thursday works but i need the specs by wed eod", 30, 112, { size: 30 });
        c.fillStyle = C.cobalt; c.fillRect(36 + w, 84, 3, 36); } }), 0.3, 0.9, 0, "field"));
    const key = (s, w, bg = C.card) => tile(renderer, { w, h: 1.15, r: 0.22, depth: 0.45, bg,
      draw: (c, cw, ch) => text(c, s, cw / 2, ch / 2 + 15, { size: 44, align: "center" }) });
    root.add(sized(place(key("⌃", 1.15), -3.0, -1.35, 2.2, "key-control"), 1.25));
    root.add(sized(place(key("⌥", 1.15), -1.45, -1.35, 2.2, "key-option"), 1.25));
    root.add(sized(place(key("", 3.4, C.cobalt), 1.35, -1.35, 2.2, "key-space"), 1.15));
    root.add(place(chip(renderer, "Slack message"), 3.6, 2.2, 1.0, "chip"));
    return { bounds: [10, 6.4] };
  },
  tone(renderer, root) {
    root.add(place(tile(renderer, { w: 6.0, h: 1.25, r: 0.22, depth: 0.12, bg: C.strip,
      draw: (c) => { text(c, "Replying to", 28, 42, { size: 17, weight: 700, color: C.mute }); text(c, "Any update on the launch?", 28, 92, { size: 26 }); } }), -1.3, 2.1, 0, "reply"));
    root.add(place(tile(renderer, { w: 7.4, h: 2.3, r: 0.24, depth: 0.16, outline: { width: 2, color: "#E3DED4" },
      draw: (c, cw) => { label(c, "Take 1", 30, 50); wrap(c, "We're a bit behind, sorry. The new date is Friday, and I'll share a short update tomorrow.", 30, 110, cw - 60, { size: 27 }); } }), 0, 0.15, 1.0, "take"));
    root.add(place(tile(renderer, { w: 4.4, h: 0.74, r: 0.37, depth: 0.14, bg: C.tray,
      draw: (c, cw, ch) => { dot(c, 34, ch / 2, 9, C.green); text(c, "May read as warm and polite", 56, ch / 2 + 8, { size: 23, weight: 700 }); } }), 1.7, -1.55, 2.1, "note"));
    return { bounds: [9.6, 5.4], zoom: 1.14 };
  },
  languages(renderer, root) {
    [["Deutsch", "Donnerstag passt mir. Die Specs brauche ich bis Mittwoch."], ["Español", "El jueves me viene bien. Necesito las especificaciones para el miércoles."],
     ["English", "Thursday works for me. I need the specs by Wednesday."]].forEach(([lang, line], i) => {
      root.add(place(tile(renderer, { w: 7.0, h: 1.45, r: 0.24, depth: 0.14, outline: i === 2 ? { width: 4, color: C.ink } : { width: 2, color: "#E3DED4" },
        draw: (c, cw) => { text(c, lang, 30, 44, { size: 18, weight: 700, color: C.mute }); wrap(c, line, 30, 92, cw - 60, { size: 25 }); } }), -0.9 + i * 0.9, 1.5 - i * 1.5, 0.2 + i * 0.85, ["de", "es", "en"][i]));
    });
    return { bounds: [9.4, 5.6] };
  },
  local(renderer, root) {
    root.add(place(tile(renderer, { w: 8.2, h: 5.2, r: 0.3, depth: 0.16,
      bg: C.ink, draw: (c, cw) => { text(c, "Engine", 34, 54, { size: 18, weight: 700, color: "#9A9488" });
        text(c, "Local model", 34, 118, { size: 34, weight: 700, color: C.paper });
        text(c, "Ollama · found on this Mac", 34, 166, { size: 22, weight: 700, color: C.acid }); } }), 0.4, 0.3, 0, "panel"));
    root.add(place(tile(renderer, { w: 5.2, h: 2.9, r: 0.24, depth: 0.1, outline: { width: 2, color: "#E3DED4" },
      draw: (c, cw) => { const row = (y, a, b, on) => { if (on) { c.fillStyle = C.tray; roundRect(c, 12, y - 40, cw - 24, 60, 12); c.fill(); }
          text(c, a, 36, y, { size: 24, weight: on ? 700 : 400 }); text(c, b, cw - 70, y, { size: 20, color: C.mute, align: "right" });
          if (on) text(c, "✓", cw - 40, y, { size: 24, weight: 700, color: C.cobalt, align: "center" }); };
        row(66, "llama3.2", "Ollama", true); row(146, "qwen3:8b", "Ollama"); row(226, "gemma-3-12b", "LM Studio"); } }), -1.3, -1.35, 1.3, "menu"));
    const badge = tile(renderer, { w: 2.5, h: 0.78, r: 0.39, depth: 0.14, bg: C.acid,
      draw: (c, cw, ch) => text(c, "On this Mac", cw / 2, ch / 2 + 8, { size: 23, weight: 700, align: "center" }) });
    root.add(sized(place(badge, 3.1, 0.55, 2.3, "badge"), 1.2));
    return { bounds: [9.4, 6.4] };
  },
  instant(renderer, root) {
    root.add(sized(place(tile(renderer, { w: 9.6, h: 2.2, r: 0.3, depth: 0.14, outline: { width: 2, color: "#E3DED4" },
      draw: (c, cw, ch) => { text(c, "Message #launch", 30, 48, { size: 17, weight: 700, color: C.mute });
        wrap(c, "Running about 5 minutes late, sorry! Start without me and I'll catch up.", 30, 100, cw - 60, { size: 26 }); } }), 0, -0.4, 0, "field"), 1.14));
    const toast = tile(renderer, { w: 3.6, h: 0.86, r: 0.43, depth: 0.14, bg: C.ink,
      draw: (c, cw, ch) => { dot(c, 40, ch / 2, 13, C.acid); text(c, "Pasted · ⌘Z to undo", 66, ch / 2 + 8, { size: 23, weight: 700, color: C.paper }); } });
    toast.rotation.z = -0.03; root.add(place(toast, -2.35, 1.45, 1.6, "toast"));
    const ret = tile(renderer, { w: 1.3, h: 1.3, r: 0.36, depth: 0.36, bg: "#F2D23C",
      draw: (c, cw, ch) => text(c, "↵", cw / 2, ch / 2 + 16, { size: 48, weight: 700, align: "center" }) });
    root.add(sized(place(ret, 3.95, -2.0, 2.3, "return"), 1.35));
    return { bounds: [10, 4.6] };
  },
  dictation(renderer, root) {
    root.add(place(tile(renderer, { w: 8.8, h: 3.6, r: 0.3, depth: 0.16,
      draw: (c, cw) => { const end = wrap(c, "can we push the call to four, the build is still running", 34, 66, cw - 70, { size: 27 });
        c.fillStyle = C.cobalt; c.fillRect(end.x + 6, end.y - 26, 3, 34); } }), 0, 0.5, 0, "card"));
    root.add(place(pill(renderer, "● Dictating", { w: 2.4, h: 0.7, bg: C.tray, color: C.ink }), 3.0, -1.95, 1.1, "pill"));
    const bars = [0.35, 0.7, 1.1, 0.8, 1.35, 0.6, 0.95, 0.45, 0.75, 0.3];
    const wave = new THREE.Group(); wave.userData = { w: 3.1, h: 1.4 }; // the waveform is one piece
    bars.forEach((hgt, i) => { const b = tile(renderer, { w: 0.2, h: hgt, r: 0.1, depth: 0.12, bg: C.cobalt }); b.position.set(-1.44 + i * 0.32, 0, 0); wave.add(b); });
    root.add(sized(place(wave, -1.2, -0.75, 1.9, "wave"), 1.5));
    return { bounds: [9.4, 4.4] };
  },
};

// Camera for the live piece scenes: how far the view looks down (x) and turns (y), per scene.
const VIEWS = { coach: { x: -0.34 }, local: { x: -0.24 } };
// Camera angles for the wide carousel frames (rotation of the scene, radians): a different view per feature.
const SHOTS = {
  shortcut: [-0.36, -0.3], presets: [-0.2, 0.36], proofread: [-0.44, 0.14], coach: [-0.14, -0.3], local: [-0.28, 0.4],
  instant: [-0.52, -0.1], dictation: [-0.1, 0.3], tone: [-0.26, -0.36], languages: [-0.32, 0.28],
};

// A soft rounded shadow, drawn once and reused under every sprite.
let shadowTex;
function shadowTexture() {
  if (shadowTex) return shadowTex;
  const cv = document.createElement("canvas"); cv.width = 256; cv.height = 256; const c = cv.getContext("2d");
  c.filter = "blur(22px)"; c.fillStyle = "rgba(60,45,25,0.55)"; roundRect(c, 48, 48, 160, 160, 26); c.fill();
  shadowTex = new THREE.CanvasTexture(cv); return shadowTex;
}

// Carousel framing: measure where the scene landed in the first render, then zoom and offset the camera so it
// fills the right part of the frame (x 42%-97%, y 7%-93%), leaving the left for the caption.
function frameRight(renderer, scene, camera) {
  const cv = renderer.domElement, W = cv.width, H = cv.height, c2 = document.createElement("canvas"); c2.width = W; c2.height = H;
  const ctx = c2.getContext("2d"); ctx.drawImage(cv, 0, 0); const px = ctx.getImageData(0, 0, W, H).data;
  let x0 = W, y0 = H, x1 = 0, y1 = 0;
  for (let y = 0; y < H; y += 2) for (let x = 0; x < W; x += 2) if (px[(y * W + x) * 4 + 3] > 40) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
  if (x1 <= x0) return;
  const T = { x0: 0.42 * W, x1: 0.97 * W, y0: 0.07 * H, y1: 0.93 * H };
  const z = Math.min((T.x1 - T.x0) / (x1 - x0), (T.y1 - T.y0) / (y1 - y0));
  const cx = W / 2 + ((x0 + x1) / 2 - W / 2) * z, cy = H / 2 + ((y0 + y1) / 2 - H / 2) * z; // where the centre lands after zooming
  camera.zoom = z; camera.setViewOffset(W, H, cx - (T.x0 + T.x1) / 2, cy - (T.y0 + T.y1) / 2, W, H); camera.updateProjectionMatrix();
  renderer.render(scene, camera);
}

// ---------- device motion ----------
// On phones the scenes follow the phone's tilt the way they follow the cursor on desktop. Readings are relative to how
// the phone is being held: the resting angle drifts slowly toward the current one, so a slow change of grip re-centres.
// iPhone Safari asks permission first, which needs a tap, so it's requested on the first touch anywhere on the page.
const motion = { x: 0, y: 0, active: false };
if (typeof window !== "undefined" && "DeviceOrientationEvent" in window && matchMedia("(pointer: coarse)").matches) {
  let rest = null;
  const clamp = (v) => Math.max(-1, Math.min(1, v));
  const listen = () => addEventListener("deviceorientation", (e) => {
    if (e.beta == null || e.gamma == null) return;
    if (!rest) rest = { b: e.beta, g: e.gamma };
    rest.b += (e.beta - rest.b) * 0.01; rest.g += (e.gamma - rest.g) * 0.01;
    motion.x = clamp((e.gamma - rest.g) / 18); motion.y = clamp((rest.b - e.beta) / 18); motion.active = true;
  });
  if (typeof DeviceOrientationEvent.requestPermission === "function") {
    const ask = () => { removeEventListener("touchend", ask);
      DeviceOrientationEvent.requestPermission().then((r) => { if (r === "granted") listen(); }).catch(() => {}); };
    addEventListener("touchend", ask, { passive: true });
  } else listen();
}

// ---------- mount ----------
// opts: interactive (hover/tap/arrows bring a take forward), exportMode (render once, transparent),
// part (export one named part alone, front-on), shot (export the wide carousel framing), sprites (a folder of
// rendered part images; the takes scene then shows those instead of its own tiles).
// card: the stage is a carousel stage that bleeds past its card (6% right, 13% top and bottom); the scene is then
// fitted to the card's area, so only pieces that really stick out use the bleed.
export function mount(el, name, { interactive = false, exportMode = false, part = null, shot = false, sprites = null, onReady = null, card = false } = {}) {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: exportMode });
  renderer.setClearColor(0x000000, 0); renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.shadowMap.enabled = !part && !sprites; renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.setPixelRatio(exportMode ? 1 : Math.min(devicePixelRatio, 2));
  const canvas = renderer.domElement; el.appendChild(canvas); canvas.style.display = "block";
  if (sprites && !exportMode) { canvas.style.opacity = "0"; canvas.style.transition = "opacity .5s ease"; } // fade in once the renders load

  const scene = new THREE.Scene(), root = new THREE.Group(); scene.add(root);
  scene.add(new THREE.AmbientLight(0xffffff, 2.45));
  const sun = new THREE.DirectionalLight(0xfff6ea, 0.95); sun.position.set(-4, 5.5, 13); sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048); sun.shadow.radius = 9; sun.shadow.blurSamples = 20; sun.shadow.bias = -0.0004;
  Object.assign(sun.shadow.camera, { left: -9, right: 9, top: 7, bottom: -7, near: 1, far: 40 }); scene.add(sun);
  let { bounds, takes, zoom = 1, offsetY = 0 } = SCENES[name](renderer, root);
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(40, 30), new THREE.ShadowMaterial({ opacity: 0.15 }));
  floor.position.z = -0.02; floor.receiveShadow = true; floor.visible = !part && !sprites; scene.add(floor);
  // Centre the scene on its pieces and fit to them, so every stage frames its graphic the same way.
  if (!part) {
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    root.children.forEach((o) => { if (!o.visible || !o.userData.w) return; const w = o.userData.w * o.scale.x, h = o.userData.h * o.scale.x;
      x0 = Math.min(x0, o.position.x - w / 2); x1 = Math.max(x1, o.position.x + w / 2); y0 = Math.min(y0, o.position.y - h / 2); y1 = Math.max(y1, o.position.y + h / 2); });
    if (x1 > x0) { const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2; root.children.forEach((o) => { o.position.x -= cx; o.position.y -= cy; if (o.userData.home) o.userData.home.x -= cx, o.userData.home.y -= cy; });
      bounds = [x1 - x0 + 0.5, y1 - y0 + 0.5]; }
    if (offsetY) root.children.forEach((o) => { o.position.y += offsetY; if (o.userData.home) o.userData.home.y += offsetY; });
  }
  root.children.forEach((o) => { o.userData.home = o.userData.home || o.position.clone(); });

  // One part alone, seen almost straight on: the layout reference for its render.
  if (part) {
    root.children.forEach((o) => { o.visible = o.name === part; });
    const p = root.getObjectByName(part); p.position.set(0, 0, 0); p.rotation.set(0, 0, 0); bounds = [p.userData.w + 0.5, p.userData.h + 0.5]; takes = null;
  }
  // Rendered pieces are seen almost straight on, each scene turned a touch its own way; carousel frames use their
  // per-feature angle; otherwise the near-front three-quarter view of the stills.
  const turn = name === "takes" ? 0 : Math.sign(SHOTS[name]?.[1] || 0) * 0.26;
  const base = part ? { x: -0.12, y: 0 } : sprites ? { x: name === "takes" ? -0.05 : (VIEWS[name]?.x ?? -0.2), y: turn } : shot && SHOTS[name] ? { x: SHOTS[name][0], y: SHOTS[name][1] } : { x: -0.2, y: 0.24 };
  const camera = new THREE.PerspectiveCamera(26, 1, 0.1, 100);
  root.rotation.set(base.x, base.y, 0); floor.rotation.copy(root.rotation);
  function fit() {
    const w = el.clientWidth || 800, h = el.clientHeight || 520; renderer.setSize(w, h, false);
    canvas.style.width = "100%"; canvas.style.height = "100%";
    camera.aspect = w / h; const t = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
    // On phones the card stacks the stage above its caption with no bleed, so the scene fills the whole stage.
    const narrow = !exportMode && matchMedia("(max-width: 720px)").matches;
    const fw = card && !narrow ? 60 / 66 : 1, fh = card && !narrow ? 1 / 1.26 : 1;
    const air = narrow ? (name === "takes" ? 1.0 : 1.08 / zoom) : name === "takes" ? 1.12 : 1.1 / zoom;
    const d = Math.max(bounds[1] / 2 / (t * fh), bounds[0] / 2 / (t * camera.aspect * fw)) * (exportMode && !sprites ? (part ? 1.04 : 1.22) : air);
    camera.position.set(0, 0, d + 1); camera.lookAt(0, 0, 0); camera.clearViewOffset(); camera.zoom = 1;
    camera.updateProjectionMatrix();
  }
  fit();

  // State: in the takes scene the active take is lifted toward the camera; elsewhere pieces stay put.
  let active = -1, pointer = { x: 0, y: 0 }, tilt = { x: 0, y: 0 }, ring = null;
  const setActive = (i) => { if (i === active || i < 0) return; active = i;
    takes?.forEach((t, j) => { if (!t.userData.sprite) t.userData.face.material.map = t.userData.maps[j === i ? 1 : 0]; }); };
  const toCam = new THREE.Vector3(), goal = new THREE.Vector3();
  const lift = (o, on, k, dist, sOn, sOff = 1, sink = 0) => { const home = o.userData.home;
    if (on) goal.copy(toCam).sub(home).normalize().multiplyScalar(dist).add(home); else goal.set(home.x, home.y, home.z - sink);
    o.position.lerp(goal, k); const s = o.scale.x + ((on ? sOn : sOff) - o.scale.x) * k; o.scale.set(s, s, 1); };
  // A sprite's shadow: the higher the piece sits, the further, larger and softer its shadow falls.
  // It is drawn just under the piece, so it falls on whatever sits below it.
  const shade = (o) => { const sh = o.userData.shadow; if (!sh) return; const z = o.position.z, e = Math.min(z, 1.6);
    sh.position.set(o.position.x + 0.14 + e * 0.16, o.position.y - 0.2 - e * 0.2, z - 0.28); // set well back, so the turned camera reveals it
    const sc = 1.03 + e * 0.05; sh.scale.set(o.userData.w * sc * o.scale.x, o.userData.h * sc * o.scale.x, 1);
    sh.material.opacity = 0.34 + e * 0.08; };
  const pose = (k) => { root.updateMatrixWorld(); toCam.copy(camera.position); root.worldToLocal(toCam);
    if (takes) takes.forEach((t, i) => lift(t, i === active, k, 2.0, 1.04, 0.97, 0.3));
    root.children.forEach(shade);
    if (ring && active >= 0) { const t = takes[active]; ring.position.set(t.position.x, t.position.y, t.position.z + 0.02); ring.scale.copy(t.scale); } };
  setActive(1);

  // Sprites: every named piece is shown as its own rendered image on a plane, at the tile's place and size, over a
  // soft drawn shadow. The drawn tiles stay underneath until every image has loaded.
  let ready = !sprites;
  if (sprites) {
    const names = root.children.filter((o) => o.name && (o.visible || o.name === "ring")).map((o) => o.name);
    const loader = new THREE.TextureLoader();
    Promise.all(names.map((n) => loader.loadAsync(`${sprites}/${n}.webp?v=${ASSET_V}`).then((tex) => [n, tex]))).then((loaded) => {
      for (const [n, tex] of loaded) {
        tex.colorSpace = THREE.SRGBColorSpace; tex.anisotropy = renderer.capabilities.getMaxAnisotropy();
        const obj = root.getObjectByName(n), { w } = obj.userData, aspect = tex.image.width / tex.image.height;
        // The blank base panel stretches to its tile; everything else keeps the render's own proportions.
        const ph = n === "base" ? obj.userData.h : w / aspect;
        const plane = new THREE.Mesh(new THREE.PlaneGeometry(w, ph), new THREE.MeshBasicMaterial({ map: tex, transparent: true, depthWrite: false }));
        obj.children.forEach((c) => { c.visible = false; }); obj.add(plane); obj.visible = true; obj.userData.sprite = plane; obj.userData.h = ph;
        if (n === "ring") { ring = obj; continue; }
        const sh = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), new THREE.MeshBasicMaterial({ map: shadowTexture(), transparent: true, depthWrite: false }));
        root.add(sh); obj.userData.shadow = sh;
      }
      // Draw back to front by depth, since sprites don't write depth; each shadow just under its piece.
      root.children.filter((o) => o.userData.sprite).sort((a, b) => a.position.z - b.position.z).forEach((o, i) => {
        o.userData.sprite.renderOrder = 10 + i * 2; if (o.userData.shadow) o.userData.shadow.renderOrder = 9 + i * 2; });
      if (takes) takes.forEach((t) => { t.userData.sprite.renderOrder = 80; t.userData.shadow.renderOrder = 79; });
      if (ring) { const tw = takes[0].userData.w, th = takes[0].userData.h; ring.userData.sprite.geometry.dispose(); // hug a take on every side
        ring.userData.sprite.geometry = new THREE.PlaneGeometry(tw * 1.045, th + tw * 0.045); ring.userData.sprite.renderOrder = 90; }
      ready = true; pose(1); renderer.render(scene, camera); canvas.style.opacity = "1"; onReady?.();
    }).catch((err) => { console.warn("layers: renders missing, keeping the still", name, err); canvas.remove(); });
  }

  if (exportMode) {
    if (!part) pose(1); renderer.render(scene, camera);
    if (shot) frameRight(renderer, scene, camera);
    return { renderer };
  }

  const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
  const aim = (e) => { const r = el.getBoundingClientRect();
    ndc.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1); pointer = { x: ndc.x, y: ndc.y }; ray.setFromCamera(ndc, camera); };
  const hitTake = () => { const hits = ray.intersectObjects(takes.flatMap((t) => t.children.filter((c) => c.visible)));
    return hits.length ? takes.findIndex((t) => t.children.includes(hits[0].object)) : -1; };
  const onMove = (e) => { aim(e); if (!interactive) return;
    if (takes) { const i = hitTake(); setActive(i); el.style.cursor = i >= 0 ? "pointer" : ""; } };
  const onDown = (e) => { aim(e); if (interactive && takes) setActive(hitTake()); };
  const onLeave = () => { pointer = { x: 0, y: 0 }; };
  const onKey = (e) => { if (!takes) return; if (e.key === "ArrowRight") setActive(Math.min(2, active + 1)); if (e.key === "ArrowLeft") setActive(Math.max(0, active - 1)); };
  el.addEventListener("pointermove", onMove); el.addEventListener("pointerdown", onDown); el.addEventListener("pointerleave", onLeave); el.addEventListener("keydown", onKey);

  let visible = true, alive = true, last = performance.now();
  const io = new IntersectionObserver(([e]) => { visible = e.isIntersecting; if (visible && alive) { last = performance.now(); requestAnimationFrame(frame); } }); io.observe(el);
  const ro = new ResizeObserver(fit); ro.observe(el);
  function frame(now) {
    if (!visible || !alive) return;
    const k = reduce ? 1 : 1 - Math.exp(-Math.min(0.05, (now - last) / 1000) * 9); last = now;
    // The camera follows the cursor a little, or on a phone the phone's tilt.
    const p = motion.active ? motion : pointer;
    if (!reduce) { tilt.x += (p.y * -0.05 - tilt.x) * k; tilt.y += (p.x * 0.08 - tilt.y) * k; }
    root.rotation.set(base.x + tilt.x, base.y + tilt.y, 0); floor.rotation.copy(root.rotation);
    if (ready) pose(k);
    renderer.render(scene, camera); requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
  // Frees the WebGL context, so a carousel can keep only the slides near the screen alive.
  const destroy = () => { alive = false; io.disconnect(); ro.disconnect();
    el.removeEventListener("pointermove", onMove); el.removeEventListener("pointerdown", onDown); el.removeEventListener("pointerleave", onLeave); el.removeEventListener("keydown", onKey);
    scene.traverse((o) => { o.geometry?.dispose(); [].concat(o.material || []).forEach((m) => { m.map?.dispose(); m.dispose(); }); });
    renderer.dispose(); renderer.forceContextLoss(); canvas.remove(); };
  return { renderer, setActive, destroy };
}
