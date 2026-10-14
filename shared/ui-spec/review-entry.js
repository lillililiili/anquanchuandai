// Dev-only fixed viewport host. The iframe runs the real application and real routes.
// width/height are layout viewport dimensions, not a scaled screenshot or browser zoom.
if(import.meta.env.DEV){
  const params=new URLSearchParams(location.search)
  const width=Math.max(320,Math.min(2560,Number(params.get('width'))||1440)),height=Math.max(480,Math.min(1600,Number(params.get('height'))||900))
  const frame=document.createElement('iframe');frame.id='review-app';frame.title='真实应用验收视口'
  const path=params.get('path')||'/';frame.src=path.startsWith('/')&&!path.startsWith('//')?path:'/'
  frame.style.cssText=`display:block;width:${width}px;height:${height}px;border:0;`
  document.body.style.cssText=`margin:0;width:${width}px;height:${height}px;background:#121e37;`
  document.body.append(frame)
}
