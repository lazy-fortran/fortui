// Drives the web demo in headless Chromium through the DevTools protocol with
// real pointer and keyboard events, and checks the resulting DOM.
//   node test/web_browser_test.mjs BUILD_DIR [SCREENSHOT.png]
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import { spawn, execFileSync } from 'node:child_process';
import { join, extname, resolve } from 'node:path';

const dir = resolve(process.argv[2]);
const shot = process.argv[3];
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.css': 'text/css' };
// The demo's first frame rendered natively by fortui_html, as a server would.
execFileSync('fpm', ['run', '--example', 'web_demo_ssr', '--', join(dir, 'ssr.html')], { stdio: 'ignore' });
const ssr = (await readFile(join(dir, 'ssr.html'))).toString().trim();
const server = createServer(async (req, res) => {
  try {
    if (req.url.startsWith('/?ssr') || req.url === '/?static') {
      // Every server element is marked before the WebAssembly starts. Other
      // than "/?ssr" the page has room to scroll below the frame; "/?static"
      // is the page without the application's script.
      let page = (await readFile(join(dir, 'index.html'))).toString();
      if (req.url !== '/?ssr') page = page.replace('</head>', '<style>#app { padding-bottom: 3000px; }</style></head>');
      if (req.url === '/?static') page = page.replace('<script src="web_demo.js"></script>', '');
      page = page.replace('<div id="app"></div>',
        `<div id="app">${ssr}</div><script>document.querySelectorAll('[data-key]').forEach((e) => { e.__ssr = 1; });
        window.__ssrCount = document.querySelectorAll('[data-key]').length;</script>`);
      res.writeHead(200, { 'content-type': 'text/html' });
      res.end(page);
      return;
    }
    // The network service of the demo: an echo and an event stream.
    if (req.url === '/api/echo' && req.method === 'POST') {
      let body = '';
      for await (const chunk of req) body += chunk;
      res.writeHead(200, { 'content-type': 'text/plain' });
      res.end('pong:' + body);
      return;
    }
    if (req.url === '/api/events') {
      res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-store' });
      res.write(': hello\n\ndata: tick\n\n');
      setTimeout(() => res.write('data: tock\n\n'), 100);
      return;
    }
    const path = req.url.split('?')[0];
    const body = await readFile(join(dir, path === '/' ? 'index.html' : path));
    res.writeHead(200, { 'content-type': types[extname(req.url)] || 'text/html' });
    res.end(body);
  } catch { res.writeHead(404); res.end(); }
}).listen(0, '127.0.0.1');
await new Promise((r) => server.once('listening', r));
const url = `http://127.0.0.1:${server.address().port}/`;

const browser = spawn(process.env.CHROME || 'chromium', ['--headless=new',
  '--remote-debugging-port=0', '--no-first-run', '--window-size=900,640',
  `--user-data-dir=${dir}/chrome-profile`, 'about:blank'], { stdio: ['ignore', 'ignore', 'pipe'] });
const wsUrl = await new Promise((resolve, reject) => {
  let err = '';
  browser.stderr.on('data', (d) => {
    err += d;
    const m = err.match(/ws:\/\/[^\s]+/);
    if (m) resolve(m[0]);
  });
  setTimeout(() => reject(new Error('browser did not start')), 15000);
});

