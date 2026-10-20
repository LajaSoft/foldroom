// Post-mix processing leaves every pattern's filters and gain envelopes intact.
export function createAudioOutput(context, input, speakerMode = false) {
  const body = context.createBiquadFilter();
  body.type = 'peaking'; body.frequency.value = 200; body.Q.value = .65;
  const treble = context.createBiquadFilter();
  treble.type = 'highshelf'; treble.frequency.value = 3500;
  const compressor = context.createDynamicsCompressor();
  compressor.threshold.value = -8; compressor.knee.value = 6;
  compressor.ratio.value = 8; compressor.attack.value = .003; compressor.release.value = .18;
  input.disconnect();
  input.connect(body); body.connect(treble); treble.connect(compressor); compressor.connect(context.destination);
  const setSpeakerMode = enabled => {
    body.gain.setTargetAtTime(enabled ? 4 : 0, context.currentTime, .04);
    treble.gain.setTargetAtTime(enabled ? -4 : 0, context.currentTime, .04);
  };
  setSpeakerMode(speakerMode);
  return {setSpeakerMode};
}
