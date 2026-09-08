/// 播放速度枚举
///
/// 定义轨迹回放的速度档位
/// [label] 显示标签（如 "0.5x", "1x"）
/// [secondsPerFrame] 每帧对应的真实时间（秒），用于计算播放间隔
enum PlaybackSpeed {
  /// 0.5 倍速：1 秒播放真实时间的 30 秒
  halfX(0.5, 3.0),

  /// 1 倍速：1 秒播放真实时间的 60 秒（1 分钟）
  normalX(1.0, 6.0),

  /// 2 倍速：1 秒播放真实时间的 120 秒（2 分钟）
  doubleX(2.0, 12.0),

  /// 5 倍速：1 秒播放真实时间的 300 秒（5 分钟）
  fiveX(5.0, 30.0);

  /// 显示标签
  final double label;

  /// 每帧对应的真实时间（秒）
  final double secondsPerFrame;

  const PlaybackSpeed(this.label, this.secondsPerFrame);

  /// 获取毫秒间隔
  int get intervalMs => (1000 / secondsPerFrame).round();

  /// 从索引获取速度
  static PlaybackSpeed fromIndex(int index) {
    return values[index % values.length];
  }

  /// 下一个速度
  PlaybackSpeed get next {
    final currentIndex = values.indexOf(this);
    return values[(currentIndex + 1) % values.length];
  }
}
