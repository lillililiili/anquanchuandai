async (page) => {
  await page.goto('about:blank'); await page.goto('http://localhost:5176/#/login');
  await page.getByRole('heading', { name: '工作账号登录' }).waitFor(); await page.waitForTimeout(250);
  return await page.evaluate(async () => {
    const { createVideoPlayer } = await import('/src/utils/video-player.js');
    const { nativeAdapter } = await import('/src/utils/video-adapters.js');
    const canvas = document.createElement('canvas'); canvas.width=160; canvas.height=90;
    const context=canvas.getContext('2d'), stream=canvas.captureStream(15), chunks=[];
    const recorder=new MediaRecorder(stream,{mimeType:'video/webm;codecs=vp8'});
    const done=new Promise(resolve=>{recorder.onstop=resolve;}); recorder.ondataavailable=e=>chunks.push(e.data);recorder.start();
    let n=0; const interval=setInterval(()=>{context.fillStyle=n++%2?'#00b5d8':'#123456';context.fillRect(0,0,160,90);context.fillStyle='white';context.fillText(String(n),20,40);},60);
    await new Promise(r=>setTimeout(r,1200));recorder.stop();await done;clearInterval(interval);stream.getTracks().forEach(t=>t.stop());
    const url=URL.createObjectURL(new Blob(chunks,{type:'video/webm'}));const media=document.createElement('video');media.muted=true;media.playsInline=true;document.body.append(media);
    const states=[]; let releases=0; const player=createVideoPlayer({media, provider:{async acquire(){return {state:'AVAILABLE',type:'native',url,sourceTime:null,release(){releases++;}};}},createAdapter:nativeAdapter,onChange:s=>states.push(s)});
    try{await player.start();await new Promise(r=>setTimeout(r,800));if(!states.some(s=>s.state==='PLAYING'&&s.lastDisplayedAt))throw Error('No actual frame advancement');if(player.snapshot.sourceTime!==null)throw Error('Invented source time');player.pause();player.destroy();player.destroy();if(releases!==1)throw Error('release count');return {actualFrameAdvancement:true,states:[...new Set(states.map(s=>s.state))],sourceTime:null,releases,codec:'local synthetic WebM VP8; not FLV validation'};}finally{player.destroy();media.remove();URL.revokeObjectURL(url);}
  });
}
