// Web Audio API Engine for interactive Mac Dynamic Notch
// Generates ambient lofi & electronic beats with real AnalyserNode for audio visualization

class AudioEngine {
  private ctx: AudioContext | null = null;
  private isPlaying = false;
  private currentTrackId = 'track-1';
  private timerId: number | null = null;
  private analyser: AnalyserNode | null = null;
  private masterGain: GainNode | null = null;
  private volume = 0.75;
  private soundEffectsEnabled = true;

  // Track state
  public currentTime = 14;
  public duration = 186; // 3:06
  private tempo = 82; // BPM
  private beatStep = 0;

  private onTickCallback?: (time: number, isPlaying: boolean) => void;

  private initContext() {
    if (!this.ctx) {
      const AudioCtx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      this.ctx = new AudioCtx();
      this.analyser = this.ctx.createAnalyser();
      this.analyser.fftSize = 64;
      this.masterGain = this.ctx.createGain();
      this.masterGain.gain.value = this.volume;
      this.masterGain.connect(this.ctx.destination);
      this.analyser.connect(this.masterGain);
    }
    if (this.ctx.state === 'suspended') {
      this.ctx.resume();
    }
  }

  public setVolume(val: number) {
    this.volume = Math.max(0, Math.min(1, val));
    if (this.masterGain && this.ctx) {
      this.masterGain.gain.setValueAtTime(this.volume, this.ctx.currentTime);
    }
  }

  public getVolume() {
    return this.volume;
  }

  public setSoundEffects(enabled: boolean) {
    this.soundEffectsEnabled = enabled;
  }

  public getFrequencyData(): Uint8Array {
    if (!this.analyser) {
      return new Uint8Array(16).fill(0);
    }
    const data = new Uint8Array(this.analyser.frequencyBinCount);
    this.analyser.getByteFrequencyData(data);
    return data;
  }

  public onTick(cb: (time: number, isPlaying: boolean) => void) {
    this.onTickCallback = cb;
  }

  public play(trackId?: string) {
    this.initContext();
    if (trackId && trackId !== this.currentTrackId) {
      this.currentTrackId = trackId;
      this.currentTime = 0;
      this.beatStep = 0;
    }
    this.isPlaying = true;
    this.startScheduler();
    this.playHaptic('expand');
  }

  public pause() {
    this.isPlaying = false;
    if (this.timerId !== null) {
      window.clearInterval(this.timerId);
      this.timerId = null;
    }
    this.onTickCallback?.(this.currentTime, false);
    this.playHaptic('click');
  }

  public togglePlay(trackId?: string) {
    if (this.isPlaying) {
      this.pause();
    } else {
      this.play(trackId);
    }
    return this.isPlaying;
  }

  public seek(seconds: number) {
    this.currentTime = Math.max(0, Math.min(this.duration, seconds));
    this.onTickCallback?.(this.currentTime, this.isPlaying);
  }

  public getIsPlaying() {
    return this.isPlaying;
  }

  // Soft haptic Apple UI audio cues
  public playHaptic(type: 'click' | 'expand' | 'notification' | 'snap' | 'ding') {
    if (!this.soundEffectsEnabled) return;
    try {
      this.initContext();
      if (!this.ctx) return;
      const now = this.ctx.currentTime;
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();

      osc.connect(gain);
      gain.connect(this.ctx.destination);

      if (type === 'click') {
        osc.type = 'sine';
        osc.frequency.setValueAtTime(1200, now);
        osc.frequency.exponentialRampToValueAtTime(300, now + 0.04);
        gain.gain.setValueAtTime(0.06, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.04);
        osc.start(now);
        osc.stop(now + 0.04);
      } else if (type === 'expand') {
        osc.type = 'sine';
        osc.frequency.setValueAtTime(240, now);
        osc.frequency.exponentialRampToValueAtTime(480, now + 0.12);
        gain.gain.setValueAtTime(0.08, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.12);
        osc.start(now);
        osc.stop(now + 0.12);
      } else if (type === 'snap') {
        osc.type = 'triangle';
        osc.frequency.setValueAtTime(450, now);
        osc.frequency.exponentialRampToValueAtTime(200, now + 0.08);
        gain.gain.setValueAtTime(0.07, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.08);
        osc.start(now);
        osc.stop(now + 0.08);
      } else if (type === 'ding' || type === 'notification') {
        // High harmonic chime
        osc.type = 'sine';
        osc.frequency.setValueAtTime(880, now);
        osc.frequency.exponentialRampToValueAtTime(1320, now + 0.08);
        gain.gain.setValueAtTime(0.12, now);
        gain.gain.exponentialRampToValueAtTime(0.001, now + 0.35);
        osc.start(now);
        osc.stop(now + 0.35);

        // second harmonic
        const osc2 = this.ctx.createOscillator();
        const gain2 = this.ctx.createGain();
        osc2.type = 'sine';
        osc2.frequency.setValueAtTime(1760, now + 0.06);
        gain2.gain.setValueAtTime(0.08, now + 0.06);
        gain2.gain.exponentialRampToValueAtTime(0.001, now + 0.4);
        osc2.connect(gain2);
        gain2.connect(this.ctx.destination);
        osc2.start(now + 0.06);
        osc2.stop(now + 0.4);
      }
    } catch {
      // AudioContext policy suppression gracefully handled
    }
  }

