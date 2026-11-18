import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PointerSurface } from '../web/fortui_surface.js';

class Canvas extends EventTarget {
  onpointerrawupdate = null;
  captured = new Set();
  setPointerCapture(id) { this.captured.add(id); }
  hasPointerCapture(id) { return this.captured.has(id); }
  releasePointerCapture(id) { this.captured.delete(id); }
}
function event(type, overrides = {}) {
  const e = new Event(type, { cancelable: true });
  const fields = { pointerId: 1, pointerType: 'pen', button: 0, clientX: 10,
    clientY: 20, timeStamp: 1000, pressure: 0.4, ...overrides };
  for (const [key, value] of Object.entries(fields)) Object.defineProperty(e, key, { value });
  return e;
}

test('coalesced measured samples, predictions and exact release stay separate', () => {
  const c = new Canvas(), measured = [], predicted = [], ends = [];
  const s = new PointerSurface(c, { samples: (a, b) => { measured.push(...a); predicted.push(...b); }, end: x => ends.push(x) });
  c.dispatchEvent(event('pointerdown'));
  const coalesced = () => [event('', { timeStamp: 1010, clientX: 20, pressure: 0.6 })];
  c.dispatchEvent(event('pointerrawupdate', { timeStamp: 1020, clientX: 30, pressure: 0.8,
    getCoalescedEvents: coalesced }));
  assert.deepEqual(measured.map(p => p.x), [10, 20, 30]);
  assert.deepEqual(predicted, []);
  c.dispatchEvent(event('pointermove', { timeStamp: 1020, clientX: 30, pressure: 0.8,
    getCoalescedEvents: coalesced,
    getPredictedEvents: () => [event('', { timeStamp: 1030, clientX: 40, pressure: 0.9 })] }));
  c.dispatchEvent(event('pointerup', { timeStamp: 1025, clientX: 35, pressure: 0 }));
  c.dispatchEvent(event('lostpointercapture'));
  assert.deepEqual(measured.map(p => p.x), [10, 20, 30, 35]);
  assert.equal(measured[0].t, 0);
  assert.deepEqual(measured.map(p => p.pressure), [0.4, 0.6, 0.8, 0.8]);
  assert.deepEqual(predicted.map(p => p.x), [40]);
  assert.deepEqual(ends, [false]);
  assert.equal(c.captured.size, 0);
  s.dispose();
});

test('a browser without raw updates delivers measurements and predictions together', () => {
  const c = new Canvas(), batches = [];
  delete c.onpointerrawupdate;
  const s = new PointerSurface(c, { samples: (a, b) => batches.push([a.map(p => p.x), b.map(p => p.x)]) });
  c.dispatchEvent(event('pointerdown'));
  c.dispatchEvent(event('pointermove', { timeStamp: 1020, clientX: 20,
    getPredictedEvents: () => [event('', { timeStamp: 1030, clientX: 30 })] }));
  assert.deepEqual(batches, [[[10], []], [[20], [30]]]);
  s.dispose();
});

test('palm touches do not interrupt a pen and cancellation ends once', () => {
  const c = new Canvas(), ends = [], gestures = [];
  const s = new PointerSurface(c, { end: x => ends.push(x), gesture: (_, phase) => gestures.push(phase) });
  c.dispatchEvent(event('pointerdown'));
  c.dispatchEvent(event('pointerdown', { pointerId: 2, pointerType: 'touch' }));
  c.dispatchEvent(event('pointercancel'));
  c.dispatchEvent(event('lostpointercapture'));
  assert.deepEqual(gestures, []);
  assert.deepEqual(ends, [true]);
  s.dispose();
  c.dispatchEvent(event('pointerdown'));
  assert.equal(c.captured.size, 0);
});

test('duplicate and stale positions cannot reorder the measured stream', () => {
  const c = new Canvas(), samples = [];
  const s = new PointerSurface(c, { samples: a => samples.push(...a) });
  c.dispatchEvent(event('pointerdown'));
  c.dispatchEvent(event('pointerrawupdate', { timeStamp: 1020, clientX: 30,
    getCoalescedEvents: () => [event('', { timeStamp: 900 }), event(''), event('', { timeStamp: 1010, clientX: 20 })] }));
  assert.deepEqual(samples.map(p => p.x), [10, 20, 30]);
  s.dispose();
});
