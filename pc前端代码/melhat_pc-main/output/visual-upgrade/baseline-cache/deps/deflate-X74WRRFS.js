import {
  inflate_1
} from "./chunk-VQ3C4AQQ.js";
import {
  BaseDecoder
} from "./chunk-U5RMOR45.js";
import "./chunk-G3PMV62Z.js";

// node_modules/geotiff/dist-module/compression/deflate.js
var DeflateDecoder = class extends BaseDecoder {
  decodeBlock(buffer) {
    return inflate_1(new Uint8Array(buffer)).buffer;
  }
};
export {
  DeflateDecoder as default
};
//# sourceMappingURL=deflate-X74WRRFS.js.map
