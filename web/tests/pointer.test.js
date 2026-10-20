import test from 'node:test';
import assert from 'node:assert/strict';
import {attachPointerControls} from '../dist/pointer.js';

class Surface {
  events = {};
  captures = new Set();
  addEventListener(name, fn) {(this.events[name] ??= []).push(fn);}
  emit(name, data = {}) {
    for (const fn of this.events[name] ?? []) fn({preventDefault() {}, ...data});
  }
  focus() {this.focused = true;}
  setPointerCapture(id) {this.captures.add(id);}
  hasPointerCapture(id) {return this.captures.has(id);}
  releasePointerCapture(id) {this.captures.delete(id);}
}
function setup(request) {
  const canvas = new Surface(), document = new Surface(), window = new Surface();
  canvas.requestPointerLock = request;
  document.exitPointerLock = () => {document.pointerLockElement = null; document.emit('pointerlockchange');};
  const state = {active: false, modes: [], errors: [], moves: []};
  const controls = attachPointerControls({canvas, document, window,
    isActive: () => state.active, setActive: value => {state.active = value;},
    onMode: mode => state.modes.push(mode), onError: error => state.errors.push(error),
    onLook: (dx, dy) => state.moves.push([dx, dy])});
  return {canvas, document, window, state, controls};
}

test('denied pointer lock starts playable drag mode and resumes without another request', async () => {
  let requests = 0;
  const error = new Error('Sandbox forbids pointer lock');
  const t = setup(() => {requests++; return Promise.reject(error);});
  await t.controls.enter();
  assert.equal(t.state.active, true);
  assert.equal(t.canvas.focused, true);
  assert.deepEqual(t.state.errors, [error]);
  assert.deepEqual(t.state.modes, ['drag']);
  t.document.emit('pointerlockerror');
  assert.equal(t.state.errors.length, 1, 'promise rejection and event are handled once');
  t.controls.pause();
  assert.equal(t.state.active, false);
  await t.controls.enter();
  assert.equal(t.state.active, true);
  assert.equal(requests, 1);
});

test('event-only denial and missing API both enable drag controls', async () => {
  for (const request of [() => undefined, undefined]) {
    const t = setup(request);
    await t.controls.enter();
    if (request) {
      assert.equal(t.state.active, false, 'wait for result event, not return value');
      t.document.emit('pointerlockerror');
    }
    assert.equal(t.state.active, true);
    assert.deepEqual(t.state.modes, ['drag']);
  }
});

test('successful lock keeps relative mouse look; unlock pauses and reacquisition works', async () => {
  const t = setup(() => Promise.resolve());
  await t.controls.enter();
  assert.equal(t.state.active, false);
  t.document.pointerLockElement = t.canvas;
  t.document.emit('pointerlockchange');
  t.document.emit('mousemove', {movementX: 12, movementY: -4});
  assert.deepEqual(t.state.moves, [[12, -4]]);
  assert.deepEqual(t.state.modes, ['locked']);
  t.document.exitPointerLock();
  assert.equal(t.state.active, false);
  t.document.emit('mousemove', {movementX: 20, movementY: 10});
  assert.equal(t.state.moves.length, 1);
  await t.controls.enter();
  t.document.pointerLockElement = t.canvas;
  t.document.emit('pointerlockchange');
  assert.equal(t.state.active, true);
});

test('drag look captures only middle mouse or Alt+left and stops on cancellation, blur and pause', async () => {
  const t = setup(undefined);
  await t.controls.enter();
  assert.equal(t.controls.isLookGesture({button: 0}), false);
  assert.equal(t.controls.isLookGesture({button: 2}), false);
  assert.equal(t.controls.isLookGesture({button: 0, shiftKey: true}), false);
  for (const gesture of [{button: 1}, {button: 0, altKey: true}]) {
    t.canvas.emit('pointerdown', {pointerId: 1, pointerType: 'mouse', clientX: 100, clientY: 100, ...gesture});
    t.canvas.emit('pointermove', {pointerId: 1, clientX: 120, clientY: 90});
    assert.deepEqual(t.state.moves.at(-1), [20, -10]);
    assert.equal(t.canvas.hasPointerCapture(1), true);
    t.canvas.emit('pointercancel', {pointerId: 1});
    assert.equal(t.canvas.hasPointerCapture(1), false);
  }
  const count = t.state.moves.length;
  t.canvas.emit('pointermove', {pointerId: 1, clientX: 300, clientY: 90});
  t.document.emit('mousemove', {movementX: 30, movementY: 20});
  assert.equal(t.state.moves.length, count);
  t.canvas.emit('pointerdown', {pointerId: 2, pointerType: 'mouse', button: 1, clientX: 1, clientY: 1});
  t.window.emit('blur');
  assert.equal(t.state.active, false);
  assert.equal(t.canvas.captures.size, 0);
  await t.controls.enter();
  t.document.hidden = true;
  t.document.emit('visibilitychange');
  assert.equal(t.state.active, false);
});

test('late pointer lock rejection or success cannot resume a paused game', async () => {
  let reject;
  const t = setup(() => new Promise((resolve, fail) => {reject = fail;}));
  const entering = t.controls.enter();
  t.controls.pause();
  reject(new Error('Late denial'));
  await entering;
  assert.equal(t.state.active, false);
  assert.deepEqual(t.state.modes, []);
  t.document.pointerLockElement = t.canvas;
  t.document.emit('pointerlockchange');
  assert.equal(t.document.pointerLockElement, null);
  assert.equal(t.state.active, false);
});
