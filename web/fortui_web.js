// Browser host for the fortui web backend (fortui_web.f90), linked with
// emcc --js-library. It owns the DOM: one absolutely positioned element per
// semantic node, reconciled by node id. Browser events are queued here and
// replayed into the runtime's input snapshot by poll.
addToLibrary({
  $FUI__deps: ['$UTF8ToString', '$stringToUTF8Array'],
  $FUI: {
    root: null,
    els: new Map(),
    events: [],
    wake: null,
    font: 'system-ui, -apple-system, "Segoe UI", sans-serif',
    keys: {
      Enter: 1, Escape: 2, Tab: 3, Backspace: 4, Delete: 5, Home: 6, End: 7,
      ArrowLeft: 8, ArrowRight: 9, ArrowUp: 10, ArrowDown: 11, PageUp: 12,
      PageDown: 13, ' ': 14, Insert: 15,
    },
    push: function (ev) {
      FUI.events.push(ev);
      FUI.wakeUp();
    },
    // Ends an idle wait without input, for asynchronous results that other
    // libraries deliver (they list '$FUI' in their __deps). The application
    // then composes a frame and can look at the result.
    wakeUp: function () {
      if (FUI.wake) { var w = FUI.wake; FUI.wake = null; w(); }
    },
    pointer: function (e, down) {
      var r = FUI.root.getBoundingClientRect();
      FUI.push([1, e.clientX - r.left, e.clientY - r.top, down ? 1 : 0]);
    },
    resize: function () {
      var r = FUI.root.getBoundingClientRect();
      FUI.push([4, r.width, r.height, window.devicePixelRatio || 1]);
    },
    install: function () {
      var root = FUI.root, down = false;
      root.addEventListener('pointerdown', function (e) {
        // The runtime owns focus, values and activation of controls; native
        // defaults would change them behind its back. Text stays selectable.
        if (e.target.closest('button, input, label, canvas')) e.preventDefault();
        down = true;
        try { root.setPointerCapture(e.pointerId); } catch (x) {}
        FUI.pointer(e, true);
      }, true);
      root.addEventListener('pointermove', function (e) { FUI.pointer(e, down); }, true);
      root.addEventListener('pointerup', function (e) {
        down = false;
        FUI.pointer(e, false);
      }, true);
      root.addEventListener('click', function (e) { e.preventDefault(); }, true);
      root.addEventListener('wheel', function (e) {
        e.preventDefault();
        var steps = e.deltaY / (e.deltaMode === 1 ? 3 : 100);
        FUI.push([3, Math.round(-steps), -steps, 0]);
      }, { passive: false, capture: true });
      window.addEventListener('keydown', function (e) {
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        var k = FUI.keys[e.key];
        if (k) FUI.push([2, k, 0, 0]);
        if (e.key.length === 1) FUI.text(e.key);
        if (k || e.key.length === 1) e.preventDefault();
      });
      window.addEventListener('resize', FUI.resize);
    },
    text: function (s) { FUI.push([5, s]); },
    create: function (kind) {
      var el;
      switch (kind) {
        case 2: case 5:
          el = document.createElement('button');
          if (kind === 5) el.setAttribute('role', 'tab');
          break;
        case 3:
          el = document.createElement('input'); el.type = 'range'; el.step = 'any';
          break;
        case 4:
          el = document.createElement('label');
          var box = document.createElement('input'); box.type = 'checkbox';
          el.appendChild(box); el.appendChild(document.createElement('span'));
          break;
        case 6: el = document.createElement('canvas'); break;
        case 8: el = document.createElement('input'); el.type = 'text'; break;
        default: el = document.createElement('div');
      }
      el.className = 'fui fui-k' + kind;
      el.style.position = 'absolute';
      el.style.boxSizing = 'border-box';
      el.style.font = 'inherit';
      el.style.margin = '0';
      return el;
    },
    update: function (el, f) {
      var kind = +f[0], flags = +f[6], text = f[14], body = f[15] || '';
      var s = el.style;
      s.left = f[2] + 'px'; s.top = f[3] + 'px';
      s.width = f[4] + 'px'; s.height = f[5] + 'px';
      s.fontSize = f[11] + 'px';
      s.fontWeight = (+f[10] >= 3) ? '600' : '';
      el.classList.toggle('fui-hover', (flags & 4) !== 0);
      el.classList.toggle('fui-focus', (flags & 8) !== 0);
      el.classList.toggle('fui-active', (flags & 16) !== 0);
      if ('disabled' in el) el.disabled = (flags & 2) !== 0;
      switch (kind) {
        case 2:
          if (el.textContent !== text) el.textContent = text;
          break;
        case 5:
          if (el.textContent !== text) el.textContent = text;
          el.setAttribute('aria-selected', (flags & 32) ? 'true' : 'false');
          break;
        case 3:
          el.min = f[8]; el.max = f[9]; el.value = f[7];
          break;
        case 4:
          el.firstChild.checked = (flags & 32) !== 0;
          if (el.lastChild.textContent !== text) el.lastChild.textContent = text;
          break;
        case 7:
          if (el.textContent !== body) el.textContent = body;
          s.whiteSpace = 'pre-wrap'; s.overflow = 'hidden';
          el.scrollTop = +f[13];
          break;
        case 8:
          if (el.value !== body) el.value = body;
          el.placeholder = text;
          break;
        case 6:
          break;
        default:
          if (el.textContent !== text) el.textContent = text;
          s.whiteSpace = 'nowrap'; s.overflow = 'hidden';
          s.textOverflow = (flags & 64) ? 'ellipsis' : 'clip';
      }
      if ((flags & 8) && document.activeElement !== el) {
        var target = kind === 4 ? el.firstChild : el;
        if (target.focus) target.focus({ preventScroll: true });
        if (kind === 8) {
          var c = utf16Index(body, +f[12]);
          try { el.setSelectionRange(c, c); } catch (x) {}
        }
      } else if (kind === 8 && (flags & 8)) {
        var c2 = utf16Index(body, +f[12]);
        try { el.setSelectionRange(c2, c2); } catch (x) {}
      }
      function utf16Index(str, bytes) {
        // The runtime counts UTF-8 bytes; the DOM counts UTF-16 units.
        var enc = new TextEncoder(), n = 0, i = 0;
        for (const ch of str) {
          n += enc.encode(ch).length;
          if (n > bytes) break;
          i += ch.length;
        }
        return i;
      }
    },
  },

  fortui_web_init__deps: ['$FUI'],
  fortui_web_init: function (ptr, n) {
    if (typeof document === 'undefined') return 1;
    var id = n > 0 ? UTF8ToString(ptr, n) : '';
    var host = id ? document.getElementById(id) : document.body;
    if (!host) return 1;
    var root = document.createElement('div');
    root.className = 'fui-root';
    root.style.position = 'relative';
    root.style.width = '100%';
    root.style.height = '100%';
    root.style.overflow = 'hidden';
    root.style.fontFamily = FUI.font;
    root.style.touchAction = 'none';
    host.appendChild(root);
    FUI.root = root;
    FUI.install();
    FUI.resize();
    return 0;
  },

  fortui_web_shutdown__deps: ['$FUI'],
  fortui_web_shutdown: function () {
    if (FUI.root) FUI.root.remove();
    FUI.root = null;
    FUI.els.clear();
  },

  fortui_web_wait__deps: ['$FUI'],
  fortui_web_wait__async: true,
  fortui_web_wait: function (forEvent) {
    return Asyncify.handleSleep(function (wakeUp) {
      if (forEvent && FUI.events.length === 0) {
        FUI.wake = wakeUp;
      } else {
        requestAnimationFrame(function () { wakeUp(); });
      }
    });
  },

  fortui_web_events__deps: ['$FUI'],
  fortui_web_events: function (evPtr, cap, textPtr, textCap) {
    var n = 0, used = 0, base = evPtr >> 2;
    while (FUI.events.length > 0 && n < cap) {
      var e = FUI.events[0];
      if (e[0] === 5) {
        var bytes = new TextEncoder().encode(e[1]);
        if (used + bytes.length > textCap) break;
        HEAPU8.set(bytes, textPtr + used);
        e = [5, used, bytes.length, 0];
        used += bytes.length;
      }
      FUI.events.shift();
      for (var j = 0; j < 4; j++) HEAPF32[base + 4 * n + j] = e[j];
      n++;
    }
    return n;
  },

  fortui_web_now: function () { return performance.now() / 1000; },

  fortui_web_present__deps: ['$FUI'],
  fortui_web_present: function (ptr, n) {
    var data = UTF8ToString(ptr, n);
    var seen = new Set(), anon = {};
    var records = data.split('\x1e');
    for (var i = 0; i < records.length; i++) {
      if (records[i] === '') continue;
      var f = records[i].split('\x1f');
      // Static text has no id; its order among id-less nodes keys it.
      var key = f[0] + ':' + f[1];
      if (f[1] === '') { anon[f[0]] = (anon[f[0]] || 0) + 1; key += '~' + anon[f[0]]; }
      var el = FUI.els.get(key);
      if (!el) {
        el = FUI.create(+f[0]);
        el.dataset.id = f[1];
        FUI.els.set(key, el);
        FUI.root.appendChild(el);
      }
      FUI.update(el, f);
      seen.add(key);
    }
    FUI.els.forEach(function (el, key) {
      if (!seen.has(key)) { el.remove(); FUI.els.delete(key); }
    });
  },

  fortui_web_measure__deps: ['$FUI'],
  fortui_web_measure: function (advPtr, ncp, fallbackPtr, linePtr) {
    var ctx = document.createElement('canvas').getContext('2d');
    var ref = 100, base = advPtr >> 2;
    var weights = ['400', '600'];
    for (var s = 0; s < 2; s++) {
      ctx.font = weights[s] + ' ' + ref + 'px ' + FUI.font;
      HEAPF32[(fallbackPtr >> 2) + s] = ctx.measureText('?').width / ref;
      for (var cp = 0; cp < ncp; cp++) {
        var w = (cp < 32 || (cp >= 0xD800 && cp <= 0xDFFF)) ? 0 :
          ctx.measureText(String.fromCodePoint(cp)).width / ref;
        HEAPF32[base + s * ncp + cp] = w;
      }
    }
    HEAPF32[linePtr >> 2] = 1.25;
  },
});