const targets = await (await fetch(wsUrl.replace('ws://', 'http://').replace(/\/devtools.*/, '/json'))).json();
const ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r));
let seq = 0;
const pending = new Map();
const consoleLines = [];
ws.addEventListener('message', (e) => {
  const msg = JSON.parse(e.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  if (msg.method === 'Runtime.consoleAPICalled') consoleLines.push(msg.params.args.map((a) => a.value).join(' '));
  if (msg.method === 'Runtime.exceptionThrown') consoleLines.push('exception: ' + msg.params.exceptionDetails.text + ' ' + (msg.params.exceptionDetails.exception?.description || '').slice(0, 1200));
});
const send = (method, params = {}) => new Promise((resolve) => {
  const id = ++seq;
  pending.set(id, resolve);
  ws.send(JSON.stringify({ id, method, params }));
});
const evaluate = async (expr) => (await send('Runtime.evaluate', { expression: expr, returnByValue: true })).result.result.value;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(expr, what) {
  for (let i = 0; i < 100; i++) {
    if (await evaluate(expr)) return;
    await sleep(50);
  }
  throw new Error('timed out waiting for ' + what);
}
async function center(selector) {
  // A real pointer reaches only what is on screen.
  return evaluate(`(() => { const e = document.querySelector(${JSON.stringify(selector)});
    const b = e.getBoundingClientRect();
    if (b.bottom > innerHeight || b.top < 0) e.scrollIntoView({ block: 'center', behavior: 'instant' });
    const r = e.getBoundingClientRect();
    return [r.left + r.width / 2, r.top + r.height / 2]; })()`);
}
async function click(selector) {
  const [x, y] = await center(selector);
  for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased']) {
    await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
    await sleep(30);
  }
}
async function type(text) {
  for (const ch of text) {
    await send('Input.dispatchKeyEvent', { type: 'keyDown', key: ch, text: ch });
    await send('Input.dispatchKeyEvent', { type: 'keyUp', key: ch });
  }
}
// A key press; `more` holds modifiers (Alt 1, Ctrl 2, Meta 4, Shift 8), autoRepeat or text.
async function press(key, code, vk, more = {}) {
  await send('Input.dispatchKeyEvent', { type: 'keyDown', key, code, windowsVirtualKeyCode: vk, ...more });
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key, code, windowsVirtualKeyCode: vk });
}
const text = (selector) => evaluate(`document.querySelector(${JSON.stringify(selector)})?.textContent ?? null`);

let failed = 0;
function check(ok, what) {
  console.log((ok ? 'PASS ' : 'FAIL ') + what);
  if (!ok) failed++;
}