  // Music synthesis scheduler
  private startScheduler() {
    if (this.timerId !== null) {
      window.clearInterval(this.timerId);
    }

    const stepIntervalMs = (60 / this.tempo / 4) * 1000; // 16th notes
    this.timerId = window.setInterval(() => {
      if (!this.isPlaying) return;

      this.currentTime += stepIntervalMs / 1000;
      if (this.currentTime >= this.duration) {
        this.currentTime = 0;
      }
      this.onTickCallback?.(this.currentTime, true);

      this.playNoteStep(this.beatStep % 16);
      this.beatStep++;
    }, stepIntervalMs);
  }

  // Musical note patterns based on track
  private playNoteStep(step: number) {
    if (!this.ctx || !this.analyser) return;
    const now = this.ctx.currentTime;

    // Chords and bass variations based on track
    const chordRoots = this.currentTrackId === 'track-2' 
      ? [261.63, 293.66, 329.63, 392.00] // C4, D4, E4, G4 (uplifting synth)
      : this.currentTrackId === 'track-3'
      ? [220.00, 261.63, 329.63, 293.66] // A3, C4, E4, D4 (chill lofi)
      : [174.61, 220.00, 261.63, 196.00]; // F3, A3, C4, G3 (dreamy neo-soul)

    const bar = Math.floor(this.beatStep / 16) % chordRoots.length;
    const root = chordRoots[bar];

    // Kick drum on 0 and 8
    if (step === 0 || step === 8 || (step === 14 && Math.random() > 0.4)) {
      this.triggerKick(now);
    }

    // Snare / Rimshot on 4 and 12
    if (step === 4 || step === 12) {
      this.triggerSnare(now);
    }

    // Hi-hat on every 2 steps
    if (step % 2 === 0) {
      this.triggerHiHat(now, step % 4 === 2);
    }

    // Melodic synth pluck
    if (step === 0 || step === 3 || step === 6 || step === 10 || step === 14) {
      const freqMultiplier = [1, 1.25, 1.5, 1.875, 2][Math.floor(Math.random() * 5)];
      this.triggerPluck(now, root * freqMultiplier);
    }

    // Warm bass on downbeat
    if (step === 0 || step === 8) {
      this.triggerBass(now, root / 2);
    }
  }

  private triggerKick(time: number) {
    if (!this.ctx || !this.analyser) return;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.frequency.setValueAtTime(140, time);
    osc.frequency.exponentialRampToValueAtTime(38, time + 0.12);
    gain.gain.setValueAtTime(0.4, time);
    gain.gain.exponentialRampToValueAtTime(0.001, time + 0.2);
    osc.connect(gain);
    gain.connect(this.analyser);
    osc.start(time);
    osc.stop(time + 0.2);
  }

  private triggerSnare(time: number) {
    if (!this.ctx || !this.analyser) return;
    // noise buffer
    const bufferSize = this.ctx.sampleRate * 0.1;
    const buffer = this.ctx.createBuffer(1, bufferSize, this.ctx.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      data[i] = Math.random() * 2 - 1;
    }
    const noise = this.ctx.createBufferSource();
    noise.buffer = buffer;
    const filter = this.ctx.createBiquadFilter();
    filter.type = 'highpass';
    filter.frequency.value = 800;

    const gain = this.ctx.createGain();
    gain.gain.setValueAtTime(0.2, time);
    gain.gain.exponentialRampToValueAtTime(0.01, time + 0.15);

    noise.connect(filter);
    filter.connect(gain);
    gain.connect(this.analyser);
    noise.start(time);
    noise.stop(time + 0.15);
  }

  private triggerHiHat(time: number, accent: boolean) {
    if (!this.ctx || !this.analyser) return;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.type = 'square';
    osc.frequency.setValueAtTime(8000, time);
    const vol = accent ? 0.08 : 0.04;
    gain.gain.setValueAtTime(vol, time);
    gain.gain.exponentialRampToValueAtTime(0.001, time + 0.05);
    osc.connect(gain);
    gain.connect(this.analyser);
    osc.start(time);
    osc.stop(time + 0.05);
  }

  private triggerBass(time: number, freq: number) {
    if (!this.ctx || !this.analyser) return;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.type = 'triangle';
    osc.frequency.setValueAtTime(freq, time);
    gain.gain.setValueAtTime(0.25, time);
    gain.gain.exponentialRampToValueAtTime(0.01, time + 0.4);
    osc.connect(gain);
    gain.connect(this.analyser);
    osc.start(time);
    osc.stop(time + 0.4);
  }

  private triggerPluck(time: number, freq: number) {
    if (!this.ctx || !this.analyser) return;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(freq, time);
    gain.gain.setValueAtTime(0.18, time);
    gain.gain.exponentialRampToValueAtTime(0.001, time + 0.3);
    osc.connect(gain);
    gain.connect(this.analyser);
    osc.start(time);
    osc.stop(time + 0.3);
  }
}

export const audioEngine = new AudioEngine();
