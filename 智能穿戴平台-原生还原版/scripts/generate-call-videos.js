// Run with playwright-cli run-code after opening the local preview.
async (page) => {
  const outputs = [];
  for (const area of ["boiler", "turbine", "electric", "water"]) {
    const downloaded = page.waitForEvent("download");
    await page.evaluate(async (area) => {
      const image = new Image();
      image.src = `assets/scene-${area}.png`;
      await image.decode();
      const canvas = document.createElement("canvas");
      canvas.width = 960;
      canvas.height = 540;
      const ctx = canvas.getContext("2d");
      const stream = canvas.captureStream(20);
      const chunks = [];
      const recorder = new MediaRecorder(stream, {
        mimeType: "video/webm;codecs=vp8",
        videoBitsPerSecond: 1400000,
      });
      const stopped = new Promise((resolve, reject) => {
        recorder.ondataavailable = (event) => chunks.push(event.data);
        recorder.onstop = resolve;
        recorder.onerror = reject;
      });
      let start = performance.now();
      const draw = () => {
        const t = (performance.now() - start) / 1000;
        const phase = t / 8 * Math.PI * 2;
        const scale = Math.max(960 / image.width, 540 / image.height) * (1.10 + 0.025 * Math.sin(phase));
        const w = image.width * scale, h = image.height * scale;
        ctx.drawImage(image, (960 - w) / 2 + Math.sin(phase) * 18,
          (540 - h) / 2 + Math.cos(phase) * 7, w, h);
        ctx.fillStyle = "rgba(0, 20, 35, 0.72)";
        ctx.fillRect(18, 490, 214, 32);
        ctx.fillStyle = "#1ce3b1";
        ctx.beginPath(); ctx.arc(34, 506, 4, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = "white";
        ctx.font = "16px monospace";
        ctx.fillText(`DEMO  00:${String(Math.floor(t) % 8).padStart(2, "0")}`, 48, 512);
      };
      draw();
      recorder.start();
      const timer = setInterval(draw, 50);
      try {
        await new Promise(resolve => setTimeout(resolve, 8000));
        recorder.stop();
        await stopped;
        const url = URL.createObjectURL(new Blob(chunks, {type: "video/webm"}));
        const link = document.createElement("a");
        link.href = url;
        link.download = `call-${area}.webm`;
        link.click();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      } finally {
        clearInterval(timer);
        stream.getTracks().forEach(track => track.stop());
      }
    }, area);
    const file = `智能穿戴平台-原生还原版/assets/call-${area}.webm`;
    await (await downloaded).saveAs(file);
    outputs.push(file);
  }
  return outputs;
}
