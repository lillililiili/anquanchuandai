import {
  Tile_default
} from "./chunk-AXERB6JN.js";
import {
  TileState_default
} from "./chunk-72RDZREA.js";
import {
  ImageBase_default,
  ImageState_default
} from "./chunk-2DRW3VXM.js";
import {
  createCanvasContext2D,
  releaseCanvas
} from "./chunk-HLUQ6OII.js";
import {
  getUid
} from "./chunk-L576JWIF.js";
import {
  assert
} from "./chunk-XD3RJ2XY.js";

// node_modules/ol/ImageCanvas.js
var ImageCanvas = class extends ImageBase_default {
  /**
   * @param {import("./extent.js").Extent} extent Extent.
   * @param {number} resolution Resolution.
   * @param {number} pixelRatio Pixel ratio.
   * @param {HTMLCanvasElement} canvas Canvas.
   * @param {Loader} [loader] Optional loader function to
   *     support asynchronous canvas drawing.
   */
  constructor(extent, resolution, pixelRatio, canvas, loader) {
    const state = loader !== void 0 ? ImageState_default.IDLE : ImageState_default.LOADED;
    super(extent, resolution, pixelRatio, state);
    this.loader_ = loader !== void 0 ? loader : null;
    this.canvas_ = canvas;
    this.error_ = null;
  }
  /**
   * Get any error associated with asynchronous rendering.
   * @return {?Error} Any error that occurred during rendering.
   */
  getError() {
    return this.error_;
  }
  /**
   * Handle async drawing complete.
   * @param {Error} [err] Any error during drawing.
   * @private
   */
  handleLoad_(err) {
    if (err) {
      this.error_ = err;
      this.state = ImageState_default.ERROR;
    } else {
      this.state = ImageState_default.LOADED;
    }
    this.changed();
  }
  /**
   * Load not yet loaded URI.
   */
  load() {
    if (this.state == ImageState_default.IDLE) {
      this.state = ImageState_default.LOADING;
      this.changed();
      this.loader_(this.handleLoad_.bind(this));
    }
  }
  /**
   * @return {HTMLCanvasElement} Canvas element.
   */
  getImage() {
    return this.canvas_;
  }
};
var ImageCanvas_default = ImageCanvas;