try {
  await send('Runtime.enable');
  await send('Page.enable');
  await send('Page.navigate', { url: url + '?site=cn' });
  await until(`!!document.querySelector('[data-id="count"]')`, 'first frame');
  // Network service: an event stream, a request, the language and the query.
  await until(`document.querySelector('[data-id="events"]')?.textContent === 'Events 2'`, 'event stream messages');
  check(true, 'event stream messages arrive in frames');
  await click('[data-id="fetch"]');
  await until(`document.querySelector('[data-id="fetched"]')?.textContent === 'Fetched 200 pong:ping'`, 'fetch answer');
  check(true, 'a POST request returns its status and body');
  check((await text('[data-id="site"]')) === 'Site cn', 'a parameter of the page address');
  check(await evaluate(`document.querySelector('[data-id="locale"]').textContent === 'Locale ' + navigator.language`),
    'the user language is the browser\'s');
  // Widgets: segmented choice, native picker, menu, chip, notification,
  // modal dialog, a chat that keeps its end in view, a virtual list, a grid.
  await click('[data-id="tabs#4"]');
  await until(`!!document.querySelector('[data-id="view/option#2"]')`, 'widgets tab');
  const state = () => text('[data-id="widget-state"]');
  check(await evaluate(`document.querySelectorAll('svg.fui-icon path').length > 5`), 'symbols are SVG strokes');
  await click('[data-id="view/option#2"]');
  await until(`document.querySelector('[data-id="widget-state"]').textContent.includes('Board')`, 'segment');
  check(await evaluate(`document.querySelector('[data-id="view/option#2"]').getAttribute('aria-pressed') === 'true'`),
    'a segment selects its option and shows it pressed');
  await evaluate(`(() => { const s = document.querySelector('select[data-id="colour"]'); s.value = '3';
    s.dispatchEvent(new Event('change', { bubbles: true })); })()`);
  await until(`document.querySelector('[data-id="widget-state"]').textContent.includes('Blue')`, 'picker');
  check(true, 'the platform picker of a drop-down chooses an option');
  await click('[data-id="more"]');
  await until(`!!document.querySelector('.fui-popup [data-id="more.list/item#4"]')`, 'menu');
  await click('[data-id="more.list/item#4"]');
  await until(`!document.querySelector('.fui-popup')`, 'menu closes');
  check((await state()).includes('command 4'), 'a menu command is chosen and the menu closes');
  await click('[data-id="more"]');
  await until(`!!document.querySelector('.fui-popup')`, 'menu again');
  await click('[data-id="widget-state"]');
  await until(`!document.querySelector('.fui-popup')`, 'menu dismissed');
  check(true, 'a press outside the menu closes it');
  await click('[data-id="save"]');
  await until(`!!document.querySelector('.fui-toasts[role="status"]')`, 'notification');
  check(true, 'a notification shows as a status');
  await click('[data-id="ask"]');
  await until(`!!document.querySelector('[role="dialog"][aria-label="Discard the branch?"]')`, 'modal');
  await click('[data-id="confirm/keep"]');
  await until(`!document.querySelector('[role="dialog"][aria-label="Discard the branch?"]')`, 'modal closes');
  check(true, 'a modal dialog has its name and closes by its button');
  for (let i = 0; i < 6; i++) { await click('[data-id="post"]'); await sleep(40); }
  await until(`!!document.querySelector('[data-id="chat/msg9"]')`, 'chat lines');
  await sleep(100);
  check(await evaluate(`(() => { const e = document.querySelector('.fui-scroll[data-box="chat"]');
    return e.scrollHeight > e.clientHeight && e.scrollTop + e.clientHeight >= e.scrollHeight - 2; })()`),
    'a sticking scroll container keeps the newest line in view');
  check(await evaluate(`document.querySelectorAll('.fui-scroll[data-box="many"] .fui-k1').length < 20`),
    'a virtual list of ten thousand rows composes a screenful');
  await evaluate(`document.querySelector('.fui-scroll[data-box="many"]').scrollTop = 5000 * 28`);
  await until(`!!document.querySelector('[data-id="many/row5001"]')`, 'virtual rows after scrolling');
  check(true, 'scrolled far, the virtual list composes the rows there');
  await click('[data-id="coils/head#1"]');
  await until(`document.querySelector('[data-id="coils/head#1"] svg') !== null`, 'sorted heading');
  check(true, 'a grid heading sorts and shows the direction');
  // Address, history, kept values and undo: the view is in the address,
  // Back returns to the one before, the colour is kept for the next visit,
  // Undo steps back through every change.
  await click('[data-id="view/option#3"]');
  await until(`location.search.includes('view=graph')`, 'view in the address');
  check(true, 'a view change puts the view into the address');
  await send('Runtime.evaluate', { expression: 'history.back()' });
  await until(`document.querySelector('[data-id="widget-state"]').textContent.includes('Board')`, 'Back');
  check(!(await evaluate('location.search')).includes('graph'), 'Back returns to the view before');
  check(await evaluate(`localStorage.getItem('fortui:colour') === '3'`), 'the chosen colour is kept in local storage');
  // Undo steps back through both views, then the colour.
  for (let i = 0; i < 3; i++) { await click('[data-id="undo"]'); await sleep(60); }
  await until(`document.querySelector('[data-id="widget-state"]').textContent.includes('Green')`, 'undo');
  check((await state()).includes('List') && await evaluate(`localStorage.getItem('fortui:colour') === '2'`),
    'Undo steps back through the views and then the colour');
  check(await evaluate(`document.querySelectorAll('[data-look="fui-avatar"]').length === 2 &&
    document.querySelector('[data-look="fui-avatar"]').textContent === 'CA'`), 'people show as initials in their colour');
  // Filled surfaces on the GPU: the nearer red square covers the blue one
  // composed after it; the canvas fill shows around them.
  await until(`!!document.querySelector('canvas[data-id="depth"]')`, 'depth canvas');
  await sleep(100);
  const depthPx = await evaluate(`(() => { const c = document.querySelector('canvas[data-id="depth"]');
    const g = c.getContext('2d'); const m = g.getImageData(c.width / 2, c.height / 2, 1, 1).data;
    const e = g.getImageData(2, 2, 1, 1).data; return [m[0], m[2], e[1]]; })()`);
  check(depthPx[0] > 150 && depthPx[1] < 50 && depthPx[2] > 200, 'a mesh draws with depth on the GPU: ' + depthPx);
  await click('[data-id="tabs#1"]');
  await until(`!!document.querySelector('[data-id="count"]')`, 'back to the first tab');
  // Pointer input: a pen with pressure, then two fingers spreading apart.
  const [sx, sy] = await center('canvas[data-id="swatch"]');
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: sx, y: sy, pointerType: 'pen' });
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x: sx, y: sy, button: 'left', clickCount: 1, pointerType: 'pen', force: 0.7, tiltX: 20 });
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: sx + 5, y: sy, button: 'left', buttons: 1, pointerType: 'pen', force: 0.7, tiltX: 20 });
  await until(`/^Pointer 1 70 /.test(document.querySelector('[data-id="felt"]')?.textContent || '')`, 'pen pressure');
  check(true, 'a pen reaches the canvas with its kind and pressure');
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: sx + 5, y: sy, button: 'left', clickCount: 1, pointerType: 'pen' });
  const touch = (type, pts) => send('Input.dispatchTouchEvent', { type, touchPoints: pts });
  await touch('touchStart', [{ x: sx - 10, y: sy, id: 1 }]);
  await touch('touchStart', [{ x: sx - 10, y: sy, id: 1 }, { x: sx + 10, y: sy, id: 2 }]);
  await touch('touchMove', [{ x: sx - 20, y: sy, id: 1 }, { x: sx + 20, y: sy, id: 2 }]);
  await touch('touchEnd', []);
  await until(`/ 200$/.test(document.querySelector('[data-id="felt"]')?.textContent || '')`, 'pinch');
  check(true, 'two fingers spreading apart pinch the canvas');
  // Type-ahead: characters typed right after a shortcut that moves the focus
  // into a field land in the field, before its frame has run.
  await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'k', code: 'KeyK', windowsVirtualKeyCode: 75, modifiers: 2 });
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'k', code: 'KeyK', windowsVirtualKeyCode: 75, modifiers: 2 });
  await type('zq');
  await until(`document.activeElement.dataset.id === 'name' && document.activeElement.value === 'zq'`, 'type-ahead');
  check(true, 'keys typed before the focus lands reach the field');
  check(await evaluate(`getComputedStyle(document.querySelector('[data-id="network"]') ?? document.getElementById('network')).alignItems === 'flex-start'`),
    'rows align their items to the top');
  await send('Page.navigate', { url: url + '?site=cn' });
  await until(`!!document.querySelector('[data-id="count"]')`, 'first frame again');

  check(await evaluate(`[...document.querySelectorAll('.fui-k1')].some((e) => e.textContent === 'FortUI in the browser')`),
    'static texts without id are realized separately');
  check((await text('[data-id="count"]')) === 'Clicked 0', 'buttons are DOM buttons with their labels');
  await until(`document.querySelector('[data-id="ticks"]')?.textContent === 'Ticks 3'`, 'timer ticks');
  check(true, 'timers advance the page without input');
  check(await evaluate(`document.querySelector('[data-id="count"]').tagName === 'BUTTON'`), 'button element');
  // Canvas layers drawn by the host: fill, a stretched image and a line,
  // through the canvas view (zoom 0.5), at device resolution.
  await until(`(() => { const c = document.querySelector('canvas[data-id="swatch"]');
    return c && c.width > 0 && c.getContext('2d').getImageData(c.width * 20 / 120 | 0, c.height * 20 / 60 | 0, 1, 1).data[0] > 200; })()`, 'canvas layers');
  const pixel = (x, y) => evaluate(`(() => { const c = document.querySelector('canvas[data-id="swatch"]');
    return [...c.getContext('2d').getImageData(Math.floor(c.width * ${x} / 120), Math.floor(c.height * ${y} / 60), 1, 1).data]; })()`);
  const near = (p, q) => p.slice(0, 3).every((v, i) => Math.abs(v - q[i]) <= 40);
  check(near(await pixel(5, 5), [30, 30, 30]), 'canvas fill');
  check(near(await pixel(20, 20), [255, 0, 0]) && near(await pixel(40, 20), [0, 0, 255]),
    'image layer stretched into its world rectangle');
  check(near(await pixel(60, 45), [0, 255, 0]), 'line layer at its world position');
  check(await evaluate(`(() => { const c = document.querySelector('canvas[data-id="swatch"]');
    return c.width === Math.round(120 * devicePixelRatio) && c.style.width === '120px'; })()`),
    'canvas bitmap at device pixels, element at logical size');
  check(await evaluate(`getComputedStyle(document.querySelector('[data-id="count"]')).fontFamily === getComputedStyle(document.querySelector('.fui-root')).fontFamily`),
    'controls use the page font the metrics were measured in');
  check(await evaluate(`(() => { const row = document.getElementById('controls'), one = document.querySelector('[data-id="one"]');
    return !!row && row.classList.contains('fui-row') && row.dataset.look === 'toolbar' && one.dataset.look === 'primary'
      && !one.id && !document.querySelector('[data-id="two"]').hasAttribute('data-look'); })()`),
    'a container and a control carry their look and anchor, others neither');
  const valueColour = `getComputedStyle(document.getElementById('value')).color`;
  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'light' }] });
  check(await evaluate(`document.getElementById('value').dataset.look === 'low' && document.getElementById('value').dataset.tone === '17'`) &&
    (await evaluate(valueColour)) === 'rgb(154, 103, 0)', 'the attention tone is amber on a light page');
  // The colour follows the scheme the page declares, not the system's preference.
  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'dark' }] });
  check((await evaluate(valueColour)) === 'rgb(154, 103, 0)', 'the attention tone stays dark amber on a light page of a dark system');
  await evaluate(`document.documentElement.style.colorScheme = 'dark'`);
  check((await evaluate(valueColour)) === 'rgb(210, 153, 34)', 'the attention tone is a lighter amber on a page of dark scheme');
  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'light' }] });
  check((await evaluate(valueColour)) === 'rgb(210, 153, 34)', 'and stays lighter on a dark page of a light system');
  await evaluate(`document.documentElement.style.colorScheme = ''`);
  await send('Emulation.setEmulatedMedia', { features: [] });
  await click('[data-id="two"]');
  await until(`document.getElementById('value')?.textContent === 'Value 90'`, 'value 90');
  check(await evaluate(`(() => { const e = document.getElementById('value');
    return !e.hasAttribute('data-look') && e.dataset.tone === '0' &&
      getComputedStyle(e).color === getComputedStyle(document.querySelector('.fui-root')).color; })()`),
    'a look and a tone that end are removed while the anchor stays');
  await click('[data-id="one"]');
  await until(`document.getElementById('value')?.dataset.look === 'low' && document.getElementById('value').textContent === 'Value 10'`, 'value 10');
  check(true, 'a look that returns is set again');
  await click('[data-id="count"]');
  await until(`document.querySelector('[data-id="count"]')?.textContent === 'Clicked 1'`, 'click');
  check(true, 'a pointer click activates the button');
  check(await evaluate(`document.querySelector('[data-id="more"]').tagName === 'A' && document.querySelector('[data-id="more"]').getAttribute('href') === '#more'`),
    'a link is an anchor with its location');
  await click('[data-id="more"]');
  await until(`document.querySelector('[data-id="count"]')?.textContent === 'Clicked 101'`, 'link');
  check(await evaluate(`location.hash === ''`), 'a plain click on a link goes to the application, not the browser');
  await click('[data-id="check"]');
  await until(`document.querySelector('[data-id="check"] input')?.checked === true`, 'checkbox');
  check(true, 'a click toggles the checkbox through the runtime');
  await click('[data-id$="#2"]');
  await until(`!!document.querySelector('[data-id="name"]')`, 'second tab');
  check(true, 'tabs switch the view');
  await click('[data-id="name"]');
  await type('Ada');
  await until(`[...document.querySelectorAll('.fui-k1')].some((e) => e.textContent === 'Hello, Ada!')`, 'typed text');
  check(true, 'typing reaches the text field');
  // The field is native: text arrives as the browser inserts it, as on paste.
  await send('Input.insertText', { text: ' Lovelace' });
  await until(`[...document.querySelectorAll('.fui-k1')].some((e) => e.textContent === 'Hello, Ada Lovelace!')`, 'pasted text');
  check(true, 'inserted text reaches the runtime');
  await click('[data-id$="#3"]');
  await until(`!!document.querySelector('[data-style="5"]')`, 'code lines');
  check(await evaluate(`getComputedStyle(document.querySelector('[data-style="5"]')).fontFamily.includes('mono')`) &&
    await evaluate(`getComputedStyle(document.querySelector('[data-style="5"]')).whiteSpace === 'pre-wrap'`),
    'code is monospaced and keeps its spaces');
  check(await evaluate(`(() => { const r = document.querySelector('[data-id="rich"]');
    return r.querySelector('span[data-t="5"]').textContent === 'call' && r.querySelector('span[data-t="8"]').textContent === '3.5'
      && r.querySelector('span[data-t="7"]').textContent === '! done' && r.textContent === 'call solve(n, 3.5) ! done'; })()`),
    'highlighted code arrives as toned spans');
  check(await evaluate(`document.documentElement.scrollWidth <= window.innerWidth`),
    'a long code line wraps instead of widening the page');
  check(await evaluate(`(() => { const root = document.querySelector('.fui-root');
    const box = [...root.children].find((e) => e.classList.contains('fui-box'));
    return !!box && Math.abs(box.offsetWidth - root.clientWidth) < 1; })()`),
    'a container spans the width of its column');
  check(await evaluate(`!!document.querySelector('[data-tone="1"]') && !!document.querySelector('[data-tone="2"]')`),
    'text carries its tone');
  check(await evaluate(`document.documentElement.scrollHeight > window.innerHeight + 200`),
    'a long page grows and the browser scrolls it');
  // Keys. A listener after the host's sees what the host prevented.
  await evaluate(`window.__keys = []; window.addEventListener('keydown',
    (e) => window.__keys.push(e.key + (e.defaultPrevented ? ' prevented' : ' default'))); document.activeElement.blur(); 1`);
  const lastKey = () => evaluate(`window.__keys[window.__keys.length - 1]`);
  const keys = () => text('[data-id="keys"]');
  const settled = async () => { await sleep(150); return keys(); };
  await press('j', 'KeyJ', 74);
  await until(`document.querySelector('[data-id="keys"]').textContent === 'Keys 1 j'`, 'shortcut j');
  check((await lastKey()) === 'j prevented', 'a registered key reaches the application and the browser does not act on it');
  await press('x', 'KeyX', 88);
  check((await settled()) === 'Keys 1 j' && (await lastKey()) === 'x default', 'a key nobody registered stays the browser\'s');
  await press('j', 'KeyJ', 74, { autoRepeat: true });
  await press('j', 'KeyJ', 74);
  await until(`document.querySelector('[data-id="keys"]').textContent === 'Keys 2 j'`, 'second j');
  check((await settled()) === 'Keys 2 j', 'a key repeat is not a second press');
  await press('k', 'KeyK', 75, { modifiers: 2 });
  await until(`document.activeElement.dataset.id === 'name'`, 'focus after mod+k');
  check((await keys()) === 'Keys 3 mod+k' && (await lastKey()) === 'k prevented',
    'Ctrl+K is the application\'s, and ui_focus moves the focus to the field it shows');
  await type('j');
  await until(`document.querySelector('[data-id="name"]').value === 'Ada Lovelacej'`, 'typing j');
  check((await settled()) === 'Keys 3 mod+k' && (await lastKey()) === 'j default',
    'in a text field a registered character is typed, not a shortcut');
  await press('ArrowDown', 'ArrowDown', 40);
  await until(`document.querySelector('[data-id="keys"]').textContent === 'Keys 4 ArrowDown'`, 'arrow in field');
  check((await lastKey()) === 'ArrowDown prevented', 'a text field gives ArrowDown to the application');
  await press('Enter', 'Enter', 13, { text: '\r' });
  await until(`document.querySelector('[data-id="keys"]').textContent === 'Keys 5 Enter'`, 'enter in field');
  check(true, 'a text field gives Enter to the application');
  await evaluate(`document.querySelector('[data-id="name"]').dispatchEvent(
    new KeyboardEvent('keydown', { key: 'Enter', isComposing: true, bubbles: true, cancelable: true })); 1`);
  check((await settled()) === 'Keys 5 Enter' && (await lastKey()) === 'Enter default',
    'Enter that ends an input method composition is not the application\'s');
  await click('[data-id="notes"]');
  await type('a');
  await press('Enter', 'Enter', 13, { text: '\r' });
  await type('b');
  await press('ArrowDown', 'ArrowDown', 40);
  await until(`document.querySelector('[data-id="notes"]').value === 'a\\nb'`, 'lines in the notes');
  check((await settled()) === 'Keys 5 Enter' && (await lastKey()) === 'ArrowDown default',
    'a field of several lines keeps Enter and the arrows');
  await press('Escape', 'Escape', 27);
  await until(`document.querySelector('[data-id="keys"]').textContent === 'Keys 6 Escape'`, 'escape in notes');
  check((await lastKey()) === 'Escape default', 'Escape reaches the application from any field and keeps its default there');
  await evaluate(`document.activeElement.blur(); window.scrollTo(0, 0); 1`);
  await press('g', 'KeyG', 71);
  await press('o', 'KeyO', 79);
  await until(`document.querySelector('[data-id="keys"]').textContent === 'Keys 7 g o'`, 'chord of two keys');
  await until(`!!document.querySelector('[data-id="last"]')`, 'end of the listing');
  check(await evaluate(`(() => { const r = document.querySelector('[data-id="last"]').getBoundingClientRect();
    return window.scrollY > 200 && r.top >= 0 && Math.abs(r.bottom - window.innerHeight) < 2; })()`),
    'two keys in a row are one chord, and ui_reveal scrolls its element to the nearest edge');
  await press('g', 'KeyG', 71);
  await press('x', 'KeyX', 88);
  await press('o', 'KeyO', 79);
  await until(`document.querySelector('[data-id="keys"]').textContent === 'Keys 8 o'`, 'o after g x');
  check((await settled()) === 'Keys 8 o', 'a key nobody registered between the two keys ends the chord');
  await evaluate(`for (let i = 0; i < 3; i++) document.body.dispatchEvent(
    new KeyboardEvent('keydown', { key: 'j', code: 'KeyJ', bubbles: true, cancelable: true })); 1`);
  await until(`document.querySelector('[data-id="keys"]').textContent === 'Keys 11 j'`, 'three j before a frame');
  check((await settled()) === 'Keys 11 j', 'presses of one chord that arrive before the next frame all count');
  // A Cyrillic layout reports another character for the key K; the window is not focused.
  check(await evaluate(`document.hasFocus = () => false; !document.body.dispatchEvent(
    new KeyboardEvent('keydown', { key: 'л', code: 'KeyK', ctrlKey: true, bubbles: true, cancelable: true }))`),
    'Ctrl with a key of another layout is prevented as the letter on the key');
  await until(`document.querySelector('[data-id="keys"]').textContent === 'Keys 12 mod+k'`, 'mod+k by key code');
  await until(`document.activeElement.dataset.id === 'name'`, 'focus in a window without focus');
  check(true, 'ui_focus moves the focus also while the window does not have it');
  await send('Page.navigate', { url });
  await until(`!!document.querySelector('[data-id="open-file"]')`, 'open button');
  await send('Page.setInterceptFileChooserDialog', { enabled: true });
  await click('[data-id="open-file"]');
  await until(`!!document.querySelector('input[type="file"]')`, 'trusted browser picker');
  const fixture = join(dir, 'chooser-test.png');
  await writeFile(fixture, Buffer.from([1, 2, 3, 4]));
  const root = await send('DOM.getDocument');
  const picker = await send('DOM.querySelector', { nodeId: root.result.root.nodeId, selector: 'input[type="file"]' });
  await send('DOM.setFileInputFiles', { nodeId: picker.result.nodeId, files: [fixture] });
  await until(`document.querySelector('[data-id="file-result"]')?.textContent === 'chooser-test.png: 4 bytes'`, 'owned browser file bytes');
  check(true, 'the trusted browser picker delivers an owned filename and bytes');
  await click('[data-id="open-file"]');
  await evaluate(`document.querySelector('input[type="file"]').dispatchEvent(new Event('cancel'))`);
  await until(`!document.querySelector('input[type="file"]')`, 'picker cancellation');
  check(true, 'cancellation releases the browser picker');
  await click('[data-id="appearance"]');
  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'dark' }] });
  await until(`document.querySelector('.fui-root').dataset.theme === 'fluent-dark'`, 'automatic dark theme');
  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'light' }] });
  await until(`document.querySelector('.fui-root').dataset.theme === 'fluent'`, 'automatic light theme');
  check(true, 'Fluent follows live browser light and dark preferences');
  await send('Emulation.setEmulatedMedia', { features: [] });
  // A page the server rendered: the WebAssembly adopts its elements.
  await send('Page.navigate', { url: url + '?ssr' });
  await until(`window.__ssrCount > 0 && !!document.querySelector('[data-id="count"]')`, 'server page');
  check(await evaluate(`document.querySelector('[data-id="count"]').textContent === 'Clicked 0'`),
    'the server page shows the first frame before the WebAssembly runs');
  await click('[data-id="count"]');
  await until(`document.querySelector('[data-id="count"]')?.textContent === 'Clicked 1'`, 'click on server page');
  check(await evaluate(`(() => { const all = [...document.querySelectorAll('[data-key]')];
    return all.length === window.__ssrCount && all.every((e) => e.__ssr === 1); })()`),
    'every server element is adopted, none rebuilt');
  // An address with a fragment: the browser scrolls the server's page to the
  // anchor without any script, and adoption leaves it there.
  await send('Page.navigate', { url: url + '?static#value' });
  await until(`window.__ssrCount > 0 && document.readyState === 'complete' && window.scrollY > 0`, 'static page');
  check(await evaluate(`!document.querySelector('script[src]') &&
    Math.abs(document.getElementById('value').getBoundingClientRect().top) < 2`),
    'an address scrolls to its anchor before any script runs');
  await send('Page.navigate', { url: url + '?ssr&tall#value' });
  await until(`window.__ssrCount > 0 && document.querySelector('[data-id="ticks"]')?.textContent === 'Ticks 3'`, 'adopted tall page');
  check(await evaluate(`(() => { const e = document.getElementById('value');
    const all = [...document.querySelectorAll('[data-key]')];
    return e.__ssr === 1 && e.dataset.look === 'low' && window.scrollY > 0 && Math.abs(e.getBoundingClientRect().top) < 2
      && all.length === window.__ssrCount && all.every((x) => x.__ssr === 1); })()`),
    'the adopted page keeps the anchor and stays scrolled to it');

  if (shot) {
    const png = await send('Page.captureScreenshot', { format: 'png' });
    await writeFile(shot, Buffer.from(png.result.data, 'base64'));
  }
} catch (e) {
  check(false, e.message);
} finally {
  if (consoleLines.length) console.log('console:\n  ' + consoleLines.join('\n  '));
  ws.close();
  browser.kill();
  server.close();
}
process.exit(failed ? 1 : 0);
