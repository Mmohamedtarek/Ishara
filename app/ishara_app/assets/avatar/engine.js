// =======================================================================
// Ishara signing avatar (Three.js r186)
// Ported from design/prototype.html (lines 1393-2105). The engine code is
// the prototype's; every change for the app is marked "Ishara app:" and
// listed in app/DECISIONS.md (step 5).
//
// Signs are keyframed: each frame places the wrist (or a fingertip / the
// palm) at a point in the signer's space, with a hand direction, a palm
// facing and a handshape. Two-bone IK turns that into arm rotations against
// the character's own skeleton, so contacts (chin, chest, the other palm)
// land where they should. The camera frames the upper body only: head to
// waist, the signing space.
//
// Ishara app: the page talks to Flutter only through the IsharaBridge
// JavaScript channel (events out) and window.__ishara.receive(cmd) (commands
// in). The sign library, hand shapes and characters are data from the
// language pack and cast.json; the engine maps no words (the app's catalogue
// does), it plays labels.
// =======================================================================
(function(){
  'use strict';
  var HOST = document.getElementById('avatar');
  if (!HOST) return;
  var canvas = document.createElement('canvas');
  canvas.setAttribute('aria-hidden', 'true');
  canvas.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;display:block;opacity:0;transition:opacity .6s ease;';
  HOST.insertBefore(canvas, HOST.firstChild);
  var busy = document.createElement('div');
  busy.setAttribute('aria-hidden', 'true');
  busy.className = 'busy';   // Ishara app: styled in style.css (the CSP allows no inline style attributes)
  HOST.appendChild(busy);
  var reduce = false;          // Ishara app: set by the app from the OS setting (init / setReduceMotion)
  var DEG = Math.PI / 180;

  // ---------- Ishara app: bridge to Flutter ----------
  function post(type, data){
    var msg = Object.assign({ type: type }, data || {});
    try { if (window.IsharaBridge) window.IsharaBridge.postMessage(JSON.stringify(msg)); } catch(e){}
    if (window.__isharaEvents) window.__isharaEvents.push(msg);   // tools/avatar_shots.py reads these
  }
  function report(code, e){ post('error', { code: code, message: String(e && e.message || e || '') }); }
  window.addEventListener('error', function(ev){ report('script', ev.message); });
  window.addEventListener('unhandledrejection', function(ev){ report('script', ev.reason); });

  var CAST = {};
  var DEF = 'nour';

  var GLTFL = null, MESHOPT = null;
  function loadAll(){
    var needGLB = Object.keys(CAST).some(function(k){ return CAST[k].kind === 'glb'; });
    Promise.all([import('three'), needGLB ? import('three/addons/loaders/GLTFLoader.js') : null, needGLB ? import('three/addons/libs/meshopt_decoder.module.js') : null])
      .then(function(m){ if (m[1]) GLTFL = m[1].GLTFLoader; if (m[2]) MESHOPT = m[2].MeshoptDecoder; init(m[0]); })
      .catch(function(e){ if (window.console) console.warn('[Ishara] three.js failed to load', e); fail('three_load', e); });
  }
  function fail(code, e){ canvas.style.display = 'none'; busy.style.opacity = '0'; report(code || 'webgl', e); }
  function init(T){ try { boot(T); } catch(e){ if (window.console) console.warn('[Ishara] 3D init failed', e); fail('init', e); } }

  // ---------- hand shapes: curl per finger (thumb, index, middle, ring, pinky), 0..100 ----------
  // Ishara app: the shapes (CURL), their contact reach (REACH) and finger
  // spread (SPREAD, degrees per finger, + = toward the thumb side; Q-A6) come
  // from the language pack's library.json.
  var CURL = {}, REACH = {}, SPREAD = {}, TIPF = {}, SPLIT = {}, WRAP = {};
  var FINGERS = ['Thumb','Index','Middle','Ring','Pinky'];
  var FMAX = [80, 250, 255, 255, 250];
  var FSPLIT = [[.3,.4,.3], [.36,.4,.24]];

  // ---------- sign library ----------
  // Signer's frame: x = toward the signer's RIGHT, y = up (m), z = toward the viewer.
  // Hand key: P = point, at = 'wrist' | 'tip' | 'palm', H = hand direction (wrist → fingers),
  // N = palm facing, c = hand shape. A P entry may be [landmark, dx, dy, dz]: dz is measured
  // from the body surface at that point, so contacts land on the skin.
  // Frame: { t: seconds, R: key, L: key, head: [turn°, nod°] }. Missing R/L/head carry over.
  var READY_R = { P:[.1,1.0,.27], H:[-.3,.05,.95], N:[-.5,-.85,.1], c:'relax' };
  var READY_L = { P:[-.1,1.0,.27], H:[.3,.05,.95], N:[.5,-.85,.1], c:'relax' };
  // Ishara app: the signs come from the pack (library.json); `rest` stays here.
  var SIGNS = { rest: { frames:[{ t:0, R:READY_R, L:READY_L, head:[0,0] }] } };
  // Ishara app: the prototype waves hello after loading a character; the
  // label comes from the pack (library.json `greeting`), none = no wave.
  var GREETING = null;
  function useLibrary(lib){
    GREETING = lib.greeting || null;
    Object.keys(lib.shapes).forEach(function(k){
      var s = lib.shapes[k];
      CURL[k] = s.curl; REACH[k] = s.reach; if (s.spread) SPREAD[k] = s.spread;
      TIPF[k] = s.tip || 'middle';
      if (s.split) SPLIT[k] = s.split;   // Ishara app: [knuckle, middle, tip] share of the fingers' curl
      if (s.thumbTo === 'fingers') WRAP[k] = true;   // Ishara app: the thumb lies across the curled fingers (S)
    });
    Object.keys(lib.signs).forEach(function(k){ if (k !== 'rest') SIGNS[k] = lib.signs[k]; });
  }

  // ---------- skeleton name aliases ----------
  var ALIAS = { Hips:['Hips','Bip01_Pelvis'], Spine:['Spine','Bip01_Spine'], Spine1:['Spine1','Bip01_Spine1'], Spine2:['Spine2','Bip01_Spine2'],
    Neck:['Neck','Bip01_Neck'], Head:['Head','Bip01_Head'], HeadTop_End:['HeadTop_End','Bip01_HeadNub'], LeftEye:['LeftEye','Bip01_LEye'], RightEye:['RightEye','Bip01_REye'] };
  ['Left','Right'].forEach(function(S){
    var b = 'Bip01_' + S.charAt(0) + '_';
    ALIAS[S + 'Shoulder'] = [S + 'Shoulder', b + 'Clavicle']; ALIAS[S + 'Arm'] = [S + 'Arm', b + 'UpperArm'];
    ALIAS[S + 'ForeArm'] = [S + 'ForeArm', b + 'Forearm']; ALIAS[S + 'Hand'] = [S + 'Hand', b + 'Hand'];
    ALIAS[S + 'ForeArm1'] = [S + 'ForeArm1', b + 'ForeTwist']; ALIAS[S + 'ForeArm2'] = [S + 'ForeArm2', b + 'ForeTwist1'];
    FINGERS.forEach(function(f, fi){
      for (var j = 1; j <= 4; j++) ALIAS[S + 'Hand' + f + j] = [S + 'Hand' + f + j, b + 'Finger' + fi + (j === 1 ? '' : String(j - 1))];
    });
  });

  var engine = null, pending = [], live = false;   // Ishara app: commands before `ready` are queued, then run in order

  function boot(T){
    var V3 = T.Vector3, Q = T.Quaternion;
    var XA = new V3(1,0,0), YA = new V3(0,1,0), ZA = new V3(0,0,1);

    var renderer;
    try { renderer = new T.WebGLRenderer({ canvas: canvas, antialias: true, alpha: true, powerPreference: 'high-performance' }); }
    catch(e){ return fail('webgl', e); }
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.outputColorSpace = T.SRGBColorSpace;
    renderer.toneMapping = T.NeutralToneMapping !== undefined ? T.NeutralToneMapping : T.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.0;
    // Ishara app: a lost GPU context (Android may drop it in the background) is reported
    canvas.addEventListener('webglcontextlost', function(ev){ ev.preventDefault(); report('context_lost'); }, false);
    canvas.addEventListener('webglcontextrestored', function(){ post('contextRestored'); }, false);

    var scene = new T.Scene();
    var camera = new T.PerspectiveCamera(24, 1, .05, 50);
    var hemi = new T.HemisphereLight(0xf4f1ea, 0x4a4540, 2.3); scene.add(hemi);
    var key = new T.DirectionalLight(0xfff1e2, 3.3); key.position.set(1.3, 2.4, 2.8); scene.add(key);
    var fillL = new T.DirectionalLight(0xe2e6ff, 1.3); fillL.position.set(-2.2, 1.3, 1.8); scene.add(fillL);
    var rim = new T.DirectionalLight(0xc9d0ff, 1.9); rim.position.set(-1.7, 2.0, -2.2); scene.add(rim);
    var rim2 = new T.DirectionalLight(0xffe6cf, 1.4); rim2.position.set(1.9, 1.7, -2.0); scene.add(rim2);

    var A = null, loaded = {}, loading = {};
    var wantId = null, activePose = 'rest', poseT = 0, speedK = 1, talking = false, ready = false, frozen = false;
    var paused = false, captionPx = 0, viewDeg = 0;   // Ishara app: see pause / reframe / preview

    // ---------- math helpers (world space) ----------
    function wpos(b){ return b.getWorldPosition(new V3()); }
    function wquat(b){ return b.getWorldQuaternion(new Q()); }
    function setWorldQuat(b, qw){ b.quaternion.copy(wquat(b.parent).invert().multiply(qw)); b.updateMatrixWorld(true); }
    function rotW(b, qd){ setWorldQuat(b, qd.clone().multiply(wquat(b))); }
    function dirTo(a, b){ return wpos(b).sub(wpos(a)).normalize(); }
    function aim(b, child, target){ rotW(b, new Q().setFromUnitVectors(dirTo(b, child), target)); }
    function rollAbout(b, axis, ang){ if (Math.abs(ang) > 1e-4) rotW(b, new Q().setFromAxisAngle(axis, ang)); }
    function vec(a, o){ return new V3(a[0] * o, a[1], a[2]).normalize(); }
    function signedAngle(from, to, axis){ return Math.atan2(new V3().crossVectors(from, to).dot(axis), from.dot(to)); }

    // ---------- body landmarks (measured on each character's own mesh) ----------
    function measure(C, obj){
      var B = C.bones, k = C.k, grid = {}, CELL = .01;
      obj.updateMatrixWorld(true);
      obj.traverse(function(n){
        if (!n.isMesh || !n.geometry || !n.geometry.attributes.position) return;
        // Ishara app: only surfaces a hand can touch (skinning every vertex
        // of eyes, lashes, teeth, shoes and trousers costs load time)
        if (/eye|lash|teeth|tongue|shoe|bottom/i.test(n.name || '')) return;
        var p = n.geometry.attributes.position, v = new V3(), m = n.matrixWorld;
        // Ishara app: skinned, quantized meshes (KHR_mesh_quantization) store
        // positions in -1..1; only the skinned position is the body surface.
        // The prototype read the raw values, found no vertex and used one
        // fixed depth for every contact.
        var skinned = n.isSkinnedMesh && typeof n.getVertexPosition === 'function';
        for (var i = 0; i < p.count; i++){
          if (skinned) n.getVertexPosition(i, v).applyMatrix4(m); else v.fromBufferAttribute(p, i).applyMatrix4(m);
          if (Math.abs(v.x) > .2 || v.y < .85 * k || v.y > 1.7 * k) continue;
          var key = Math.round(v.x / CELL) + ':' + Math.round(v.y / CELL);
          if (grid[key] === undefined || v.z > grid[key]) grid[key] = v.z;
        }
      });
      C.front = function(xw, y){
        var cx = Math.round(xw / CELL), cy = Math.round(y / CELL), best = -1;
        // Ishara app: the nearest measured ring (1, then up to 3 cells = 3 cm)
        // instead of the fixed fallback beside the face, where cells are sparse
        for (var rr = 1; rr <= 3 && best === -1; rr++)
          for (var dx = -rr; dx <= rr; dx++) for (var dy = -rr; dy <= rr; dy++){ var z = grid[(cx + dx) + ':' + (cy + dy)]; if (z !== undefined && z > best) best = z; }
        return best > -1 ? best : .08 * k;
      };
      var h0 = B.Head ? wpos(B.Head).y : 1.36 * k, top = C.top, hh = top - h0;
      C.headZ = B.Head ? wpos(B.Head).z : 0;
      if (B.LeftEye && B.RightEye){
        var ey = (wpos(B.LeftEye).y + wpos(B.RightEye).y) / 2, adj = C.lmAdj || {};
        C.lm = { chin: ey - .118 * k + (adj.chin || 0), mouth: ey - .072 * k + (adj.mouth || 0), cheek: ey - .035 * k + (adj.cheek || 0), forehead: ey + .052 * k + (adj.forehead || 0),
          chest: (B.Spine2 ? wpos(B.Spine2).y : 1.2 * k) + (adj.chest || 0) };
        // Ishara app: 'ear' = beside the head (CALL): its depth is measured from
        // the head bone, not from the skin (the side of the face is too uneven)
        C.lm.ear = ey - .02 * k;
      } else C.lm = { chin: h0 - .17 * hh, mouth: h0 + .01 * hh, cheek: h0 + .05 * hh, forehead: h0 + .6 * hh,
        chest: B.Spine2 ? wpos(B.Spine2).y - .01 * k : 1.16 * k };
      var hand = B.RightHand, tip = B.RightHandMiddle4 || B.RightHandMiddle3;
      C.handLen = hand && tip ? wpos(hand).distanceTo(wpos(tip)) * (B.RightHandMiddle4 ? 1 : 1.15) : .16 * k;
    }

    // ---------- IK: a hand key → arm spec (upper arm, forearm, hand, palm directions) ----------
    function resolvePoint(C, key, side){
      var P = key.P, sx = side === 'Right' ? 1 : -1, x, y, z;
      if (P[0] === 'ear'){
        x = P[1]; y = C.lm.ear + P[2]; z = C.headZ + P[3];   // Ishara app: from the head bone
      } else if (OTHER[P[0]]){
        // Ishara app: a point on the other hand (side-local → signer frame)
        var w = otherWant(C, side, key); x = w.x * sx; y = w.y; z = w.z;
      } else if (typeof P[0] === 'string'){
        x = P[1]; y = C.lm[P[0]] + P[2];
        z = C.front(-x, y) + P[3];                   // signer x → world x is mirrored
      } else { x = P[0] * C.k; y = P[1] * C.k; z = P[2] * C.k; }
      var H = new V3(key.H[0], key.H[1], key.H[2]).normalize(), N = new V3(key.N[0], key.N[1], key.N[2]).normalize();
      var p = new V3(x, y, z), at = key.at || 'wrist';
      if (at === 'tip') p.addScaledVector(H, -C.handLen * (REACH[key.c] || 1));
      else if (at === 'palm' || at === 'edge') p.addScaledVector(H, -C.handLen * (/^(s|a)$/.test(key.c) ? .35 : .45)).addScaledVector(N, -.022 * C.k);
      // signer frame → this arm's side-local frame (x = outward on that side)
      return { p: new V3(p.x * sx, p.y, p.z), H: [H.x * sx, H.y, H.z], N: [N.x * sx, N.y, N.z] };
    }
    function solveArm(C, S, key, off){
      var r = resolvePoint(C, key, S), o = C.outSign[S], B = C.bones;
      if (off) r.p.add(off);   // Ishara app: contact correction (bakeFrame)
      var sw = wpos(B[S + 'Arm']), sh = new V3(sw.x * o, sw.y, sw.z);
      var L1 = C.len[S][0], L2 = C.len[S][1];
      var d = r.p.clone().sub(sh), D = d.length();
      D = Math.min(Math.max(D, Math.abs(L1 - L2) + .01), L1 + L2 - .002);
      d.normalize();
      var a = (L1 * L1 - L2 * L2 + D * D) / (2 * D), h = Math.sqrt(Math.max(0, L1 * L1 - a * a));
      // Ishara app: a key may set the elbow direction E (signer frame, like H);
      // without it, the prototype's fixed pole.
      var pole = key.E ? new V3(key.E[0] * (S === 'Right' ? 1 : -1), key.E[1], key.E[2]).normalize() : new V3(.42, -1, -.28).normalize();
      pole.sub(d.clone().multiplyScalar(pole.dot(d))).normalize();
      var elbow = sh.clone().addScaledVector(d, a).addScaledVector(pole, h);
      var wrist = sh.clone().addScaledVector(d, D);
      var u = elbow.clone().sub(sh).normalize(), f = wrist.clone().sub(elbow).normalize();
      return { u:[u.x, u.y, u.z], f:[f.x, f.y, f.z], h:r.H, n:r.N, c:key.c };
    }

    // ---------- pose baking ----------
    function palmNormal(C, S){
      var B = C.bones, H = B[S + 'Hand'], M1 = B[S + 'HandMiddle1'], I1 = B[S + 'HandIndex1'], P1 = B[S + 'HandPinky1'];
      return new V3().crossVectors(dirTo(P1, I1), dirTo(H, M1)).multiplyScalar(-C.outSign[S]).normalize();
    }
    function resetBind(C){ C.boneList.forEach(function(n){ C.raw[n].quaternion.copy(C.bind[n]); }); C.root.updateMatrixWorld(true); }
    function poseArm(C, S, sp){
      var B = C.bones, U = B[S + 'Arm'], F = B[S + 'ForeArm'], H = B[S + 'Hand'], M1 = B[S + 'HandMiddle1'];
      if (!U || !F || !H) return;
      var o = C.outSign[S], du = vec(sp.u, o), df = vec(sp.f, o);
      aim(U, F, du);
      var want = new V3().crossVectors(du, df);
      if (want.lengthSq() > 1e-4 && C.hingeLocal[S]){
        var now = C.hingeLocal[S].clone().applyQuaternion(wquat(U)).projectOnPlane(du).normalize();
        want.projectOnPlane(du).normalize();
        rollAbout(U, du, signedAngle(now, want, du));
      }
      aim(F, H, df);
      var dh = sp.h ? vec(sp.h, o) : df;
      if (M1) aim(H, M1, dh);
      if (sp.n && M1 && B[S + 'HandIndex1'] && B[S + 'HandPinky1']){
        var nw = vec(sp.n, o).projectOnPlane(dh).normalize(), nn = palmNormal(C, S).projectOnPlane(dh).normalize();
        var a = signedAngle(nn, nw, dh);
        rollAbout(H, dh, a);
        [S + 'ForeArm1', S + 'ForeArm2'].forEach(function(nm){ if (B[nm]) rollAbout(B[nm], df, a * (C.twistShare[nm] || .5)); });
      }
      curlHand(C, S, CURL[sp.c] || CURL.relax, SPREAD[sp.c], SPLIT[sp.c], WRAP[sp.c] ? sp.c : null);
    }
    function curlHand(C, S, curl, spread, fsplit, wrap){
      var B = C.bones, H = B[S + 'Hand'], M1 = B[S + 'HandMiddle1'], I1 = B[S + 'HandIndex1'], P1 = B[S + 'HandPinky1'];
      if (!H || !M1 || !I1 || !P1) return;
      var N = palmNormal(C, S), L = dirTo(P1, I1);
      // Ishara app (Q-A6): finger spread first, at the knuckle: each finger
      // turns toward the pinky → index direction by `spread` degrees (+), the
      // thumb included, which swings it sideways away from the fingers (as in
      // FIVE). If a finger already points along that direction, its spread
      // has no axis and is skipped.
      if (spread) FINGERS.forEach(function(f, fi){
        var j1 = B[S + 'Hand' + f + '1'], j2 = B[S + 'Hand' + f + '2'];
        if (!j1 || !j2 || !spread[fi]) return;
        var d0 = dirTo(j1, j2), ax = new V3().crossVectors(d0, L);
        if (ax.lengthSq() < 1e-6) return;
        rollAbout(j1, ax.normalize(), spread[fi] * DEG);
      });
      FINGERS.forEach(function(f, fi){
        var j1 = B[S + 'Hand' + f + '1'], j2 = B[S + 'Hand' + f + '2'];
        if (!j1 || !j2) return;
        if (fi === 0 && wrap) return;   // Ishara app: placed by wrapThumb below
        var d0 = dirTo(j1, j2), tgt = fi === 0 ? N.clone().multiplyScalar(.55).addScaledVector(L, -1).normalize() : N;
        var axis = new V3().crossVectors(d0, tgt);
        if (axis.lengthSq() < 1e-6) return;
        axis.normalize();
        var c0 = C.curl0 ? C.curl0[fi] : 0;
        // Ishara app: a shape may bend the four fingers mostly at the
        // knuckles (flat-O): `split` replaces their default share per joint
        // (the thumb keeps its own)
        var total = ((curl[fi] - c0) / 100) * FMAX[fi] * DEG, split = fi === 0 ? FSPLIT[0] : (fsplit || FSPLIT[1]);
        for (var j = 1; j <= 3; j++){ var b = B[S + 'Hand' + f + j]; if (b) rollAbout(b, axis, total * split[j - 1]); }
      });
      if (wrap) wrapThumb(C, S, wrap, N, L);
    }
    // Ishara app: an S thumb lies flat across the front of the curled index
    // and middle fingers at any wrist angle: after the fingers curl, its tip
    // is placed (CCD over the thumb joints) 1.2 cm outside the middle
    // finger's middle segment, on the palm side (N); the base joint turns
    // freely, the two outer joints only bend on their hinge (as a thumb
    // does). The result depends only on the hand itself, so it is solved once
    // per character, hand and shape and then reused (local rotations).
    var WRAP_OUT = .012;
    function wrapThumb(C, S, shape, N, L){
      var B = C.bones, T = [B[S + 'HandThumb1'], B[S + 'HandThumb2'], B[S + 'HandThumb3']], T4 = B[S + 'HandThumb4'];
      var M2 = B[S + 'HandMiddle2'], M3 = B[S + 'HandMiddle3'];
      if (!T[0] || !T[1] || !T[2] || !M2 || !M3) return;
      var key = S + ':' + shape, cache = C.wrapCache || (C.wrapCache = {});
      if (cache[key]){
        T.forEach(function(b, i){ b.quaternion.copy(cache[key][i]); });
        T[0].updateMatrixWorld(true);
        return;
      }
      // the tip: the end bone, or (without one) a segment past the last joint;
      // without an end bone the last joint can't move the tip, so it is left
      var tip = function(){ if (T4) return wpos(T4); var a = wpos(T[1]), c = wpos(T[2]); return c.clone().add(c.clone().sub(a)); };
      var joints = T4 ? [2, 1, 0] : [1, 0];
      var target = wpos(M2).add(wpos(M3)).multiplyScalar(.5).addScaledVector(N, WRAP_OUT * C.k);
      // the thumb's hinge (its default bend plane, as in curlHand)
      var bendTo = N.clone().multiplyScalar(.55).addScaledVector(L, -1).normalize();
      for (var it = 0; it < 10; it++){
        joints.forEach(function(j){
          var b = T[j], p = wpos(b), a = tip().sub(p), t = target.clone().sub(p), ax;
          if (j === 0) ax = new V3().crossVectors(a, t);
          else {
            ax = new V3().crossVectors(dirTo(b, j === 2 && T4 ? T4 : T[j + 1]), bendTo);
            if (ax.lengthSq() < 1e-8) return;
            ax.normalize();
            a.projectOnPlane(ax); t.projectOnPlane(ax);
            if (a.lengthSq() < 1e-10 || t.lengthSq() < 1e-10) return;
            rollAbout(b, ax, signedAngle(a.normalize(), t.normalize(), ax) * .5);
            return;
          }
          var l = ax.length(); if (l < 1e-6) return;
          rollAbout(b, ax.divideScalar(l), Math.atan2(l, a.dot(t)) * .5);
        });
      }
      cache[key] = T.map(function(b){ return b.quaternion.clone(); });
    }
    function headTurn(C, h){
      if (!h) return;
      var nk = C.bones.Neck, hd = C.bones.Head;
      if (nk){ rollAbout(nk, YA, h[0] * .4 * DEG); rollAbout(nk, XA, h[1] * .4 * DEG); }
      if (hd){ rollAbout(hd, YA, h[0] * .6 * DEG); rollAbout(hd, XA, h[1] * .6 * DEG); }
    }
    // Ishara app: body contacts land on the skin. For a key measured from a
    // landmark with at 'tip' / 'palm', the real fingertip (the shape's `tip`
    // finger) or palm centre is measured after posing and the target moved
    // by the error, a few times. Other keys are posed exactly as before.
    function isContact(key){ return typeof key.P[0] === 'string' && key.P[0] !== 'ear' && (key.at === 'tip' || key.at === 'palm' || key.at === 'edge'); }

    // ---------- Ishara app: contacts on the other hand ----------
    // A key may aim at a point of the other hand (P = [otherWrist | otherPalm
    // | otherFist, dx, dy, dz], offsets in the signer frame). The other arm
    // is posed first and the points are read from its real bones, so the
    // contact holds on any character's proportions.
    var OTHER = { otherWrist: 1, otherPalm: 1, otherFist: 1 };
    function usesOther(key){ return !!(key && typeof key.P[0] === 'string' && OTHER[key.P[0]]); }
    function otherSide(S){ return S === 'Right' ? 'Left' : 'Right'; }
    // world points on hand O: the inside of the wrist (palm-side skin over
    // the joint), the middle of the palm's surface, the top of a fist (its
    // index / thumb side)
    function handPoints(C, O){
      var B = C.bones, H = B[O + 'Hand'], M1 = B[O + 'HandMiddle1'], I1 = B[O + 'HandIndex1'], P1 = B[O + 'HandPinky1'];
      if (!H || !M1 || !I1 || !P1) return null;
      var h = wpos(H), mid = h.clone().add(wpos(M1)).multiplyScalar(.5), n = palmNormal(C, O), up = wpos(I1).sub(wpos(P1)).normalize();
      return { otherWrist: h.clone().addScaledVector(n, .015 * C.k), otherPalm: mid.clone().addScaledVector(n, .012 * C.k), otherFist: mid.clone().addScaledVector(up, .03 * C.k) };
    }
    function otherWant(C, S, key){
      var O = otherSide(S), pts = C.handPts && C.handPts[O], w = pts && pts[key.P[0]];
      if (!w) w = C.bones[O + 'Hand'] ? wpos(C.bones[O + 'Hand']) : new V3(0, C.lm.chest, C.front(0, C.lm.chest));
      return toLocal(C, S, w).add(new V3(key.P[1] * (S === 'Right' ? 1 : -1), key.P[2], key.P[3]));
    }
    function toLocal(C, S, w){ return new V3(w.x * C.outSign[S], w.y, w.z); }
    function contactWant(C, S, key){
      if (OTHER[key.P[0]]) return otherWant(C, S, key);
      var x = key.P[1], y = C.lm[key.P[0]] + key.P[2];
      return new V3(x * (S === 'Right' ? 1 : -1), y, C.front(-x, y) + key.P[3]);
    }
    function contactGot(C, S, key){
      var B = C.bones;
      if (key.at === 'tip'){
        var f = TIPF[key.c] || 'middle', F = f.charAt(0).toUpperCase() + f.slice(1);
        var end = B[S + 'Hand' + F + '4'];
        if (end) return toLocal(C, S, wpos(end));
        // no end bone: the tip is one more segment past the last joint
        var j2 = B[S + 'Hand' + F + '2'], j3 = B[S + 'Hand' + F + '3'];
        if (!j2 || !j3) return null;
        var p3 = wpos(j3);
        return toLocal(C, S, p3.clone().add(p3.clone().sub(wpos(j2))));
      }
      var H = B[S + 'Hand'], M1 = B[S + 'HandMiddle1'];
      if (!H || !M1 || !B[S + 'HandIndex1'] || !B[S + 'HandPinky1']) return null;
      if (key.at === 'edge'){
        // Ishara app: the pinky-side edge of a closed hand (A / S on a palm,
        // fist on fist)
        var down = wpos(B[S + 'HandPinky1']).sub(wpos(B[S + 'HandIndex1'])).normalize();
        return toLocal(C, S, wpos(H).add(wpos(M1)).multiplyScalar(.5).addScaledVector(down, .045 * C.k));
      }
      var fist = /^(s|a)$/.test(key.c);
      var c = wpos(H).add(wpos(M1)).multiplyScalar(.5).addScaledVector(palmNormal(C, S), (fist ? .03 : .012) * C.k);
      return toLocal(C, S, c);
    }
    function bakeFrame(C, R, L, head){
      var offR = isContact(R) ? new V3() : null, offL = isContact(L) ? new V3() : null;
      // Ishara app: a key aiming at the other hand needs that hand posed
      // first; the library allows only one hand to aim at the other, and
      // that one doesn't touch the body, so it doesn't move in the loop
      var aimR = usesOther(R), aimL = usesOther(L);
      C.handPts = null;
      if (aimR || aimL){
        resetBind(C);
        var O = aimR ? 'Left' : 'Right';
        poseArm(C, O, solveArm(C, O, aimR ? L : R, null));
        C.handPts = {}; C.handPts[O] = handPoints(C, O);
      }
      for (var it = 0; it < 5; it++){
        resetBind(C);
        poseArm(C, 'Right', solveArm(C, 'Right', R, offR));
        poseArm(C, 'Left', solveArm(C, 'Left', L, offL));
        var more = false;
        [[R, offR, 'Right'], [L, offL, 'Left']].forEach(function(e){
          if (!e[1]) return;
          var got = contactGot(C, e[2], e[0]); if (!got) return;
          var err = contactWant(C, e[2], e[0]).sub(got);
          if (err.length() > .002){ e[1].add(err); more = true; }
        });
        if (!more) break;
      }
      headTurn(C, head);
      var out = {}; C.boneList.forEach(function(n){ out[n] = C.raw[n].quaternion.clone(); }); return out;
    }
    function bakeSign(C, sg){
      var R = READY_R, L = READY_L, head = [0,0];
      return sg.frames.map(function(fr){
        if (fr.R) R = fr.R; if (fr.L) L = fr.L; if (fr.head) head = fr.head;
        return { t: fr.t, q: bakeFrame(C, R, L, head) };
      });
    }

    // ---------- face ----------
    function morphIndex(m, key){
      var d = m.morphTargetDictionary; if (!d) return null;
      if (d[key] != null) return d[key];
      var k, lk = key.toLowerCase();
      for (k in d){ if (k.toLowerCase().slice(-lk.length) === lk) return d[k]; }
      return null;
    }
    var blinkT = -1, nextBlink = 1.2;
    function face(dt, t){
      nextBlink -= dt;
      if (nextBlink <= 0 && blinkT < 0){ blinkT = 0; nextBlink = 2.2 + Math.random() * 3.4; }
      var bl = 0;
      if (blinkT >= 0){ blinkT += dt; var k = blinkT / .09; bl = k < 1 ? k : (k < 2 ? 2 - k : 0); if (k >= 2) blinkT = -1; }
      var jaw = talking && !reduce ? .05 + Math.abs(Math.sin(t * 9)) * .12 : 0;
      A.morphMeshes.forEach(function(m){
        var mi = m.userData.mi, inf = m.morphTargetInfluences;
        if (mi.bl != null) inf[mi.bl] = bl; if (mi.br != null) inf[mi.br] = bl;
        if (mi.jaw != null) inf[mi.jaw] += (jaw - inf[mi.jaw]) * .35;
        if (mi.sl != null) inf[mi.sl] = .24; if (mi.sr != null) inf[mi.sr] = .24;
        if (mi.bu != null) inf[mi.bu] = talking ? .12 : .04;
      });
    }

    // ---------- framing: upper body only (top of the head to the waist) ----------
    function resize(){
      var r = HOST.getBoundingClientRect(), w = Math.max(1, r.width), h = Math.max(1, r.height);
      renderer.setSize(w, h, false);
      var aspect = w / h, tanH = Math.tan(camera.fov * DEG / 2), k = A ? A.k : 1;
      camera.aspect = aspect;
      // Ishara app: the caption is a Flutter widget; the app reports its height (reframe)
      var capPx = captionPx > 0 ? Math.max(captionPx, 70) : 0;
      // the caption strip may cover the belly, never the hands' signing space (chest and up)
      var capRoom = Math.min(.36, Math.max(0, capPx - 14) / h * .9);
      var topY = (A ? A.top : 1.62) + .045 * k, botY = (A ? A.waist : .86) + .05 * k;
      var visH = (topY - botY) / (1 - capRoom);
      var d = Math.max((visH / 2) / tanH, (.9 * k / 2) / (tanH * aspect));
      visH = 2 * d * tanH;
      var center = topY - visH / 2;
      // Ishara app: the preview screen orbits the camera around the signer (0 = front)
      var yr = viewDeg * DEG;
      camera.position.set(Math.sin(yr) * d, center + .05 * k, Math.cos(yr) * d);
      camera.lookAt(0, center, 0);
      camera.updateProjectionMatrix();
    }
    try { new ResizeObserver(resize).observe(HOST); } catch(e){ window.addEventListener('resize', resize); }
    resize();

    // ---------- loading ----------
    // Ishara app: characters are .glb files served next to this page
    // (cast.json `src`); the prototype's base64 copies and its unused
    // compressed-rig path (buildRig, loadScript, inflate) are not ported.
    function fetchCharacter(id){
      if (loaded[id]) return Promise.resolve(loaded[id]);
      if (loading[id]) return loading[id];
      var info = CAST[id]; if (!info) return Promise.reject(new Error('unknown character ' + id));
      if (info.kind !== 'glb') return Promise.reject(new Error('unsupported character kind ' + info.kind));
      loading[id] = fetch(info.src).then(function(r){
        if (!r.ok) throw new Error('HTTP ' + r.status + ' for ' + info.src);
        return r.arrayBuffer();
      }).then(function(buf){
        return new Promise(function(res, rej){
          var ld = new GLTFL(); if (MESHOPT) ld.setMeshoptDecoder(MESHOPT);
          ld.parse(buf, '', function(g){ res(prepareGLB(id, g.scene, info)); }, rej);
        });
      }).then(function(C){ makeThumb(C); loaded[id] = C; delete loading[id]; return C; }).catch(function(e){ delete loading[id]; throw e; });
      return loading[id];
    }

    function prepareGLB(id, obj, info){
      obj.traverse(function(n){
        if (!n.isMesh) return;
        (Array.isArray(n.material) ? n.material : [n.material]).forEach(function(m){
          if (!m) return;
          // a plain top: the sample outfit carries a vendor logo
          if (info.plainTop && /outfit_top/i.test((m.name || '') + ' ' + (n.name || ''))){ m.map = null; m.color.set(info.plainTop); m.needsUpdate = true; }
        });
      });
      return prepare(id, obj, info.curl0 || [0,0,0,0,0], info.lmAdj);
    }
    function prepare(id, obj, curl0, lmAdj){
      var C = { id: id, curl0: curl0 || null, lmAdj: lmAdj || null, root: obj, raw: {}, bones: {}, bind: {}, boneList: [], cur: {}, tgt: {}, POSEQ: {}, outSign: { Right:-1, Left:1 }, hingeLocal: {}, twistShare: {}, len: {}, morphMeshes: [], skinMats: [], outfitMats: [], top: 1.62, waist: .86, k: 1 };
      var box = new T.Box3().setFromObject(obj), size = box.getSize(new V3());
      if (size.z > size.y * 1.2){ obj.rotation.x = -Math.PI / 2; obj.updateMatrixWorld(true); box.setFromObject(obj); size = box.getSize(new V3()); }
      var hM = size.y > 20 ? size.y / 100 : size.y;
      if (!(hM > .8 && hM < 2.2)) hM = 1.72;
      obj.scale.multiplyScalar(hM / size.y);
      obj.updateMatrixWorld(true);
      obj.traverse(function(n){ if (n.isBone && !C.raw[n.name]){ C.raw[n.name] = n; C.boneList.push(n.name); } });
      Object.keys(ALIAS).forEach(function(k){ for (var i = 0; i < ALIAS[k].length; i++){ var b = C.raw[ALIAS[k][i]]; if (b){ C.bones[k] = b; break; } } });
      var B = C.bones;
      if (B.Head && B.LeftEye && B.RightEye){
        var eyes = wpos(B.LeftEye).add(wpos(B.RightEye)).multiplyScalar(.5);
        if (eyes.z < wpos(B.Head).z){ obj.rotation.y += Math.PI; obj.updateMatrixWorld(true); }
      }
      box.setFromObject(obj);
      var c = box.getCenter(new V3());
      obj.position.x -= c.x; obj.position.z -= c.z; obj.position.y -= box.min.y;
      obj.updateMatrixWorld(true);
      box.setFromObject(obj);

      C.boneList.forEach(function(n){ C.bind[n] = C.raw[n].quaternion.clone(); C.cur[n] = C.bind[n].clone(); C.tgt[n] = C.bind[n].clone(); });
      ['Right','Left'].forEach(function(S){
        var U = B[S + 'Arm'], F = B[S + 'ForeArm'], H = B[S + 'Hand'];
        if (!U || !F) return;
        var x = wpos(U).x; if (Math.abs(x) > 1e-3) C.outSign[S] = x > 0 ? 1 : -1;
        var hw = new V3().crossVectors(dirTo(U, F), ZA);
        if (hw.lengthSq() > 1e-6) C.hingeLocal[S] = hw.normalize().applyQuaternion(wquat(U).invert());
        C.len[S] = [wpos(U).distanceTo(wpos(F)), H ? wpos(F).distanceTo(wpos(H)) : .24];
        var t1 = B[S + 'ForeArm1'], t2 = B[S + 'ForeArm2'];
        if (t1 && t2 && H){ var d1 = wpos(t1).distanceTo(wpos(H)), d2 = wpos(t2).distanceTo(wpos(H)); C.twistShare[S + 'ForeArm1'] = d1 < d2 ? .66 : .33; C.twistShare[S + 'ForeArm2'] = d1 < d2 ? .33 : .66; }
      });
      C.top = B.HeadTop_End ? wpos(B.HeadTop_End).y : (B.LeftEye ? Math.min(box.max.y, wpos(B.LeftEye).y + .125 * box.max.y / 1.72) : box.max.y);
      C.k = B.RightArm ? wpos(B.RightArm).y / 1.246 : C.top / 1.62;   // body scale from shoulder height
      C.waist = B.Hips ? wpos(B.Hips).y : .86 * C.k;
      measure(C, obj);

      obj.traverse(function(n){
        if (!n.isMesh) return;
        n.frustumCulled = false;
        if (n.morphTargetDictionary && n.morphTargetInfluences){
          n.userData.mi = { bl: morphIndex(n, 'eyeBlinkLeft'), br: morphIndex(n, 'eyeBlinkRight'), jaw: morphIndex(n, 'jawOpen') != null ? morphIndex(n, 'jawOpen') : morphIndex(n, 'mouthOpen'), sl: morphIndex(n, 'mouthSmileLeft'), sr: morphIndex(n, 'mouthSmileRight'), bu: morphIndex(n, 'browInnerUp') };
          C.morphMeshes.push(n);
        }
        (Array.isArray(n.material) ? n.material : [n.material]).forEach(function(m){
          if (!m) return;
          var nm = (m.name || '') + ' ' + (n.name || '');
          if (m.color) m.userData.base = m.color.clone();
          if (/avatarbody|avatarhead/i.test(nm)) C.skinMats.push(m);
          if (/outfit/i.test(nm)) C.outfitMats.push(m);
        });
      });

      Object.keys(SIGNS).forEach(function(k){ C.POSEQ[k] = bakeSign(C, SIGNS[k]); });
      resetBind(C);
      return C;
    }

    // face thumbnail for the "who signs for you" picker, rendered once per character
    function makeThumb(C){
      try {
        var r2 = new T.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
        r2.setSize(128, 128, false); r2.outputColorSpace = T.SRGBColorSpace; r2.toneMapping = renderer.toneMapping;
        var sc = new T.Scene(); sc.background = new T.Color(0xE6E2D8);
        sc.add(new T.HemisphereLight(0xf4f1ea, 0x4a4540, 2.3));
        var kl = new T.DirectionalLight(0xfff1e2, 3.0); kl.position.set(1.3, 2.4, 2.8); sc.add(kl);
        C.boneList.forEach(function(n){ C.raw[n].quaternion.copy(C.POSEQ.rest[0].q[n]); });
        C.root.updateMatrixWorld(true); sc.add(C.root);
        var k = C.k, ey = C.lm.cheek + .04 * k, cam = new T.PerspectiveCamera(22, 1, .05, 20);
        cam.position.set(0, ey - .02 * k, .78 * k); cam.lookAt(0, ey - .045 * k, 0);
        r2.render(sc, cam);
        var url = r2.domElement.toDataURL('image/jpeg', .85);
        sc.remove(C.root); r2.dispose(); if (r2.forceContextLoss) r2.forceContextLoss();
        // Ishara app: the picker is a Flutter widget; the thumbnail goes to the app
        if (CAST[C.id]){ CAST[C.id].thumb = url; post('thumbnail', { character: C.id, dataUrl: url }); }
      } catch(e){}
    }
    function stage(C){
      if (A && A.root.parent) scene.remove(A.root);
      A = C; scene.add(C.root);
      C.boneList.forEach(function(n){ C.cur[n].copy(C.POSEQ.rest[0].q[n]); });
      resize();
      if (!ready){
        ready = true;
        canvas.style.opacity = '1';
        readyResolvers.forEach(function(fn){ try { fn(); } catch(e){} }); readyResolvers = [];
      }
      post('character', { character: C.id });   // Ishara app
    }
    function select(id){
      if (!CAST[id]) id = DEF;
      wantId = id;
      if (A && A.id === id) return Promise.resolve(A);
      busy.style.opacity = '1';
      return fetchCharacter(id).then(function(C){
        if (wantId !== id) return C;
        busy.style.opacity = '0';
        stage(C);
        return C;
      }).catch(function(e){
        if (window.console) console.warn('[Ishara] character failed to load', id, e);
        busy.style.opacity = '0';
        if (!A) fail('character', e); else report('character', e);
      });
    }

    // ---------- render loop: sample the keyframes, then ease toward them ----------
    var LEAD = .32;   // seconds to travel from wherever the hands are into the first frame
    function sampleInto(frames, tt, out, names){
      var i = 0; while (i < frames.length - 1 && frames[i + 1].t <= tt) i++;
      var a = frames[i], b = frames[Math.min(i + 1, frames.length - 1)], s = 0;
      if (b !== a && b.t > a.t){ s = Math.max(0, Math.min(1, (tt - a.t) / (b.t - a.t))); s = s * s * (3 - 2 * s); }
      for (var j = 0; j < names.length; j++){ var n = names[j]; out[n].copy(a.q[n]); if (s > 0) out[n].slerp(b.q[n], s); }
    }
    // Ishara app: frame-rate meter for the performance budget (stats command)
    var fpsFrames = 0, fpsSince = performance.now(), fpsOn = false;
    var lastT = performance.now(), elapsed = 0;
    function animate(){
      requestAnimationFrame(animate);
      var now = performance.now(), dt = Math.min(.25, (now - lastT) / 1000), t; lastT = now; elapsed += dt; t = elapsed;
      if (!A || paused) return;   // Ishara app: `paused` replaces the prototype's offsetParent check
      if (!frozen) poseT += dt;
      var frames = A.POSEQ[activePose] || A.POSEQ.rest;
      sampleInto(frames, Math.max(0, poseT * speedK - LEAD), A.tgt, A.boneList);
      var k = 1 - Math.exp(-dt * (poseT * speedK < LEAD ? 10 : 18) * Math.min(1.6, speedK));
      if (frozen) k = 1;   // Ishara app: a frozen preview frame shows the exact keyframe pose
      for (var i = 0; i < A.boneList.length; i++){ var n = A.boneList[i]; A.cur[n].slerp(A.tgt[n], k); A.raw[n].quaternion.copy(A.cur[n]); }
      if (!reduce && !frozen){
        nudge('Spine1', XA, Math.sin(t * 1.25) * .01);
        nudge('Neck', YA, Math.sin(t * .37) * .02 + Math.sin(t * .13) * .015);
      }
      face(dt, t);
      renderer.render(scene, camera);
      if (fpsOn){ fpsFrames++; if (now - fpsSince >= 2000){ post('stats', { fps: fpsFrames * 1000 / (now - fpsSince) }); fpsFrames = 0; fpsSince = now; } }
    }
    function nudge(name, axisW, ang){
      var b = A && A.bones[name]; if (!b || !ang) return;
      var ax = axisW.clone().applyQuaternion(wquat(b.parent).invert());
      b.quaternion.premultiply(new Q().setFromAxisAngle(ax, ang));
    }
    animate();

    // ---------- public API ----------
    // Ishara app: the prototype's word → sign mapping (ALIASES, WORD_MAP,
    // poseNameFor) is gone: the app's catalogue maps words (sign rule 7,
    // Q-A5). play() takes a library label; noSign() is the prototype's
    // "no sign for this word" branch. Every sign that starts gets a
    // signStarted event and exactly one signEnded (interrupted or not).
    var readyResolvers = [], talkTimer = null, loopWord = null, current = null, playSeq = 0;
    function setPose(name){ activePose = name; poseT = 0; }
    function signLength(name){ var f = SIGNS[name].frames; return LEAD + f[f.length - 1].t + .25; }
    function endCurrent(interrupted){
      if (!current) return;
      var c = current; current = null;
      post('signEnded', { id: c.id, label: c.label, interrupted: !!interrupted });
    }
    function startSign(label, speed, loop, id){
      clearTimeout(talkTimer); loopWord = null; frozen = false;
      endCurrent(true);
      speedK = Math.max(.4, Math.min(2, speed || 1));
      if (!label || label === 'rest' || !SIGNS[label]){
        report('unknown_sign', label);
        return noSign(speed, id);
      }
      setPose(label); talking = true;
      var dur = signLength(label) * 1000 / speedK;
      if (loop) loopWord = { label: label, speed: speed, id: id };
      current = { id: id, label: label };
      post('signStarted', { id: id, label: label, ms: dur, loop: !!loop });
      talkTimer = setTimeout(function(){
        setPose('rest'); talking = false;
        endCurrent(false);
        if (loopWord) talkTimer = setTimeout(function(){ if (loopWord) startSign(loopWord.label, loopWord.speed, true, loopWord.id); }, 800);
      }, dur);
      return { known:true, ms: dur };
    }
    function noSign(speed, id){
      clearTimeout(talkTimer); loopWord = null; frozen = false;
      endCurrent(true);
      speedK = Math.max(.4, Math.min(2, speed || 1));
      // no sign for this word: stay in the ready position and let the caption carry it
      if (activePose !== 'rest') setPose('rest');
      talking = true;
      var ms = Math.max(360, 520 / speedK);
      current = { id: id, label: null };
      post('signStarted', { id: id, label: null, ms: ms, loop: false });
      talkTimer = setTimeout(function(){ talking = false; }, 420 / speedK);
      // Ishara app: the word's slot ends after `ms`, as the prototype's caller waits
      setTimeout(function(){ if (current && current.id === id) endCurrent(false); }, ms);
      return { known:false, ms: ms };
    }
    engine = {
      play: function(c){ return startSign(c.label, c.speed, c.loop, c.id); },
      noSign: function(c){ return noSign(c.speed, c.id); },
      stop: function(){ clearTimeout(talkTimer); loopWord = null; frozen = false; endCurrent(true); setPose('rest'); talking = false; },
      reframe: function(c){ captionPx = Math.max(0, +c.captionPx || 0); if (A) resize(); },
      setCharacter: function(c){
        return select(c.character).then(function(){ if (c.greet !== false && GREETING && activePose === 'rest' && !current) startSign(GREETING, .8, false, null); });
      },
      customize: function(st){
        if (!A || !st) return;
        var SK = ['#F3D9C4','#E8B894','#C98B62','#A26A45','#7A4A2E','#4E2F1E'], OUT = ['#E9E1C0','#3446C9','#24309A','#F2A33A','#1F7A4D','#C62B33'];
        if (st.skin != null){
          var ref = new T.Color(SK[2]), c = new T.Color(SK[st.skin] || SK[2]);
          var tint = new T.Color(Math.min(1.6, c.r / ref.r), Math.min(1.6, c.g / ref.g), Math.min(1.6, c.b / ref.b));
          A.skinMats.forEach(function(m){ if (m.userData.base) m.color.copy(m.userData.base).multiply(tint); });
        }
        if (st.outfit != null){
          var oc = new T.Color(OUT[st.outfit] || OUT[0]), ot = new T.Color(1, 1, 1).lerp(oc, st.outfit === 0 ? 0 : .7);
          A.outfitMats.forEach(function(m){ if (m.userData.base) m.color.copy(m.userData.base).multiply(ot); });
        }
      },
      // a sign nobody can see is not played on: it ends (interrupted)
      pause: function(){ paused = true; if (current){ clearTimeout(talkTimer); loopWord = null; endCurrent(true); setPose('rest'); talking = false; } },
      resume: function(){ paused = false; lastT = performance.now(); if (A) resize(); },
      setReduceMotion: function(c){ reduce = !!c.on; },
      stats: function(c){ fpsOn = !!c.on; fpsFrames = 0; fpsSince = performance.now(); },
      // the preview screen: freeze a sign at time t (s, at speed 1), seen from `view` degrees
      // (0 = front, -90 = from the signer's right side); `frozen: false` lets it play on.
      preview: function(c){
        viewDeg = +c.view || 0; resize();
        if (c.label == null) return;
        if (!SIGNS[c.label]) return report('unknown_sign', c.label);
        clearTimeout(talkTimer); loopWord = null; endCurrent(true);
        activePose = c.label; speedK = 1; poseT = (+c.t || 0) + LEAD; talking = false; frozen = c.frozen !== false;
      },
      whenReady: function(fn){ if (ready) fn(); else readyResolvers.push(fn); },
      _dbg: { T: T, SIGNS: SIGNS, CURL: CURL, SPREAD: SPREAD, SPLIT: SPLIT, WRAP: WRAP, REACH: REACH, camera: camera, scene: scene, renderer: renderer, avatar: function(){ return A; }, resize: resize,
        // contact check: for every landmark contact key, the distance (mm)
        // between the target and the real tip / palm after baking
        contacts: function(){
          var out = [];
          Object.keys(SIGNS).forEach(function(k){
            var R = READY_R, L = READY_L;
            SIGNS[k].frames.forEach(function(fr, i){
              if (!fr.R && !fr.L) return;   // a hold frame repeats the last pose
              if (fr.R) R = fr.R; if (fr.L) L = fr.L;
              if (!isContact(R) && !isContact(L)) return;
              bakeFrame(A, R, L, [0,0]);
              [[R, 'Right'], [L, 'Left']].forEach(function(e){
                if (!isContact(e[0])) return;
                var w = contactWant(A, e[1], e[0]), g = contactGot(A, e[1], e[0]);
                out.push({ sign: k, frame: i, side: e[1], want: w.toArray().map(function(v){ return +v.toFixed(3); }), got: g && g.toArray().map(function(v){ return +v.toFixed(3); }), mm: g ? Math.round(w.distanceTo(g) * 1000) : null });
              });
            });
          });
          resetBind(A);
          return out;
        },
        // pose the current character directly (tools only; the next frame
        // overwrites it): for measuring a shape without rebaking the signs
        bake: function(R, L){ if (!A || !R) return; bakeFrame(A, R, L || READY_L, [0,0]); A.root.updateMatrixWorld(true); },
        lm: function(){ return A && { lm: A.lm, handLen: A.handLen, len: A.len, chinZ: A.front(0, A.lm.chin), mouthZ: A.front(0, A.lm.mouth), chestZ: A.front(0, A.lm.chest) }; } }
    };
    window.__avatarEngine = engine;

    select(INIT.character || DEF).then(function(){
      if (!A) return;
      post('ready', { character: A.id, signs: Object.keys(SIGNS).filter(function(k){ return k !== 'rest'; }) });
      live = true;
      pending.splice(0).forEach(run);
      if (INIT.greet !== false && GREETING && activePose === 'rest' && !current) startSign(GREETING, .8, false, null);
      if (INIT.prefetch !== false) Object.keys(CAST).forEach(function(id, i){ setTimeout(function(){ if (!loaded[id]) fetchCharacter(id).catch(function(){}); }, 1200 + i * 600); });
    });
  }

  // ---------- Ishara app: commands from Flutter ----------
  var INIT = null;
  function run(c){
    try {
      var fn = engine && engine[c.cmd];
      if (typeof fn !== 'function' || c.cmd.charAt(0) === '_' || c.cmd === 'whenReady') return report('bad_command', c.cmd);
      var r = fn(c);
      if (r && typeof r.catch === 'function') r.catch(function(e){ report('command', e); });
    } catch(e){ report('command', e); }
  }
  function start(c){
    INIT = c;
    reduce = !!c.reduceMotion;
    Promise.all([
      fetch(c.cast).then(function(r){ if (!r.ok) throw new Error('HTTP ' + r.status + ' for ' + c.cast); return r.json(); }),
      fetch(c.library).then(function(r){ if (!r.ok) throw new Error('HTTP ' + r.status + ' for ' + c.library); return r.json(); })
    ]).then(function(d){
      // Ishara app: a hidden character (cast.json `hidden`) is not offered,
      // loaded or prefetched; asking for it shows the default (RB-1)
      CAST = {};
      Object.keys(d[0].characters).forEach(function(k){ if (!d[0].characters[k].hidden) CAST[k] = d[0].characters[k]; });
      DEF = CAST[d[0].default] ? d[0].default : Object.keys(CAST)[0];
      useLibrary(d[1]);
      loadAll();
    }).catch(function(e){ fail('data', e); });
  }
  window.__ishara = {
    receive: function(c){
      if (!c || typeof c.cmd !== 'string') return report('bad_command', c);
      if (c.cmd === 'init'){ if (!INIT) start(c); return; }
      if (live) run(c); else pending.push(c);
    }
  };
  post('loaded');
})();