// node_modules/ol/structs/LRUCache.js
var LRUCache = class {
  /**
   * @param {number} [highWaterMark] High water mark.
   */
  constructor(highWaterMark) {
    this.highWaterMark = highWaterMark !== void 0 ? highWaterMark : 2048;
    this.count_ = 0;
    this.entries_ = {};
    this.oldest_ = null;
    this.newest_ = null;
  }
  /**
   * @return {boolean} Can expire cache.
   */
  canExpireCache() {
    return this.highWaterMark > 0 && this.getCount() > this.highWaterMark;
  }
  /**
   * Expire the cache.
   * @param {!Object<string, boolean>} [keep] Keys to keep. To be implemented by subclasses.
   */
  expireCache(keep) {
    while (this.canExpireCache()) {
      this.pop();
    }
  }
  /**
   * FIXME empty description for jsdoc
   */
  clear() {
    this.count_ = 0;
    this.entries_ = {};
    this.oldest_ = null;
    this.newest_ = null;
  }
  /**
   * @param {string} key Key.
   * @return {boolean} Contains key.
   */
  containsKey(key) {
    return this.entries_.hasOwnProperty(key);
  }
  /**
   * @param {function(T, string, LRUCache<T>): ?} f The function
   *     to call for every entry from the oldest to the newer. This function takes
   *     3 arguments (the entry value, the entry key and the LRUCache object).
   *     The return value is ignored.
   */
  forEach(f) {
    let entry = this.oldest_;
    while (entry) {
      f(entry.value_, entry.key_, this);
      entry = entry.newer;
    }
  }
  /**
   * @param {string} key Key.
   * @param {*} [options] Options (reserved for subclasses).
   * @return {T} Value.
   */
  get(key, options) {
    const entry = this.entries_[key];
    assert(entry !== void 0, 15);
    if (entry === this.newest_) {
      return entry.value_;
    }
    if (entry === this.oldest_) {
      this.oldest_ = /** @type {Entry} */
      this.oldest_.newer;
      this.oldest_.older = null;
    } else {
      entry.newer.older = entry.older;
      entry.older.newer = entry.newer;
    }
    entry.newer = null;
    entry.older = this.newest_;
    this.newest_.newer = entry;
    this.newest_ = entry;
    return entry.value_;
  }
  /**
   * Remove an entry from the cache.
   * @param {string} key The entry key.
   * @return {T} The removed entry.
   */
  remove(key) {
    const entry = this.entries_[key];
    assert(entry !== void 0, 15);
    if (entry === this.newest_) {
      this.newest_ = /** @type {Entry} */
      entry.older;
      if (this.newest_) {
        this.newest_.newer = null;
      }
    } else if (entry === this.oldest_) {
      this.oldest_ = /** @type {Entry} */
      entry.newer;
      if (this.oldest_) {
        this.oldest_.older = null;
      }
    } else {
      entry.newer.older = entry.older;
      entry.older.newer = entry.newer;
    }
    delete this.entries_[key];
    --this.count_;
    return entry.value_;
  }
  /**
   * @return {number} Count.
   */
  getCount() {
    return this.count_;
  }
  /**
   * @return {Array<string>} Keys.
   */
  getKeys() {
    const keys = new Array(this.count_);
    let i = 0;
    let entry;
    for (entry = this.newest_; entry; entry = entry.older) {
      keys[i++] = entry.key_;
    }
    return keys;
  }
  /**
   * @return {Array<T>} Values.
   */
  getValues() {
    const values = new Array(this.count_);
    let i = 0;
    let entry;
    for (entry = this.newest_; entry; entry = entry.older) {
      values[i++] = entry.value_;
    }
    return values;
  }
  /**
   * @return {T} Last value.
   */
  peekLast() {
    return this.oldest_.value_;
  }
  /**
   * @return {string} Last key.
   */
  peekLastKey() {
    return this.oldest_.key_;
  }
  /**
   * Get the key of the newest item in the cache.  Throws if the cache is empty.
   * @return {string} The newest key.
   */
  peekFirstKey() {
    return this.newest_.key_;
  }
  /**
   * Return an entry without updating least recently used time.
   * @param {string} key Key.
   * @return {T} Value.
   */
  peek(key) {
    if (!this.containsKey(key)) {
      return void 0;
    }
    return this.entries_[key].value_;
  }
  /**
   * @return {T} value Value.
   */
  pop() {
    const entry = this.oldest_;
    delete this.entries_[entry.key_];
    if (entry.newer) {
      entry.newer.older = null;
    }
    this.oldest_ = /** @type {Entry} */
    entry.newer;
    if (!this.oldest_) {
      this.newest_ = null;
    }
    --this.count_;
    return entry.value_;
  }
  /**
   * @param {string} key Key.
   * @param {T} value Value.
   */
  replace(key, value) {
    this.get(key);
    this.entries_[key].value_ = value;
  }
  /**
   * @param {string} key Key.
   * @param {T} value Value.
   */
  set(key, value) {
    assert(!(key in this.entries_), 16);
    const entry = {
      key_: key,
      newer: null,
      older: this.newest_,
      value_: value
    };
    if (!this.newest_) {
      this.oldest_ = entry;
    } else {
      this.newest_.newer = entry;
    }
    this.newest_ = entry;
    this.entries_[key] = entry;
    ++this.count_;
  }
  /**
   * Set a maximum number of entries for the cache.
   * @param {number} size Cache size.
   * @api
   */
  setSize(size) {
    this.highWaterMark = size;
  }
};
var LRUCache_default = LRUCache;

