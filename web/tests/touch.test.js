import {zoomCameraDistance} from '../dist/overview.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {joystickAxes, attachTouchControls} from '../dist/touch.js';

test('joystick dead zone, directions and diagonal speed stay bounded', () => {
  assert.equal(joystickAxes(2, 2).forward, 0);
  assert.equal(joystickAxes(0, -46).forward, 1);
  assert.equal(joystickAxes(46, 0).side, 1);
  const diagonal = joystickAxes(200, -200);
  assert.ok(Math.abs(Math.hypot(diagonal.forward, diagonal.side) - 1) < 1e-12);
});

test('two fingers move and look independently, cancellation stops motion and only buttons carve', () => {
  class Surface {
    constructor() {this.events = {};this.style = {};this.dataset = {};}
    addEventListener(name, fn) {(this.events[name] ??= []).push(fn);}
    emit(name, data = {}) {for (const fn of this.events[name] ?? []) fn({preventDefault() {},stopPropagation() {},...data});}
    setPointerCapture() {}
    getBoundingClientRect() {return {left: 0,top: 0,width: 130,height: 130};}
  }
  const canvas = new Surface(), stick = new Surface(), knob = new Surface();
  const buttons = ['straight','up','down'].map(kind => {const button = new Surface();button.dataset.carve = kind;return button;});
  globalThis.window = new Surface();
  globalThis.document = Object.assign(new Surface(), {body: {},getElementById: id => id === 'joystick' ? stick : knob, querySelectorAll: () => buttons});
  let menuChanged;
  globalThis.MutationObserver = class {constructor(fn) {menuChanged = fn;} observe() {}};
  let active = true, motion, look, carved = [], zoom=0, zoomCalls=0;
  attachTouchControls({canvas,isActive: () => active,onMove: (forward,side) => {motion = [forward,side];},onLook: (x,y) => {look = [x,y];},onCarve: kind => carved.push(kind),onZoom: delta => {zoom=zoomCameraDistance(zoom,delta);zoomCalls++;}});
  stick.emit('pointerdown', {pointerId: 1,clientX: 65,clientY: 19});
  canvas.emit('pointerdown', {pointerId: 2,pointerType: 'touch',clientX: 200,clientY: 100});
  canvas.emit('pointermove', {pointerId: 2,clientX: 220,clientY: 90});
  assert.deepEqual(motion, [1,0]);
  assert.deepEqual(look, [20,-10]);
  assert.deepEqual(carved, []);
  // The joystick is independent: it must not turn a look finger into a pinch.
  assert.equal(zoomCalls,0);
  canvas.emit('pointerdown',{pointerId:4,pointerType:'touch',clientX:320,clientY:90});
  canvas.emit('pointermove',{pointerId:4,clientX:270,clientY:90});
  assert.ok(Math.abs(zoom-3)<1e-8,'closing fingers dollies outward');
  assert.deepEqual(look,[20,-10],'pinch must not also rotate or steer');
  canvas.emit('pointermove',{pointerId:4,clientX:320,clientY:90});
  assert.equal(zoom,0,'spreading fingers returns to first-person view');
  canvas.emit('pointercancel',{pointerId:4});
  canvas.emit('pointermove',{pointerId:2,clientX:225,clientY:90});
  assert.deepEqual(look,[5,0],'single-finger look resumes without a jump');
  canvas.emit('lostpointercapture',{pointerId:4});

  buttons.forEach(button => button.emit('click'));
  assert.deepEqual(carved, ['straight','up','down']);
  stick.emit('pointercancel', {pointerId: 1});
  assert.deepEqual(motion, [0,0]);
  stick.emit('pointerdown', {pointerId: 3,clientX: 111,clientY: 65});
  active = false; menuChanged();
  assert.deepEqual(motion, [0,0]);
  buttons[0].emit('click');
  assert.equal(carved.length, 3);
  canvas.emit('pointermove',{pointerId:2,clientX:240,clientY:90});
  assert.deepEqual(look,[5,0]);
  assert.equal(zoomCalls,2);
});
