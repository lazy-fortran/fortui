// Raw drawing input stays outside semantic composition and carries measured
// and provisional samples separately.
export class PointerSurface {
  constructor(canvas, callbacks = {}) {
    this.canvas = canvas;
    this.callbacks = callbacks;
    this.pointer = null;
    this.touches = new Map();
    this.abort = new AbortController();
    const options = { signal: this.abort.signal, passive: false };
    this.raw = 'onpointerrawupdate' in canvas;
    canvas.addEventListener('pointerdown', e => this.down(e), options);
    canvas.addEventListener(this.raw ? 'pointerrawupdate' : 'pointermove', e => this.move(e), options);
    // Gesture positions are still delivered when raw updates are unavailable
    // for touch on a host that exposes them for its pen.
    if (this.raw) canvas.addEventListener('pointermove', e => {
      if (e.pointerType === 'touch') this.touch(e);
    }, options);
    canvas.addEventListener('pointerup', e => this.end(e, false), options);
    canvas.addEventListener('pointercancel', e => this.end(e, true), options);
    canvas.addEventListener('lostpointercapture', e => this.end(e, true), options);
  }
  down(e) {
    if (e.pointerType === 'touch') {
      if (this.pointer?.type === 'pen') return;
      this.touches.set(e.pointerId, [e.clientX, e.clientY]);
      this.canvas.setPointerCapture(e.pointerId);
      this.callbacks.gesture?.(this.touches, 'start');
      return;
    }
    if (this.pointer || (e.button !== 0 && e.button !== 5)) return;
    e.preventDefault();
    this.touches.clear();
    if (this.callbacks.start?.(e) === false) return;
    this.pointer = { id: e.pointerId, type: e.pointerType, last: null, origin: e.timeStamp / 1000 };
    this.canvas.setPointerCapture(e.pointerId);
    this.deliver(e);
  }
  touch(e) {
    if (!this.touches.has(e.pointerId)) return;
    this.touches.set(e.pointerId, [e.clientX, e.clientY]);
    this.callbacks.gesture?.(this.touches, 'move');
  }
  move(e) {
    if (e.pointerType === 'touch') { this.touch(e); return; }
    if (e.pointerId !== this.pointer?.id) return;
    e.preventDefault();
    this.deliver(e);
  }
  deliver(e, final = false) {
    let measured = e.getCoalescedEvents?.() || [];
    if (!measured.length) measured = [e];
    else if (measured.at(-1).timeStamp < e.timeStamp) measured = [...measured, e];
    const samples = [];
    for (const p of measured) {
      const pressure = final && p.pressure === 0 ? (this.pointer.last?.pressure ?? 0.5)
        : (e.pointerType === 'mouse' ? 0.5 : p.pressure);
      const sample = { x: p.clientX, y: p.clientY, t: p.timeStamp / 1000 - this.pointer.origin,
        pressure, tiltX: p.tiltX, tiltY: p.tiltY };
      const last = this.pointer.last;
      if (last && sample.t < last.t) continue;
      if (last && sample.t === last.t && sample.x === last.x && sample.y === last.y
          && sample.pressure === last.pressure) continue;
      samples.push(sample);
      this.pointer.last = sample;
    }
    const predicted = final ? [] : (e.getPredictedEvents?.() || []).map(p => ({
      x: p.clientX, y: p.clientY, t: p.timeStamp / 1000 - this.pointer.origin, pressure: p.pressure,
    }));
    if (samples.length) this.callbacks.samples?.(samples, predicted);
  }
  end(e, cancelled) {
    if (this.touches.delete(e.pointerId)) {
      this.callbacks.gesture?.(this.touches, 'end');
      return;
    }
    if (e.pointerId !== this.pointer?.id) return;
    if (!cancelled) this.deliver(e, true);
    this.pointer = null;
    this.callbacks.end?.(cancelled);
    if (this.canvas.hasPointerCapture(e.pointerId)) this.canvas.releasePointerCapture(e.pointerId);
  }
  dispose() {
    if (this.pointer) this.callbacks.end?.(true);
    this.pointer = null;
    this.touches.clear();
    this.abort.abort();
  }
}