// node_modules/ol/tilecoord.js
function createOrUpdate(z, x, y, tileCoord) {
  if (tileCoord !== void 0) {
    tileCoord[0] = z;
    tileCoord[1] = x;
    tileCoord[2] = y;
    return tileCoord;
  }
  return [z, x, y];
}
function getKeyZXY(z, x, y) {
  return z + "/" + x + "/" + y;
}
function getKey(tileCoord) {
  return getKeyZXY(tileCoord[0], tileCoord[1], tileCoord[2]);
}
function getCacheKeyForTileKey(tileKey) {
  const [z, x, y] = tileKey.substring(tileKey.lastIndexOf("/") + 1, tileKey.length).split(",").map(Number);
  return getKeyZXY(z, x, y);
}
function fromKey(key) {
  return key.split("/").map(Number);
}
function hash(tileCoord) {
  return (tileCoord[1] << tileCoord[0]) + tileCoord[2];
}
function withinExtentAndZ(tileCoord, tileGrid) {
  const z = tileCoord[0];
  const x = tileCoord[1];
  const y = tileCoord[2];
  if (tileGrid.getMinZoom() > z || z > tileGrid.getMaxZoom()) {
    return false;
  }
  const tileRange = tileGrid.getFullTileRange(z);
  if (!tileRange) {
    return true;
  }
  return tileRange.containsXY(x, y);
}

// node_modules/ol/TileCache.js
var TileCache = class extends LRUCache_default {
  clear() {
    while (this.getCount() > 0) {
      this.pop().release();
    }
    super.clear();
  }
  /**
   * @param {!Object<string, boolean>} usedTiles Used tiles.
   */
  expireCache(usedTiles) {
    while (this.canExpireCache()) {
      const tile = this.peekLast();
      if (tile.getKey() in usedTiles) {
        break;
      } else {
        this.pop().release();
      }
    }
  }
  /**
   * Prune all tiles from the cache that don't have the same z as the newest tile.
   */
  pruneExceptNewestZ() {
    if (this.getCount() === 0) {
      return;
    }
    const key = this.peekFirstKey();
    const tileCoord = fromKey(key);
    const z = tileCoord[0];
    this.forEach((tile) => {
      if (tile.tileCoord[0] !== z) {
        this.remove(getKey(tile.tileCoord));
        tile.release();
      }
    });
  }
};
var TileCache_default = TileCache;

// node_modules/ol/VectorRenderTile.js
var canvasPool = [];
var VectorRenderTile = class extends Tile_default {
  /**
   * @param {import("./tilecoord.js").TileCoord} tileCoord Tile coordinate.
   * @param {import("./TileState.js").default} state State.
   * @param {import("./tilecoord.js").TileCoord} urlTileCoord Wrapped tile coordinate for source urls.
   * @param {function(VectorRenderTile):Array<import("./VectorTile").default>} getSourceTiles Function
   * to get source tiles for this tile.
   */
  constructor(tileCoord, state, urlTileCoord, getSourceTiles) {
    super(tileCoord, state, { transition: 0 });
    this.context_ = {};
    this.executorGroups = {};
    this.declutterExecutorGroups = {};
    this.loadingSourceTiles = 0;
    this.hitDetectionImageData = {};
    this.replayState_ = {};
    this.sourceTiles = [];
    this.errorTileKeys = {};
    this.wantedResolution;
    this.getSourceTiles = getSourceTiles.bind(void 0, this);
    this.wrappedTileCoord = urlTileCoord;
  }
  /**
   * @param {import("./layer/Layer.js").default} layer Layer.
   * @return {CanvasRenderingContext2D} The rendering context.
   */
  getContext(layer) {
    const key = getUid(layer);
    if (!(key in this.context_)) {
      this.context_[key] = createCanvasContext2D(1, 1, canvasPool);
    }
    return this.context_[key];
  }
  /**
   * @param {import("./layer/Layer.js").default} layer Layer.
   * @return {boolean} Tile has a rendering context for the given layer.
   */
  hasContext(layer) {
    return getUid(layer) in this.context_;
  }
  /**
   * Get the Canvas for this tile.
   * @param {import("./layer/Layer.js").default} layer Layer.
   * @return {HTMLCanvasElement} Canvas.
   */
  getImage(layer) {
    return this.hasContext(layer) ? this.getContext(layer).canvas : null;
  }
  /**
   * @param {import("./layer/Layer.js").default} layer Layer.
   * @return {ReplayState} The replay state.
   */
  getReplayState(layer) {
    const key = getUid(layer);
    if (!(key in this.replayState_)) {
      this.replayState_[key] = {
        dirty: false,
        renderedRenderOrder: null,
        renderedResolution: NaN,
        renderedRevision: -1,
        renderedTileResolution: NaN,
        renderedTileRevision: -1,
        renderedTileZ: -1
      };
    }
    return this.replayState_[key];
  }
  /**
   * Load the tile.
   */
  load() {
    this.getSourceTiles();
  }
  /**
   * Remove from the cache due to expiry
   */
  release() {
    for (const key in this.context_) {
      const context = this.context_[key];
      releaseCanvas(context);
      canvasPool.push(context.canvas);
      delete this.context_[key];
    }
    super.release();
  }
};
var VectorRenderTile_default = VectorRenderTile;

