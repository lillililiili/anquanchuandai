import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../api.dart';

class BackendTileProvider extends TileProvider {
  BackendTileProvider(this.api, this.scopeKey);
  final WearApi api;
  final String scopeKey;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _BackendTileImage(api, scopeKey, getTileUrl(coordinates, options));
}

class _BackendTileImage extends ImageProvider<_BackendTileImage> {
  const _BackendTileImage(this.api, this.scopeKey, this.path);
  final WearApi api;
  final String scopeKey, path;

  @override
  Future<_BackendTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _BackendTileImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final data = await api.get(path);
    if (data is! String || data.isEmpty) throw const FormatException('地图响应无效');
    return decode(await ui.ImmutableBuffer.fromUint8List(base64Decode(data)));
  }

  @override
  bool operator ==(Object other) =>
      other is _BackendTileImage &&
      identical(api, other.api) &&
      scopeKey == other.scopeKey &&
      path == other.path;
  @override
  int get hashCode => Object.hash(api, scopeKey, path);
}
