// All samples are generated locally. This module never calls getUserMedia.
export async function createSource({ video, name, sn }) {
  const context = new AudioContext({ sampleRate: 48000 });
  try {
    await context.resume();
    const destination = context.createMediaStreamDestination();
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    oscillator.frequency.value = 440;
    oscillator.connect(gain).connect(destination);
    oscillator.start();
    let muted = false;
    const pulse = () => {
      gain.gain.cancelScheduledValues(context.currentTime);
      gain.gain.setValueAtTime(0, context.currentTime);
      if (!muted) {
        gain.gain.linearRampToValueAtTime(.08, context.currentTime + .02);
        gain.gain.setValueAtTime(.08, context.currentTime + .2);
        gain.gain.linearRampToValueAtTime(0, context.currentTime + .25);
      }
    };
    pulse();
    const audioTimer = setInterval(pulse, 1000);
    const stream = new MediaStream(destination.stream.getAudioTracks());
    let videoTimer;
    let frame = 0;
    let paused = false;
    if (video) {
      const canvas = document.createElement('canvas');
      canvas.width = 640; canvas.height = 360;
      const ctx = canvas.getContext('2d');
      const draw = () => {
        frame++;
        const palette = ['#e5d369', '#62bea2', '#72aada', '#b099cb', '#d88a84', '#54868b'];
        ctx.fillStyle = '#122c29'; ctx.fillRect(0, 0, 640, 360);
        ctx.fillStyle = '#1b423a';
        for (let x = 0; x < 640; x += 40) { ctx.fillRect(x, 0, 1, 360); }
        for (let y = 0; y < 360; y += 40) { ctx.fillRect(0, y, 640, 1); }
        ctx.fillStyle = '#9bc6b5'; ctx.font = '12px sans-serif';
        ctx.fillText('CALL LAB / SYNTHETIC VIDEO', 32, 36);
        ctx.fillStyle = '#eef9f1'; ctx.font = 'bold 34px sans-serif';
        ctx.fillText(name, 32, 112);
        ctx.fillStyle = '#9bc6b5'; ctx.font = '15px monospace';
        ctx.fillText(sn || 'VIRTUAL DEVICE', 32, 142);
        ctx.font = '28px monospace'; ctx.fillStyle = '#eef9f1';
        ctx.fillText(new Date().toLocaleTimeString('zh-CN', { hour12: false }), 32, 205);
        ctx.font = '12px monospace'; ctx.fillStyle = '#94b5a7';
        ctx.fillText(paused ? 'VIDEO PAUSED' : `FRAME ${String(frame).padStart(6, '0')}    640 x 360 / 15 FPS`, 32, 236);
        palette.forEach((color, i) => { ctx.fillStyle = color; ctx.fillRect(32 + i * 96, 270, 96, 42); });
        if (!paused) { ctx.fillStyle = '#fff'; ctx.fillRect(32 + (frame * 4) % 570, 324, 7, 7); }
        if (paused) { ctx.fillStyle = '#0a1819cc'; ctx.fillRect(0, 0, 640, 360); ctx.fillStyle = '#fff'; ctx.font = '24px sans-serif'; ctx.fillText('测试画面已暂停', 220, 188); }
      };
      draw();
      const canvasStream = canvas.captureStream(15);
      stream.addTrack(canvasStream.getVideoTracks()[0]);
      videoTimer = setInterval(draw, 1000 / 15);
    }
    let stopped = false;
    return {
      stream,
      setMuted(value) { muted = value; pulse(); },
      setVideoPaused(value) { paused = value; },
      async resume() { await context.resume(); },
      stop() {
        if (stopped) return; stopped = true;
        clearInterval(audioTimer); clearInterval(videoTimer);
        oscillator.stop(); oscillator.disconnect(); gain.disconnect();
        stream.getTracks().forEach(track => track.stop());
        void context.close();
      },
    };
  } catch (error) { await context.close(); throw error; }
}
