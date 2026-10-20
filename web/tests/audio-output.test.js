import test from 'node:test';
import assert from 'node:assert/strict';
import {createAudioOutput} from '../dist/audio-output.js';

test('speaker EQ is reversible and the protective compressor remains after the master', () => {
  const param = () => ({value: 0,setTargetAtTime(value) {this.value = value;}});
  const node = () => ({gain: param(),frequency: param(),Q: param(),threshold: param(),knee: param(),ratio: param(),attack: param(),release: param(),connect(to) {this.target = to;},disconnect() {this.target = null;}});
  const filters = [], compressor = node(), input = node(), destination = node();
  const context = {currentTime: 0,destination,createBiquadFilter() {const result = node();filters.push(result);return result;},createDynamicsCompressor: () => compressor};
  const output = createAudioOutput(context, input, true);
  assert.equal(input.target, filters[0]);
  assert.equal(filters[1].target, compressor);
  assert.equal(compressor.target, destination);
  assert.equal(filters[0].gain.value, 4);
  assert.equal(filters[1].gain.value, -4);
  output.setSpeakerMode(false);
  assert.equal(filters[0].gain.value, 0);
  assert.equal(filters[1].gain.value, 0);
});
