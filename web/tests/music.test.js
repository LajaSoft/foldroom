import test from 'node:test';
import assert from 'node:assert/strict';
import {createSoundtrack, SOUNDTRACK_CPS} from '../dist/soundtrack.js';
import {MusicPlayer} from '../dist/music.js';

globalThis.window = {addEventListener() {}, postMessage() {}};
globalThis.document = {addEventListener() {}, removeEventListener() {}, dispatchEvent() {}};
const strudel = await import('../dist/vendor/strudel-web-1.3.0.mjs');
strudel.miniAllStrings();

test('the complete trance pattern evaluates over all slow modulation periods', () => {
  const pattern = createSoundtrack(strudel);
  const sounds = new Set();
  for (const cycle of [0, 17, 23, 29, 37, 47, 64, 127]) {
    const events = pattern.queryArc(cycle, cycle + 1);
    assert.ok(events.length > 100);
    events.forEach(event => {
      sounds.add(event.value.s);
      for (const value of Object.values(event.value)) {
        if (typeof value === 'number') assert.ok(Number.isFinite(value));
      }
    });
    const kicks = events.filter(event => event.value.s === 'bd' && event.hasOnset());
    assert.equal(kicks.length, 4);
    assert.deepEqual(kicks.map(event => Number(event.whole.begin)), [cycle, cycle + .25, cycle + .5, cycle + .75]);
  }
  assert.deepEqual(sounds, new Set(['bd','cp','hh','oh','rim','lt','mt','sawtooth','supersaw','triangle','white']));
  const arp = pattern.queryArc(0, 1).filter(event => event.value.s === 'supersaw' && event.value.orbit === 4);
  assert.ok(arp.some(event => typeof event.value.note === 'number' && event.value.note >= 74), 'octave harmonic must actually transpose');
  assert.equal(SOUNDTRACK_CPS * 240, 138);
});

test('music initializes once, preloads local drums, controls master volume and pauses independently', async () => {
  const calls = [];
  const context = {currentTime: 0, resume: async () => calls.push('resume'), suspend: async () => calls.push('suspend')};
  const gain = {setTargetAtTime: value => calls.push(['gain', value])};
  const repl = {setCps: value => calls.push(['cps', value]), setPattern: async () => calls.push('pattern'), start: () => calls.push('start'), pause: () => calls.push('pause')};
  const runtime = {...strudel, initAudio: async () => calls.push('audio'), initStrudel: async ({prebake}) => {await prebake(); return repl;}, samples: async data => calls.push(['samples', Object.keys(data)]), loadBuffer: async (url, ctx) => {assert.equal(ctx, context);assert.ok(url.includes('/audio/'));}, getAudioContext: () => context, getSuperdoughAudioController: () => ({output: {destinationGain: {gain}}})};
  let loads = 0;
  const player = new MusicPlayer({onChange() {}, onError: error => assert.fail(error.message), loadRuntime: async () => {loads++; return runtime;}});
  await player.toggle();
  assert.equal(player.playing, true);
  player.setVolume(.5);
  assert.ok(calls.some(call => Array.isArray(call) && call[0] === 'gain' && call[1] === .2));
  await player.toggle();
  assert.equal(player.playing, false);
  assert.ok(calls.includes('pause') && calls.includes('suspend'));
  await player.toggle();
  assert.equal(player.playing, true);
  assert.equal(loads, 1);
  assert.equal(calls.filter(call => call === 'pattern').length, 1);
});

test('a failed library load can be retried', async () => {
  let errors = 0, attempts = 0;
  const player = new MusicPlayer({onChange() {}, onError() {errors++;}, loadRuntime: async () => {attempts++;throw new Error('offline');}});
  await player.toggle();
  await player.toggle();
  assert.equal(errors, 2);
  assert.equal(attempts, 2);
  assert.equal(player.busy, false);
});

test('mobile synthesis retains all layers and lowers supersaw voice counts', () => {
  const events=createSoundtrack(strudel,{mobile:true}).queryArc(0,1);
  const saws=events.filter(event=>event.value.s==='supersaw');
  assert.ok(saws.every(event=>event.value.unison<=3));
  assert.ok(events.some(event=>event.value.s==='bd'));
  assert.ok(events.some(event=>event.value.s==='sawtooth'));
});
