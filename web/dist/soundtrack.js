// User-provided continuous progressive trance, integrated 2026-10-03.
// All rhythmic layers, gains, effects and harmonic offsets are retained.
export const SOUNDTRACK_BPM = 138;
export const SOUNDTRACK_CPS = SOUNDTRACK_BPM / 4 / 60;

export function createSoundtrack({s, note, sine, cosine, saw, stack}, {mobile = false} = {}) {
  const kick = s('bd*4').bank('RolandTR909')
    .gain(sine.slow(47).range(.8, .2)).room('[.82 .1 .33]');
  const clap = s('[~ cp]*2').bank('RolandTR909').gain(.29).room(.12).orbit(7);
  const hat16 = s('hh*16').bank('RolandTR909')
    .gain(saw.slow(45).range('[.08 .18 .11 .22]*[5 4]', .5)).hpf(6000).orbit(2);
  const openHat = s('oh(3,8,1)').bank('RolandTR909')
    .gain(sine.slow(29).range(.07, .21)).late(sine.slow(37).range(0, 1 / 96)).hpf(5200).orbit(2);

  const perc3 = s('rim').euclidRot(3, 8, 1).bank('RolandTR909')
    .gain(sine.slow(17).range(.025, .13)).pan(.27).orbit(3);
  const perc5 = s('lt').euclidRot(5, 16, 3).bank('RolandTR909')
    .gain(cosine.slow(23).range(.015, .13)).pan(.73).orbit(3);
  const perc7 = s('mt').euclidRot(7, 16, 6).bank('RolandTR909')
    .gain(sine.slow(37).range(.01, .085)).pan(sine.slow(31).range(.38, .62)).orbit(3);
  const perc9 = s('rim').euclidRot(9, 32, 11).bank('RolandTR909')
    .gain(cosine.slow(29).range(.005, .065)).late(sine.slow(41).range(0, 1 / 128)).room(.18).orbit(3);

  const bassNotes = note(`
    [~
      <d2 bb1 f2 c2>
      <d2 bb1 f2 c2>
      <d2 bb1 f2 c2>
    ]*4
  `);
  const bass = bassNotes.s('sawtooth').lpf(sine.slow(32).range(290, 390))
    .lpq(cosine.slow(23).range(5.5, 8)).lpenv(sine.slow(19).range(2.8, 3.8))
    .lpd(.085).decay(.125).sustain(0).release(.035).ftype('24db').distort('1.25:.1').gain(.54);
  const bassHarmonic = note('<d3 bb2 f3 c3>').struct('x(3,16,7)').s('sawtooth')
    .lpf(520).lpq(5).decay(.07).sustain(0).release(.025).gain(sine.slow(37).range(0, .085));

  const arpNotes = note(`
  <
    [d4 a4 f4 a4 d5 a4 f4 a4]*2
    [bb3 f4 d4 f4 bb4 f4 d4 f4]*2
    [f4 c5 a4 c5 f5 c5 a4 c5]*2
    [c4 g4 e4 g4 c5 g4 e4 g4]*2
  >
  `);
  const arp = arpNotes.s('supersaw').unison(mobile ? 2 : 4).detune(.15).spread(.72)
    .lpf(sine.slow(64).range(1050, 4800)).lpq(cosine.slow(29).range(1.5, 4))
    .decay(.14).sustain(.035).release(.11).gain('[.055 .21 .24 .19]*4')
    .off(3 / 16, x => x.add(note(12)).gain(sine.slow(23).range(0, .115)))
    .off(5 / 16, x => x.add(note(7)).gain(cosine.slow(37).range(0, .055)))
    .delay(.19).delaytime(.375).delayfeedback(.24).room(.27).orbit(4);

  const pluck5 = note('<d5 bb4 f5 c5>').struct('x(5,16,2)').s('triangle')
    .lpf(sine.slow(29).range(1600, 5100)).decay(.095).sustain(0).release(.12)
    .delay(.27).delaytime(.375).delayfeedback(.29).gain(sine.slow(31).range(.015, .115)).pan(.31).orbit(5);
  const pluck7 = note('<a4 f4 c5 g4>').struct('x(7,16,5)').s('triangle')
    .lpf(cosine.slow(37).range(1200, 4300)).decay(.075).sustain(0).release(.1)
    .delay(.21).delaytime(.25).delayfeedback(.26).gain(cosine.slow(31).range(.008, .075)).pan(.69).orbit(5);

  const pad = note(`
  <
    [d3,f3,a3]
    [bb2,d3,f3]
    [f3,a3,c4]
    [c3,e3,g3]
  >
  `).s('supersaw').unison(mobile ? 3 : 5).detune(.105).spread(.9)
    .attack(.35).decay(.75).sustain(.5).release(1.7).lpf(sine.slow(64).range(650, 2600))
    .gain(sine.slow(47).range(.055, .54)).room(.68).orbit(6);

  const motif = note(`
  <
    [a4 ~ c5 ~ d5 ~ a4 ~]
    [f4 ~ a4 ~ bb4 ~ f4 ~]
    [c5 ~ a4 ~ f4 ~ a4 ~]
    [g4 ~ e4 ~ c4 ~ e4 ~]
  >
  `).s('supersaw').unison(mobile ? 2 : 3).detune(.08).spread(.65)
    .lpf(sine.slow(43).range(1700, 5000)).decay(.18).sustain(.025).release(.3)
    .gain(sine.slow(64).range(.015, .145))
    .off(3 / 8, x => x.add(note(12)).gain(cosine.slow(29).range(0, .045)))
    .delay(.37).delaytime(.375).delayfeedback(.39).room(.42).orbit(7);
  const air = s('white').hpf(sine.slow(64).range(5000, 9500)).lpf(12500)
    .gain(sine.slow(64).range(.002, .025)).room(.3).orbit(8);

  return stack(kick, clap, hat16, openHat, perc3, perc5, perc7, perc9,
    bass, bassHarmonic, arp, pluck5, pluck7, pad, motif, air);
}
