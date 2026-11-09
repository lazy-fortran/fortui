// Drives the web demo in headless Chromium through the DevTools protocol with
// real pointer and keyboard events, and checks the resulting DOM.
//   node test/web_browser_test.mjs BUILD_DIR [SCREENSHOT.png]
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { join, extname } from 'node:path';

const dir = process.argv[2];
const shot = process.argv[3];
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm' };
const server = createServer(async (req, res) => {
  try {
    const body = await readFile(join(dir, req.url === '/' ? 'index.html' : req.url));
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
  if (msg.method === 'Runtime.exceptionThrown') consoleLines.push('exception: ' + msg.params.exceptionDetails.text);
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
  return evaluate(`(() => { const r = document.querySelector(${JSON.stringify(selector)}).getBoundingClientRect();
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
const text = (selector) => evaluate(`document.querySelector(${JSON.stringify(selector)})?.textContent ?? null`);

let failed = 0;
function check(ok, what) {
  console.log((ok ? 'PASS ' : 'FAIL ') + what);
  if (!ok) failed++;
}

try {
  await send('Runtime.enable');
  await send('Page.enable');
  await send('Page.navigate', { url });
  await until(`!!document.querySelector('[data-id="count"]')`, 'first frame');
  check(await evaluate(`[...document.querySelectorAll('.fui-k1')].some((e) => e.textContent === 'FortUI in the browser')`),
    'static texts without id are realized separately');
  check((await text('[data-id="count"]')) === 'Clicked 0', 'buttons are DOM buttons with their labels');
  check(await evaluate(`document.querySelector('[data-id="count"]').tagName === 'BUTTON'`), 'button element');
  await click('[data-id="count"]');
  await until(`document.querySelector('[data-id="count"]')?.textContent === 'Clicked 1'`, 'click');
  check(true, 'a pointer click activates the button');
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
