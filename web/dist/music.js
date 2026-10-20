import {createAudioOutput} from './audio-output.js';
import {createSoundtrack, SOUNDTRACK_CPS} from './soundtrack.js';

const DRUMS = ['bd', 'cp', 'hh', 'oh', 'rim', 'lt', 'mt'];

export class MusicPlayer {
  constructor({onChange, onError, loadRuntime = () => import('./vendor/strudel-web-1.3.0.mjs')}) {
    this.onChange = onChange;
    this.onError = onError;
    this.loadRuntime = loadRuntime;
    this.volume = .35;
    this.mobile = globalThis.matchMedia?.('(any-pointer: coarse)').matches ?? false;
    this.speakerMode = this.mobile;
    this.context = null;
    this.output = null;
    this.playing = false;
    this.busy = false;
    this.ready = null;
    this.runtime = null;
    this.repl = null;
  }
  notify() {
    this.onChange({playing: this.playing, busy: this.busy, volume: this.volume});
  }
  async initialize() {
    const runtime = await this.loadRuntime();
    this.runtime = runtime;
    if(this.context)runtime.setAudioContext(this.context);
    // Called explicitly from the user's music button, including keyboard activation.
    await runtime.initAudio();
    this.repl = await runtime.initStrudel({
      prebake: async () => {
        const samples = {};
        await Promise.all(DRUMS.map(async drum => {
          const url = new URL(`audio/${drum}.wav`, import.meta.url).href;
          samples[`RolandTR909_${drum}`] = [url];
          // Warm the audio buffers so the first kick/hat are present from beat one.
          await runtime.loadBuffer(url, runtime.getAudioContext());
        }));
        await runtime.samples(samples);
      },
    });
    this.repl.setCps(SOUNDTRACK_CPS);
    await this.repl.setPattern(createSoundtrack(runtime, {mobile: this.mobile}), false);
    const context=runtime.getAudioContext();
    if(context.createDynamicsCompressor)this.output=createAudioOutput(context,runtime.getSuperdoughAudioController().output.destinationGain,this.speakerMode);
    this.setVolume(this.volume);
  }
  setSpeakerMode(enabled) {
    this.speakerMode=Boolean(enabled);
    this.output?.setSpeakerMode(this.speakerMode);
  }
  setVolume(value) {
    this.volume = Math.max(0, Math.min(1, Number(value) || 0));
    if (this.runtime) {
      const context = this.runtime.getAudioContext();
      const gain = this.runtime.getSuperdoughAudioController().output.destinationGain.gain;
      gain.setTargetAtTime(this.volume * .4, context.currentTime, .025);
    }
    this.notify();
  }
  async toggle() {
    if (this.busy) return;
    // Unlock on the original trusted tap, before importing or fetching audio.
    if(!this.context && globalThis.AudioContext){
      this.context=new AudioContext({latencyHint:'playback'});
    }
    if(this.context&&!this.playing)this.context.resume().catch(()=>{});
    this.busy = true;
    this.notify();
    try {
      if (!this.ready) {
        this.ready = this.initialize().catch(error => {
          this.ready = null;
          throw error;
        });
      }
      await this.ready;
      const context = this.runtime.getAudioContext();
      if (this.playing) {
        this.repl.pause();
        await context.suspend();
        this.playing = false;
        return;
      }
      await context.resume();
      await this.repl.start();
      this.playing = true;
    } catch (error) {
      this.repl?.pause();
      this.playing = false;
      this.onError(error);
    } finally {
      this.busy = false;
      this.notify();
    }
  }
}

export function attachMusicControls(toast) {
  const buttons = [...document.querySelectorAll('[data-music-toggle]')];
  const slider = document.getElementById('musicVolume');
  const status = document.getElementById('musicStatus');
  const output = document.getElementById('musicVolumeValue');
  const music = new MusicPlayer({
    onChange: ({playing, busy, volume}) => {
      for (const button of buttons) {
        button.disabled = busy;
        button.textContent = busy ? 'Loading music…' : playing ? 'Music: off' : 'Music: on';
        button.setAttribute('aria-pressed', String(playing));
      }
      status.textContent = busy ? 'Preparing sounds' : playing ? 'Progressive trance · 138 BPM' : 'Progressive trance · tap to play';
      output.value = `${Math.round(volume * 100)}%`;
    },
    onError: error => {
      console.error('Strudel music:', error);
      toast('Could not start the music. Tap the button to retry.');
    },
  });
  buttons.forEach(button => button.addEventListener('click', () => music.toggle()));
  slider.addEventListener('input', () => music.setVolume(slider.value));
  const speaker=document.getElementById('speakerMode');
  speaker.checked=music.speakerMode;
  speaker.addEventListener('change',()=>music.setSpeakerMode(speaker.checked));
  music.notify();
  return music;
}