// node_modules/ol/VectorTile.js
var VectorTile = class extends Tile_default {
  /**
   * @param {import("./tilecoord.js").TileCoord} tileCoord Tile coordinate.
   * @param {import("./TileState.js").default} state State.
   * @param {string} src Data source url.
   * @param {import("./format/Feature.js").default} format Feature format.
   * @param {import("./Tile.js").LoadFunction} tileLoadFunction Tile load function.
   * @param {import("./Tile.js").Options} [options] Tile options.
   */
  constructor(tileCoord, state, src, format, tileLoadFunction, options) {
    super(tileCoord, state, options);
    this.extent = null;
    this.format_ = format;
    this.features_ = null;
    this.loader_;
    this.projection = null;
    this.resolution;
    this.tileLoadFunction_ = tileLoadFunction;
    this.url_ = src;
    this.key = src;
  }
  /**
   * Get the feature format assigned for reading this tile's features.
   * @return {import("./format/Feature.js").default} Feature format.
   * @api
   */
  getFormat() {
    return this.format_;
  }
  /**
   * Get the features for this tile. Geometries will be in the view projection.
   * @return {Array<import("./Feature.js").FeatureLike>} Features.
   * @api
   */
  getFeatures() {
    return this.features_;
  }
  /**
   * Load not yet loaded URI.
   */
  load() {
    if (this.state == TileState_default.IDLE) {
      this.setState(TileState_default.LOADING);
      this.tileLoadFunction_(this, this.url_);
      if (this.loader_) {
        this.loader_(this.extent, this.resolution, this.projection);
      }
    }
  }
  /**
   * Handler for successful tile load.
   * @param {Array<import("./Feature.js").default>} features The loaded features.
   * @param {import("./proj/Projection.js").default} dataProjection Data projection.
   */
  onLoad(features, dataProjection) {
    this.setFeatures(features);
  }
  /**
   * Handler for tile load errors.
   */
  onError() {
    this.setState(TileState_default.ERROR);
  }
  /**
   * Function for use in an {@link module:ol/source/VectorTile~VectorTile}'s `tileLoadFunction`.
   * Sets the features for the tile.
   * @param {Array<import("./Feature.js").default>} features Features.
   * @api
   */
  setFeatures(features) {
    this.features_ = features;
    this.setState(TileState_default.LOADED);
  }
  /**
   * Set the feature loader for reading this tile's features.
   * @param {import("./featureloader.js").FeatureLoader} loader Feature loader.
   * @api
   */
  setLoader(loader) {
    this.loader_ = loader;
  }
};
var VectorTile_default = VectorTile;

export {
  ImageCanvas_default,
  LRUCache_default,
  createOrUpdate,
  getKeyZXY,
  getKey,
  getCacheKeyForTileKey,
  fromKey,
  hash,
  withinExtentAndZ,
  TileCache_default,
  VectorRenderTile_default,
  VectorTile_default
};
//# sourceMappingURL=chunk-R6MMLIEB.js.map
