import "./chunk-G3PMV62Z.js";

// node_modules/autofit.js/dist/autofit.esm.js
var currRenderDom = null;
var currelRectification = "";
var currelRectificationLevel = "";
var currelRectificationIsKeepRatio = "";
var resizeListener = null;
var timer = null;
var currScale = 1;
var isElRectification = false;
var autofit = {
  isAutofitRunning: false,
  init(options = {}, isShowInitTip = true) {
    if (isShowInitTip) console.log(`autofit.js is running`);
    const { dw = 1920, dh = 1080, el = typeof options === "string" ? options : "body", resize = true, ignore = [], transition = "none", delay = 0, limit = 0.1, cssMode = "scale", allowScroll = false } = options;
    currRenderDom = el;
    const dom = document.querySelector(el);
    if (!dom) {
      console.error(`autofit: '${el}' is not exist`);
      return;
    }
    const style = document.createElement("style");
    const ignoreStyle = document.createElement("style");
    style.lang = "text/css";
    ignoreStyle.lang = "text/css";
    style.id = "autofit-style";
    ignoreStyle.id = "ignoreStyle";
    !allowScroll && (style.innerHTML = `body {overflow: hidden;}`);
    const bodyEl = document.querySelector("body");
    bodyEl.appendChild(style);
    bodyEl.appendChild(ignoreStyle);
    dom.style.height = `${dh}px`;
    dom.style.width = `${dw}px`;
    dom.style.transformOrigin = `0 0`;
    !allowScroll && (dom.style.overflow = "hidden");
    keepFit(dw, dh, dom, ignore, limit, cssMode);
    resizeListener = () => {
      clearTimeout(timer);
      if (delay != 0) timer = setTimeout(() => {
        keepFit(dw, dh, dom, ignore, limit, cssMode);
        isElRectification && elRectification(currelRectification, currelRectificationIsKeepRatio, currelRectificationLevel);
      }, delay);
      else {
        keepFit(dw, dh, dom, ignore, limit, cssMode);
        isElRectification && elRectification(currelRectification, currelRectificationIsKeepRatio, currelRectificationLevel);
      }
    };
    resize && window.addEventListener("resize", resizeListener);
    this.isAutofitRunning = true;
    setTimeout(() => {
      dom.style.transition = `${transition}s`;
    });
  },
  off(el = "body") {
    try {
      window.removeEventListener("resize", resizeListener);
      const autofitStyle = document.querySelector("#autofit-style");
      autofitStyle && autofitStyle.remove();
      const ignoreStyleDOM = document.querySelector("#ignoreStyle");
      ignoreStyleDOM && ignoreStyleDOM.remove();
      const temp = document.querySelector(currRenderDom ? currRenderDom : el);
      temp && (temp.style.cssText = "");
      isElRectification && offelRectification();
    } catch (error) {
      console.error(`autofit: Failed to remove normally`, error);
    }
    this.isAutofitRunning = false;
    console.log(`autofit.js is off`);
  },
  elRectification: null,
  scale: currScale
};
function elRectification(el, isKeepRatio = true, level = 1) {
  if (!autofit.isAutofitRunning) {
    console.error("autofit.js：(elRectification): autofit has not been initialized yet");
    return;
  }
  offelRectification();
  !el && console.error(`autofit.js：elRectification bad selector: ${el}`);
  currelRectification = el;
  currelRectificationLevel = level;
  currelRectificationIsKeepRatio = isKeepRatio;
  const currEl = Array.from(document.querySelectorAll(el));
  if (currEl.length == 0) {
    console.error(`autofit.js：elRectification found no element by selector: "${el}"`);
    return;
  }
  for (const item of currEl) {
    const rectification = currScale == 1 ? 1 : Number(currScale) * Number(level);
    if (!isElRectification) {
      item.originalWidth = item.clientWidth;
      item.originalHeight = item.clientHeight;
    }
    if (isKeepRatio) {
      item.style.width = `${item.originalWidth * rectification}px`;
      item.style.height = `${item.originalHeight * rectification}px`;
    } else {
      item.style.width = `${100 * rectification}%`;
      item.style.height = `${100 * rectification}%`;
    }
    item.style.transform = `translateZ(0) scale(${1 / Number(currScale)})`;
    item.style.transformOrigin = `0 0`;
  }
  isElRectification = true;
}
function offelRectification() {
  if (!currelRectification) return;
  isElRectification = false;
  for (const item of Array.from(document.querySelectorAll(currelRectification))) {
    item.style.width = ``;
    item.style.height = ``;
    item.style.transform = ``;
  }
}
function keepFit(dw, dh, dom, ignore, limit, cssMode = "scale") {
  const clientHeight = document.documentElement.clientHeight;
  const clientWidth = document.documentElement.clientWidth;
  currScale = clientWidth / clientHeight < dw / dh ? clientWidth / dw : clientHeight / dh;
  currScale = Math.abs(1 - currScale) > limit ? currScale : 1;
  autofit.scale = +currScale;
  const height = Math.round(clientHeight / Number(currScale));
  const width = Math.round(clientWidth / Number(currScale));
  dom.style.height = `${height}px`;
  dom.style.width = `${width}px`;
  if (cssMode === "zoom") dom.style.zoom = `${currScale}`;
  else dom.style.transform = `translateZ(0) scale(${currScale})`;
  const ignoreStyleDOM = document.querySelector("#ignoreStyle");
  ignoreStyleDOM.innerHTML = "";
  for (const temp of ignore) {
    const item = temp;
    let itemEl = item.el || item.dom;
    typeof item == "string" && (itemEl = item);
    if (!itemEl || typeof itemEl === "object" && !Object.keys(itemEl).length) {
      console.error(`autofit: found invalid or empty selector/object: ${itemEl}`);
      continue;
    }
    const realScale = item.scale ? item.scale : 1 / Number(currScale);
    const realFontSize = realScale != currScale && item.fontSize;
    const realWidth = realScale != currScale && item.width;
    const realHeight = realScale != currScale && item.height;
    ignoreStyleDOM.innerHTML += `
${itemEl} { 
      transform: scale(${realScale})!important;
      transform-origin: 0 0;
      ${realWidth ? `width: ${realWidth}!important;` : ""}
      ${realHeight ? `height: ${realHeight}!important;` : ""}
    }`;
    if (realFontSize) ignoreStyleDOM.innerHTML += `
${itemEl} div ,${itemEl} span,${itemEl} a,${itemEl} * {
        font-size: ${realFontSize}px;
      }`;
  }
}
autofit.elRectification = elRectification;
export {
  autofit as default,
  elRectification
};
/*! Bundled license information:

autofit.js/dist/autofit.esm.js:
  (**
   * @name: autofit.js
   * @author: Larry Zhu
   * @version: 3.2.8
   * @description: autofit.js 是迄今为止最易用的自适应工具
   * @license: MIT
   *)
*/
//# sourceMappingURL=autofit__js.js.map
