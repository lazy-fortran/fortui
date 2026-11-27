// Browser host for the fortui web backend (fortui_web.f90), linked with
// emcc --js-library. Containers become flex boxes and controls native
// elements; the browser lays them out. Elements report what happens to them
// (activated, focused, edited, submitted) as semantic events, and the host
// calls the Fortran frame step only when something happened.
//
// Every element carries a stable data-key, so a page rendered by the server
// is adopted rather than rebuilt (no flash when the WebAssembly starts).
addToLibrary({
  $FUI__deps: ['$UTF8ToString', '$FS'],
  $FUI: {
    root: null,
    els: new Map(),
    events: [],
    scheduled: false,
    started: false,
    fileSequence: 0,
    filePicker: null,
    // Characters typed after a taken press, until the next frame (type-ahead).
    ahead: null,
    HOST: { activate: 1, focus: 2, blur: 3, value: 4, submit: 5 },
    // Named keys as the runtime numbers them (KEY_* in fortui_input).
    KEYS: { Enter: 1, Escape: 2, Tab: 3, Backspace: 4, Delete: 5, Home: 6, End: 7, ArrowLeft: 8,
      ArrowRight: 9, ArrowUp: 10, ArrowDown: 11, PageUp: 12, PageDown: 13, ' ': 14, Insert: 15 },
    // A key press as [named key, flags, code point], or null for keys that are
    // none of the application's (modifiers alone, function keys). Flags: Ctrl
    // 1, Alt 2, Shift 4, Meta 8, 16 where Cmd is the command modifier, 32 a
    // repeat, and 256 times what the element with the focus does with keys
    // itself: 1 Enter and Space (a button), 2 also the navigation keys (a
    // slider), 3 typing (a field of one line), 4 everything (several lines, a
    // select, editable content).
    key: function (e) {
      var named = FUI.KEYS[e.key] || 0, code = 0;
      if (!named) {
        if (typeof e.key !== 'string' || Array.from(e.key).length !== 1) return null;
        code = e.key.codePointAt(0);
      }
      // AltGr types a character; it is not Ctrl with Alt.
      var typing = e.getModifierState && e.getModifierState('AltGraph');
      var flags = (e.ctrlKey && !typing ? 1 : 0) | (e.altKey && !typing ? 2 : 0) |
        (e.shiftKey ? 4 : 0) | (e.metaKey ? 8 : 0) | (e.repeat ? 32 : 0);
      // With a modifier, a key whose layout gives no ASCII character (Cyrillic,
      // Alt on macOS) is the letter or digit printed on it.
      var at = (flags & 11) && code > 127 && /^(Key[A-Z]|Digit[0-9])$/.test(e.code || '');
      if (at) code = e.code.slice(-1).toLowerCase().charCodeAt(0);
      if (/Mac|iPhone|iPad/.test(navigator.platform)) flags |= 16;
      var t = e.target, tag = t && t.tagName, uses = 0;
      if (tag === 'TEXTAREA' || tag === 'SELECT' || (t && t.isContentEditable)) uses = 4;
      else if (tag === 'INPUT') {
        if (/^(text|search|url|tel|email|password)$/.test(t.type)) uses = 3;
        else if (/^(checkbox|button|submit|reset|image|file)$/.test(t.type)) uses = 1;
        else uses = t.type === 'range' || t.type === 'radio' ? 2 : 4;
      } else if (tag === 'BUTTON' || tag === 'SUMMARY' || (tag === 'A' && t.hasAttribute('href'))) uses = 1;
      return [named, flags | (uses << 8), code];
    },
    // Frame scheduling: one animation frame per burst of events.
    request: function () {
      if (FUI.scheduled || !FUI.started) return;
      FUI.scheduled = true;
      requestAnimationFrame(FUI.step);
    },
    step: function () {
      FUI.scheduled = false;
      if (Module._fortui_web_step()) FUI.request();
    },
    push: function (ev) { FUI.events.push(ev); FUI.request(); },
    // For other libraries delivering asynchronous results (fetch): compose a
    // frame so the application can look at them.
    wakeUp: function () { FUI.request(); },
    host: function (kind, el, value) {
      var id = el && el.dataset.id;
      if (!id) return;
      FUI.push([5, kind, id + (value === undefined ? '' : '\x1f' + value)]);
    },
    resize: function () {
      FUI.push([4, FUI.root.clientWidth, window.innerHeight, window.devicePixelRatio || 1]);
    },
    install: function () {
      var root = FUI.root, H = FUI.HOST;
      root.addEventListener('click', function (e) {
        var el = e.target.closest('[data-id]');
        if (!el || !root.contains(el)) return;
        if (el.tagName === 'BUTTON') {
          if (el.hasAttribute('data-file-accept')) FUI.chooseFile(el);
          else FUI.host(H.activate, el);
        }
        // A plain click on a link is the application's to handle; with a
        // modifier or another button the browser opens the location itself.
        if (el.tagName === 'A' && e.button === 0 && !e.metaKey && !e.ctrlKey &&
          !e.shiftKey && !e.altKey) {
          e.preventDefault();
          FUI.host(H.activate, el);
        }
      });
      root.addEventListener('change', function (e) {
        var el = e.target.closest('[data-id]');
        if (el && e.target.type === 'checkbox') FUI.host(H.activate, el);
        if (el && el.tagName === 'SELECT') FUI.host(H.value, el, el.value);
      });
      root.addEventListener('input', function (e) {
        var t = e.target, el = t.closest('[data-id]');
        if (!el || (t.tagName !== 'INPUT' && t.tagName !== 'TEXTAREA')) return;
        if (t.type === 'checkbox' || t.type === 'file') return;
        t._reported = t.value;
        FUI.host(H.value, el, t.value);
      });
      root.addEventListener('focusin', function (e) {
        FUI.host(H.focus, e.target.closest('[data-id]'));
      });
      root.addEventListener('focusout', function (e) {
        FUI.host(H.blur, e.target.closest('[data-id]'));
      });
      // One path for keys. The runtime says whether the application wants a
      // press and whether the browser's own action must not happen: that is so
      // for the chords the last frame asked for (ui_shortcut), never for a key
      // the element with the focus uses itself; Escape always arrives.
      window.addEventListener('keydown', function (e) {
        // Keys of a composition belong to the input method.
        if (e.isComposing || e.keyCode === 229) return;
        var t = e.target;
        if (e.key === 'Enter' && t.tagName === 'INPUT' && t.type === 'text' && root.contains(t)) {
          FUI.host(H.submit, t.closest('[data-id]'));
        }
        if (e.key === 'Enter' && t.tagName === 'SELECT' && root.contains(t)) {
          e.preventDefault(); FUI.host(H.submit, t); return;
        }
        var k = FUI.key(e);
        if (!k) return;
        // Type-ahead: after a press the application took, characters typed
        // outside fields before its next frame are remembered (and handled as
        // usual). If that frame moves the focus into a text field, they are
        // typed there, so typing right after a shortcut loses nothing.
        var field = t && (t.tagName === 'TEXTAREA' || (t.tagName === 'INPUT' && /^(text|search|url|tel|email|password)$/.test(t.type)));
        if (FUI.ahead && !field && e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) FUI.ahead.push(e.key);
        var claim = Module._fortui_web_key(k[0], k[1], k[2]);
        if (claim & 2) e.preventDefault();
        if (claim & 1) {
          FUI.push([2, k[0], k[1], k[2]]);
          if (!field && !FUI.ahead) FUI.ahead = [];
        }
      });
      // Canvases are drawn by the application: they get pointer coordinates
      // in the runtime's own layout units.
      ['pointerdown', 'pointermove', 'pointerup'].forEach(function (type) {
        root.addEventListener(type, function (e) {
          var c = e.target.closest('canvas[data-id]');
          if (!c) return;
          var r = c.getBoundingClientRect();
          FUI.push([1, c._x + e.clientX - r.left, c._y + e.clientY - r.top,
            (type === 'pointerup' ? 0 : (e.buttons & 1))]);
        });
      });
      root.addEventListener('wheel', function (e) {
        if (!e.target.closest('canvas[data-id]')) return;
        e.preventDefault();
        var steps = e.deltaY / (e.deltaMode === 1 ? 3 : 100);
        FUI.push([3, Math.round(-steps), -steps, 0]);
      }, { passive: false });
      root.addEventListener('dblclick', function (e) {
        var el = e.target.closest('select[data-id]');
        if (el) FUI.host(H.submit, el);
      });
      window.addEventListener('resize', FUI.resize);
    },
    tags: { 2: 'button', 3: 'input', 4: 'label', 5: 'button', 6: 'canvas', 8: 'input', 9: 'a',
      10: 'textarea', 11: 'select' },
    // Canvas layers drawn with Canvas 2D: images are cached per store slot
    // and data version, lines and points are read from the Fortran arrays.
    colour: function (c) {
      return 'rgba(' + (c & 255) + ',' + ((c >>> 8) & 255) + ',' + ((c >>> 16) & 255) + ',' + (((c >>> 24) & 255) / 255) + ')';
    },
    array: function (Type, slot, which, n) {
      if (typeof _fortui_web_layer_ptr !== 'function' || n <= 0) return null;
      var p = _fortui_web_layer_ptr(slot, which);
      return p ? new Type(HEAPU8.buffer, p, n) : null;
    },
    drawCanvas: function (el, view, layers) {
      // The bitmap has device pixels; the element keeps its logical size.
      var dpr = window.devicePixelRatio || 1, w = el._lw || 1, h = el._lh || 1;
      var ctx = el.getContext('2d'), zoom = +view[2], px = +view[3], py = +view[4], fill = +view[5];
      if (el.width !== Math.round(w * dpr) || el.height !== Math.round(h * dpr)) {
        el.width = Math.round(w * dpr); el.height = Math.round(h * dpr);
      }
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, el.width, el.height);
      if (fill) { ctx.fillStyle = FUI.colour(fill); ctx.fillRect(0, 0, el.width, el.height); }
      ctx.setTransform(dpr * zoom, 0, 0, dpr * zoom, dpr * px, dpr * py);
      ctx.imageSmoothingEnabled = true; ctx.imageSmoothingQuality = 'high';
      el._images = el._images || new Map();
      var used = new Set();
      for (var i = 0; i < layers.length; i++) {
        var l = layers[i], kind = +l[2], slot = +l[3], version = l[4];
        if (kind === 4) {
          var iw = +l[5], ih = +l[6], key = slot, cached = el._images.get(key);
          used.add(key);
          if (!cached || cached.version !== version || cached.w !== iw || cached.h !== ih) {
            var px8 = FUI.array(Uint8ClampedArray, slot, 2, iw * ih * 4);
            if (!px8) continue;
            var c = cached && cached.canvas && cached.w === iw && cached.h === ih ? cached.canvas : document.createElement('canvas');
            c.width = iw; c.height = ih;
            c.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(px8), iw, ih), 0, 0);
            cached = { version: version, w: iw, h: ih, canvas: c };
            el._images.set(key, cached);
          }
          // Single pixels stretched to a rectangle stay flat (shading).
          ctx.imageSmoothingEnabled = iw > 1 || ih > 1;
          ctx.drawImage(cached.canvas, +l[7], +l[8], +l[9], +l[10]);
          ctx.imageSmoothingEnabled = true;
        } else {
          var vslot = +l[5], nv = +l[6], nc = +l[7], ni = +l[8], width = +l[9], ns = +l[10];
          var xy = FUI.array(Float32Array, vslot, 1, 2 * nv), rgba = FUI.array(Uint32Array, slot, 2, nc);
          if (!xy) continue;
          var colourOf = function (k) { return FUI.colour(rgba && rgba.length ? rgba[Math.min(k, rgba.length - 1)] : -1); };
          if (kind === 2) {
            var idx = FUI.array(Int32Array, slot, 4, ni);
            if (!idx) continue;
            ctx.lineWidth = width / zoom; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
            var paths = new Map();
            for (var s = 0; s + 1 < ni; s += 2) {
              var a = idx[s], b = idx[s + 1], col = colourOf(a), path = paths.get(col);
              if (!path) { path = new Path2D(); paths.set(col, path); }
              path.moveTo(xy[2 * a], xy[2 * a + 1]); path.lineTo(xy[2 * b], xy[2 * b + 1]);
            }
            paths.forEach(function (path, col) { ctx.strokeStyle = col; ctx.stroke(path); });
          } else if (kind === 1) {
            var sizes = FUI.array(Float32Array, slot, 3, ns), world = l[11] === '1', minPx = +l[12];
            for (var p = 0; p < nv; p++) {
              var r = (sizes ? sizes[Math.min(p, sizes.length - 1)] : width) / 2;
              if (!world) r = r / zoom;
              r = Math.max(r, minPx / zoom / 2);
              ctx.fillStyle = colourOf(p); ctx.beginPath(); ctx.arc(xy[2 * p], xy[2 * p + 1], r, 0, 2 * Math.PI); ctx.fill();
            }
          }
        }
      }
      el._images.forEach(function (_, key) { if (!used.has(key)) el._images.delete(key); });
    },
    create: function (kind, key) {
      var el = document.createElement(FUI.tags[kind] || 'div');
      if (kind === 3) { el.type = 'range'; el.step = 'any'; }
      if (kind === 8) el.type = 'text';
      if (kind === 11) { el.size = 12; el.setAttribute('aria-label', 'Files and folders'); }
      if (kind === 5) el.setAttribute('role', 'tab');
      if (kind === 4) {
        var box = document.createElement('input'); box.type = 'checkbox';
        el.appendChild(box); el.appendChild(document.createElement('span'));
      }
      if (kind === 2 || kind === 5) el.type = 'button';
      el.className = 'fui fui-k' + kind;
      el.dataset.key = key;
      return el;
    },
    // Width modes: 0 natural, 1 fixed, 2 fill the container.
    size: function (s, mode, width, inRow) {
      if (mode === 1) { s.width = width + 'px'; s.flex = '0 0 auto'; s.alignSelf = ''; }
      else if (mode === 2) {
        s.width = ''; s.minWidth = '0';
        if (inRow) { s.flex = '1 1 0'; s.alignSelf = ''; } else { s.flex = ''; s.alignSelf = 'stretch'; }
      } else { s.width = ''; s.flex = '0 0 auto'; s.alignSelf = ''; }
    },
    update: function (el, f, inRow) {
      var kind = +f[0], flags = +f[6], style = f[10], text = f[15], body = f[16] || '';
      var s = el.style;
      if (el.dataset.id !== f[1]) { if (f[1]) el.dataset.id = f[1]; else delete el.dataset.id; }
      if (el.dataset.style !== style) el.dataset.style = style;
      if (el.dataset.tone !== f[14]) el.dataset.tone = f[14];
      var emphasis = f[20] || '0';
      if ((el.dataset.emphasis || '0') !== emphasis) {
        if (emphasis !== '0') el.dataset.emphasis = emphasis; else delete el.dataset.emphasis;
      }
      FUI.mark(el, f[18] || '', f[19] || '');
      var px = f[11] + 'px';
      if (s.fontSize !== px) s.fontSize = px;
      FUI.size(s, +f[13], +f[4], inRow);
      if ('disabled' in el) el.disabled = (flags & 2) !== 0;
      if (kind === 2 || kind === 5 || kind === 6 || kind === 7 || kind === 10) s.height = f[5] + 'px';
      if (f[21] && f[21][0] === '1') el.setAttribute('data-file-accept', f[21].slice(1));
      else el.removeAttribute('data-file-accept');
      switch (kind) {
        case 2:
          if (el.textContent !== text) el.textContent = text;
          if (flags & 512) el.setAttribute('aria-pressed', (flags & 32) ? 'true' : 'false');
          else el.removeAttribute('aria-pressed');
          if (f[22]) { if (el.title !== f[22]) { el.title = f[22]; el.setAttribute('aria-label', f[22]); } }
          else if (el.title) { el.removeAttribute('title'); el.removeAttribute('aria-label'); }
          break;
        case 5:
          if (el.textContent !== text) el.textContent = text;
          el.setAttribute('aria-selected', (flags & 32) ? 'true' : 'false');
          break;
        case 3:
          el.min = f[8]; el.max = f[9];
          if (+f[7] !== +el._reported && +el.value !== +f[7]) el.value = f[7];
          break;
        case 4:
          el.firstChild.checked = (flags & 32) !== 0;
          if (el.lastChild.textContent !== text) el.lastChild.textContent = text;
          break;
        case 6:
          el._x = +f[2]; el._y = +f[3];
          el._lw = +f[4]; el._lh = +f[5];
          el.style.width = el._lw + 'px';
          break;
        case 11:
          if (el._body !== body) {
            el._body = body;
            el.replaceChildren(...body.trimEnd().split('\n').filter(Boolean).map(function (name, i) {
              var option = document.createElement('option');
              option.value = String(i + 1); option.textContent = name; return option;
            }));
          }
          el.value = String(Math.round(+f[7]));
          el.size = Math.max(3, Math.round(+f[5] / 24));
          break;
        case 7:
          if (el.textContent !== body) el.textContent = body;
          break;
        case 9:
          if (el.textContent !== text) el.textContent = text;
          if (el.getAttribute('href') !== body) el.setAttribute('href', body);
          el.classList.toggle('fui-ellipsis', (flags & 64) !== 0);
          break;
        case 8:
        case 10:
          // The field edits natively; the runtime's value is shown only when
          // the application changed it (it differs from what the field said).
          if (body !== el._reported && el.value !== body) { el.value = body; el._reported = body; }
          if (el.placeholder !== text) el.placeholder = text;
          break;
        default:
          FUI.text(el, text, f[17] || '');
          el.classList.toggle('fui-ellipsis', (flags & 64) !== 0);
      }
      // Applied once the element is in the page (fortui_web_present).
      if ((flags & 8) && kind !== 1 && kind !== 7) FUI.toFocus = kind === 4 ? el.firstChild : el;
      if (flags & 256) FUI.toReveal = el;
    },
    // The style name as data-look and the page address as the element's id.
    mark: function (el, look, anchor) {
      if ((el.dataset.look || '') !== look) { if (look) el.dataset.look = look; else delete el.dataset.look; }
      if (el.id !== anchor) { if (anchor) el.id = anchor; else el.removeAttribute('id'); }
    },
    // Plain text, or runs of rich text as spans (ends are UTF-8 byte offsets).
    text: function (el, text, runs) {
      if (el._text === text && el._runs === runs) return;
      el._text = text; el._runs = runs;
      if (!runs) { el.textContent = text; return; }
      var bytes = new TextEncoder().encode(text), dec = new TextDecoder(), at = 0;
      var frag = document.createDocumentFragment();
      runs.split(',').forEach(function (r) {
        var p = r.split(':'), end = Math.min(+p[0], bytes.length);
        if (end <= at) return;
        var span = document.createElement('span');
        span.textContent = dec.decode(bytes.subarray(at, end));
        if (p[1] !== '0') span.dataset.t = p[1];
        frag.appendChild(span);
        at = end;
      });
      if (at < bytes.length) frag.appendChild(document.createTextNode(dec.decode(bytes.subarray(at))));
      el.replaceChildren(frag);
    },
    chooseFile: function (el) {
      // click() stays inside the trusted button handler, including keyboard activation.
      if (FUI.filePicker) return;
      var input = document.createElement('input');
      input.type = 'file'; input.accept = el.getAttribute('data-file-accept') || '';
      input.hidden = true; document.body.appendChild(input);
      var token = ++FUI.fileSequence, id = el.dataset.id;
      FUI.filePicker = input;
      function finish() { input.remove(); if (FUI.filePicker === input) FUI.filePicker = null; }
      input.addEventListener('cancel', function () {
        if (token === FUI.fileSequence && FUI.root) FUI.host(FUI.HOST.value, el, '');
        finish();
      }, { once: true });
      input.addEventListener('change', async function () {
        var file = input.files[0];
        if (!file) { finish(); return; }
        try {
          var bytes = new Uint8Array(await file.arrayBuffer());
          if (token !== FUI.fileSequence || !FUI.root || !el.isConnected || el.dataset.id !== id) return;
          var dir = '/fortui-selected-' + token;
          FS.mkdir(dir);
          var path = dir + '/' + file.name.replace(/[\/\x00-\x1f]/g, '_');
          FS.writeFile(path, bytes);
          FUI.host(FUI.HOST.value, el, path);
        } catch (error) {
          FUI.host(FUI.HOST.value, el, '');
          console.error('File selection failed', error);
        } finally { finish(); }
      }, { once: true });
      input.click();
    },
    box: function (el, b) {
      var kind = +b[1], s = el.style;
      el.className = 'fui-box ' + (kind === 2 || kind === 3 ? 'fui-row' : 'fui-col') +
        (+b[5] > 0 ? ' fui-centred' : '') + (b[10] === '1' ? ' fui-wrap' : '');
      var gap = b[4] + 'px';
      if (s.gap !== gap) s.gap = gap;
      s.minHeight = +b[5] > 0 ? b[5] + 'px' : '';
      if (kind === 4 && +b[6] >= 0) { s.width = b[6] + 'px'; s.flex = '0 0 auto'; }
      if ((b[7] || '') !== (el.dataset.box || '')) { if (b[7]) el.dataset.box = b[7]; else delete el.dataset.box; }
      if (kind === 5) { el.setAttribute('role', 'dialog'); el.setAttribute('aria-modal', 'true'); el.setAttribute('aria-label', 'Open file'); }
      else { el.removeAttribute('role'); el.removeAttribute('aria-modal'); el.removeAttribute('aria-label'); }
      FUI.mark(el, b[8] || '', b[9] || '');
    },
  },

  fortui_system_appearance: function () {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 1 : 2;
  },
  // The application's theme as data-theme on the root ('' keeps the page's look).
  fortui_web_theme__deps: ['$FUI'],
  fortui_web_theme: function (ptr, n) {
    var name = n > 0 ? UTF8ToString(ptr, n) : '';
    if (!FUI.root) return;
    if (name) FUI.root.dataset.theme = name; else delete FUI.root.dataset.theme;
  },
  fortui_web_init__deps: ['$FUI', '$runtimeKeepalivePush'],
  fortui_web_init: function (ptr, n) {
    if (typeof document === 'undefined') return 1;
    var id = n > 0 ? UTF8ToString(ptr, n) : '';
    var host = id ? document.getElementById(id) : document.body;
    if (!host) return 1;
    // A page rendered by the server already holds the root and its elements.
    var root = host.querySelector(':scope > .fui-root');
    if (!root) {
      root = document.createElement('div');
      root.className = 'fui-root fui-box fui-col';
      host.appendChild(root);
    }
    root.querySelectorAll('[data-key]').forEach(function (el) { FUI.els.set(el.dataset.key, el); });
    // The program's main returns (and calls exit) once it has registered the
    // application; the runtime stays for the frames the browser drives.
    runtimeKeepalivePush();
    FUI.root = root;
    FUI.install();
    FUI.resize();
    // The first frame runs once main has registered the application.
    setTimeout(function () { FUI.started = true; FUI.request(); }, 0);
    return 0;
  },

  fortui_web_shutdown__deps: ['$FUI'],
  fortui_web_shutdown: function () {
    ++FUI.fileSequence;
    if (FUI.filePicker) { FUI.filePicker.remove(); FUI.filePicker = null; }
    if (FUI.root) FUI.root.remove();
    FUI.root = null;
    FUI.els.clear();
  },

  fortui_web_events__deps: ['$FUI'],
  fortui_web_events: function (evPtr, cap, textPtr, textCap) {
    var n = 0, used = 0, base = evPtr >> 2, enc = new TextEncoder();
    while (FUI.events.length > 0 && n < cap) {
      var e = FUI.events[0];
      if (e[0] === 5) {
        var bytes = enc.encode(e[2]);
        if (used + bytes.length > textCap) break;
        HEAPU8.set(bytes, textPtr + used);
        e = [5, e[1], used, bytes.length];
        used += bytes.length;
      }
      FUI.events.shift();
      for (var j = 0; j < 4; j++) HEAPF32[base + 4 * n + j] = e[j];
      n++;
    }
    return n;
  },

  fortui_web_now: function () { return performance.now() / 1000; },
  // Network service (fortui_web_net.f90): fetch and EventSource; each outcome
  // is copied into the Fortran queue and wakes a frame.
  $FUINET__deps: ['$FUI'],
  $FUINET: {
    open: new Map(),
    deliver: function (id, kind, failed, code, data) {
      var bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data;
      var p = Module._fortui_web_net_deliver(id, kind, failed, code, bytes.length);
      if (p && bytes.length) HEAPU8.set(bytes, p);
      FUI.wakeUp();
    },
  },
  fortui_web_net_start__deps: ['$FUINET', '$UTF8ToString'],
  fortui_web_net_start: function (id, m, nm, u, nu, b, nb, c, nc, stream) {
    var method = UTF8ToString(m, nm), url = UTF8ToString(u, nu);
    if (stream) {
      var es = new EventSource(url);
      FUINET.open.set(id, es);
      es.onopen = function () { FUINET.deliver(id, 3, 0, 0, ''); };
      es.onmessage = function (e) { FUINET.deliver(id, 2, 0, 0, e.data); };
      es.onerror = function () { FUINET.deliver(id, 4, es.readyState === 2 ? 1 : 0, 0, ''); };
      return;
    }
    var ctl = new AbortController(), init = { method: method, signal: ctl.signal };
    FUINET.open.set(id, ctl);
    if (method !== 'GET' && method !== 'HEAD') {
      init.body = HEAPU8.slice(b, b + nb);
      init.headers = { 'Content-Type': UTF8ToString(c, nc) };
    }
    fetch(url, init)
      .then(function (r) {
        return r.arrayBuffer().then(function (a) {
          if (FUINET.open.delete(id)) FUINET.deliver(id, 1, 0, r.status, new Uint8Array(a));
        });
      })
      .catch(function (e) {
        if (FUINET.open.delete(id)) FUINET.deliver(id, 1, 1, 0, String(e));
      });
  },
  fortui_web_net_cancel__deps: ['$FUINET'],
  fortui_web_net_cancel: function (id) {
    var h = FUINET.open.get(id);
    if (!h) return;
    FUINET.open.delete(id);
    if (h.close) h.close(); else h.abort();
  },
  fortui_web_locale__deps: ['$stringToUTF8', '$lengthBytesUTF8'],
  fortui_web_locale: function (buf, cap) {
    var tag = navigator.language || '';
    stringToUTF8(tag, buf, cap);
    return Math.min(lengthBytesUTF8(tag), cap - 1);
  },
  fortui_web_url_param__deps: ['$UTF8ToString', '$stringToUTF8', '$lengthBytesUTF8'],
  fortui_web_url_param: function (name, n, buf, cap) {
    var v = new URLSearchParams(location.search).get(UTF8ToString(name, n)) || '';
    stringToUTF8(v, buf, cap);
    return Math.min(lengthBytesUTF8(v), cap - 1);
  },
  fortui_web_offer_file__deps: ['$FUI'],
  fortui_web_offer_file: function (ptr) {
    var path = UTF8ToString(ptr), data = FS.readFile(path);
    var url = URL.createObjectURL(new Blob([data])), a = document.createElement('a');
    a.href = url; a.download = path.split('/').pop(); document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 30000);
  },

  // One timer for the next due frame (ms), replacing the previous one; -1 cancels.
  fortui_web_wake_after__deps: ['$FUI'],
  fortui_web_wake_after: function (ms) {
    if (FUI.timer) { clearTimeout(FUI.timer); FUI.timer = 0; }
    if (ms >= 0) FUI.timer = setTimeout(function () { FUI.timer = 0; FUI.request(); }, ms);
  },

  fortui_web_present__deps: ['$FUI'],
  fortui_web_present: function (ptr, n) {
    var records = UTF8ToString(ptr, n).split('\x1e');
    var boxes = [null], nodes = [], anon = {}, views = [], layers = [], nodeEls = [];
    for (var i = 0; i < records.length; i++) {
      if (records[i] === '') continue;
      var f = records[i].split('\x1f');
      if (f[0] === 'B') boxes.push(f);
      else if (f[0] === 'V') views.push(f);
      else if (f[0] === 'L') layers.push(f);
      else nodes.push(f);
    }
    var seen = new Set(), children = boxes.map(function () { return []; });
    var boxEl = [FUI.root];
    for (var b = 1; b < boxes.length; b++) {
      var key = 'b' + b, el = FUI.els.get(key);
      if (!el) { el = document.createElement('div'); el.dataset.key = key; FUI.els.set(key, el); }
      FUI.box(el, boxes[b]);
      boxEl.push(el);
      seen.add(key);
      children[+boxes[b][2]].push([2 * +boxes[b][3] + 1, b, el]);
    }
    for (var k = 0; k < nodes.length; k++) {
      var f2 = nodes[k], nkey = f2[0] + ':' + f2[1];
      if (f2[1] === '') { anon[f2[0]] = (anon[f2[0]] || 0) + 1; nkey += '~' + anon[f2[0]]; }
      var nel = FUI.els.get(nkey);
      if (!nel) { nel = FUI.create(+f2[0], nkey); FUI.els.set(nkey, nel); }
      var parent = +f2[12], pkind = parent > 0 ? +boxes[parent][1] : 1;
      FUI.update(nel, f2, pkind === 2 || pkind === 3);
      nodeEls[k + 1] = nel;
      seen.add(nkey);
      children[parent].push([2 * (k + 1), 0, nel]);
    }
    // Place every element in its container, in composition order; moving
    // only what is out of place keeps focus and selection where they are.
    for (var p = 0; p < children.length; p++) {
      var list = children[p].sort(function (a, c) { return a[0] - c[0] || a[1] - c[1]; });
      var host = boxEl[p];
      for (var q = 0; q < list.length; q++) {
        if (host.children[q] !== list[q][2]) host.insertBefore(list[q][2], host.children[q] || null);
      }
    }
    FUI.els.forEach(function (el, key) {
      if (!seen.has(key)) { el.remove(); FUI.els.delete(key); }
    });
    for (var v = 0; v < views.length; v++) {
      var cel = nodeEls[+views[v][1]];
      if (cel && cel.getContext) FUI.drawCanvas(cel, views[v], layers.filter(function (l) { return l[1] === views[v][1]; }));
    }
    var focus = FUI.toFocus, reveal = FUI.toReveal;
    FUI.toFocus = FUI.toReveal = null;
    // Also in a window without the focus: the element then has it when the
    // window gets it.
    if (focus && document.activeElement !== focus && focus.focus) focus.focus({ preventScroll: true });
    var ahead = FUI.ahead;
    FUI.ahead = null;
    if (ahead && ahead.length && focus && (focus.tagName === 'TEXTAREA' ||
        (focus.tagName === 'INPUT' && /^(text|search|url|tel|email|password)$/.test(focus.type)))) {
      // After this frame's step has returned to the browser.
      Promise.resolve().then(function () {
        focus.setRangeText(ahead.join(''), focus.selectionStart, focus.selectionEnd, 'end');
        focus.dispatchEvent(new Event('input', { bubbles: true }));
      });
    }
    // ui_reveal: the least scrolling that shows the element, at once.
    if (reveal) reveal.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'instant' });
  },
});
