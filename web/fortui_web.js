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
        root.classList.remove('fui-keyboard');
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
        // Focus rings matter after keyboard navigation, not after a click.
        if (e.key === 'Tab' || e.key.indexOf('Arrow') === 0) root.classList.add('fui-keyboard');
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        var k = FUI.keys[e.key];
        if (k) FUI.push([2, k, 0, 0]);
        if (e.key.length === 1) FUI.text(e.key);
        if (k || e.key.length === 1) e.preventDefault();
      });
      // Text that does not arrive as a key press (paste, phone keyboards,
      // autofill, drop) would change a DOM field behind the runtime's back;
      // it goes to the runtime instead. Line breaks at the ends of pasted
      // text are dropped, inner ones become spaces.
      root.addEventListener('paste', function (e) {
        var t = e.clipboardData ? e.clipboardData.getData('text/plain') : '';
        e.preventDefault();
        t = t.replace(/^[\r\n]+|[\r\n]+$/g, '').replace(/[\r\n]+/g, ' ');
        if (t) FUI.text(t);
      }, true);
      root.addEventListener('beforeinput', function (e) {
        if (e.inputType === 'insertCompositionText') return;
        e.preventDefault();
        if (e.inputType === 'deleteContentBackward') FUI.push([2, 4, 0, 0]);
        else if (e.inputType === 'deleteContentForward') FUI.push([2, 5, 0, 0]);
        else if (e.data) FUI.text(e.data);
        else if (e.dataTransfer) FUI.text(e.dataTransfer.getData('text/plain'));
      }, true);
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
      // The style token (1 body, 2 caption, 3 heading, 4 title) for page CSS.
      if (el.dataset.style !== f[10]) el.dataset.style = f[10];
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

  // Measuring a code point the page font lacks makes the browser search its
  // fallback fonts, about a millisecond each, so only the ranges ordinary
  // text uses are measured; the others advance like '?' (wide scripts from
  // U+2E80 by one em). The table is kept per font and device in
  // localStorage, so later visits skip the measuring.
  fortui_web_measure__deps: ['$FUI'],
  fortui_web_measure: function (advPtr, ncp, fallbackPtr, linePtr) {
    var ranges = [[0x20, 0x250], [0x370, 0x530], [0x2000, 0x20D0],
      [0x2100, 0x2400], [0x2500, 0x2600]];
    var key = 'fortui-metrics-v1:' + FUI.font + ':' + (window.devicePixelRatio || 1);
    var base = advPtr >> 2, n = 2 * ncp;
    var table = null;
    try {
      var saved = localStorage.getItem(key);
      if (saved) {
        var bytes = Uint8Array.from(atob(saved), function (c) { return c.charCodeAt(0); });
        if (bytes.length === 4 * (n + 2)) table = new Float32Array(bytes.buffer);
      }
    } catch (x) { table = null; }
    if (!table) {
      table = new Float32Array(n + 2);
      var ctx = document.createElement('canvas').getContext('2d');
      var ref = 100, weights = ['400', '600'];
      for (var s = 0; s < 2; s++) {
        ctx.font = weights[s] + ' ' + ref + 'px ' + FUI.font;
        var q = ctx.measureText('?').width / ref;
        table[n + s] = q;
        for (var cp = 0; cp < ncp; cp++) table[s * ncp + cp] = cp >= 0x2E80 ? 1 : q;
        for (var r = 0; r < ranges.length; r++) {
          for (var c = ranges[r][0]; c < Math.min(ranges[r][1], ncp); c++) {
            table[s * ncp + c] = ctx.measureText(String.fromCodePoint(c)).width / ref;
          }
        }
        for (var z = 0; z < 32; z++) table[s * ncp + z] = 0;
      }
      try {
        var str = '', u8 = new Uint8Array(table.buffer);
        for (var i = 0; i < u8.length; i += 0x8000) {
          str += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
        }
        localStorage.setItem(key, btoa(str));
      } catch (x) {}
    }
    HEAPF32.set(table.subarray(0, n), base);
    HEAPF32[fallbackPtr >> 2] = table[n];
    HEAPF32[(fallbackPtr >> 2) + 1] = table[n + 1];
    HEAPF32[linePtr >> 2] = 1.25;
  },
});
