// Browser host for the fortui web backend (fortui_web.f90), linked with
// emcc --js-library. Containers become flex boxes and controls native
// elements; the browser lays them out. Elements report what happens to them
// (activated, focused, edited, submitted) as semantic events, and the host
// calls the Fortran frame step only when something happened.
//
// Every element carries a stable data-key, so a page rendered by the server
// is adopted rather than rebuilt (no flash when the WebAssembly starts).
addToLibrary({
  $FUI__deps: ['$UTF8ToString'],
  $FUI: {
    root: null,
    els: new Map(),
    events: [],
    scheduled: false,
    started: false,
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
        if (el.tagName === 'BUTTON') FUI.host(H.activate, el);
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
      });
      root.addEventListener('input', function (e) {
        var t = e.target, el = t.closest('[data-id]');
        if (!el || (t.tagName !== 'INPUT' && t.tagName !== 'TEXTAREA')) return;
        if (t.type === 'checkbox') return;
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
        var k = FUI.key(e);
        if (!k) return;
        var claim = Module._fortui_web_key(k[0], k[1], k[2]);
        if (claim & 2) e.preventDefault();
        if (claim & 1) FUI.push([2, k[0], k[1], k[2]]);
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
      window.addEventListener('resize', FUI.resize);
    },
    tags: { 2: 'button', 3: 'input', 4: 'label', 5: 'button', 6: 'canvas', 8: 'input', 9: 'a',
      10: 'textarea' },
    create: function (kind, key) {
      var el = document.createElement(FUI.tags[kind] || 'div');
      if (kind === 3) { el.type = 'range'; el.step = 'any'; }
      if (kind === 8) el.type = 'text';
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
      FUI.mark(el, f[18] || '', f[19] || '');
      var px = f[11] + 'px';
      if (s.fontSize !== px) s.fontSize = px;
      FUI.size(s, +f[13], +f[4], inRow);
      if ('disabled' in el) el.disabled = (flags & 2) !== 0;
      if (kind === 2 || kind === 5 || kind === 6 || kind === 7 || kind === 10) s.height = f[5] + 'px';
      switch (kind) {
        case 2:
          if (el.textContent !== text) el.textContent = text;
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
          el.width = +f[4]; el.height = +f[5];
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
    box: function (el, b) {
      var kind = +b[1], s = el.style;
      el.className = 'fui-box ' + (kind === 2 || kind === 3 ? 'fui-row' : 'fui-col');
      var gap = b[4] + 'px';
      if (s.gap !== gap) s.gap = gap;
      s.minHeight = +b[5] > 0 ? b[5] + 'px' : '';
      if (kind === 4 && +b[6] >= 0) { s.width = b[6] + 'px'; s.flex = '0 0 auto'; }
      if ((b[7] || '') !== (el.dataset.box || '')) { if (b[7]) el.dataset.box = b[7]; else delete el.dataset.box; }
      FUI.mark(el, b[8] || '', b[9] || '');
    },
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

  // One timer for the next due frame (ms), replacing the previous one; -1 cancels.
  fortui_web_wake_after__deps: ['$FUI'],
  fortui_web_wake_after: function (ms) {
    if (FUI.timer) { clearTimeout(FUI.timer); FUI.timer = 0; }
    if (ms >= 0) FUI.timer = setTimeout(function () { FUI.timer = 0; FUI.request(); }, ms);
  },

  fortui_web_present__deps: ['$FUI'],
  fortui_web_present: function (ptr, n) {
    var records = UTF8ToString(ptr, n).split('\x1e');
    var boxes = [null], nodes = [], anon = {};
    for (var i = 0; i < records.length; i++) {
      if (records[i] === '') continue;
      var f = records[i].split('\x1f');
      if (f[0] === 'B') boxes.push(f); else nodes.push(f);
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
    var focus = FUI.toFocus, reveal = FUI.toReveal;
    FUI.toFocus = FUI.toReveal = null;
    // Also in a window without the focus: the element then has it when the
    // window gets it.
    if (focus && document.activeElement !== focus && focus.focus) focus.focus({ preventScroll: true });
    // ui_reveal: the least scrolling that shows the element, at once.
    if (reveal) reveal.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'instant' });
  },
});
