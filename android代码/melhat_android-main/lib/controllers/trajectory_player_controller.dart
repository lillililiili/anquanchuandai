import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/trajectory_point.dart';
import '../models/playback_speed.dart';

/// 标记一次查询属于哪一版查询条件，避免旧请求覆盖新条件。
class TrajectoryQueryGeneration {
  int _value = 0;

  int get current => _value;

  int next() => ++_value;

  void invalidate() => _value++;

  bool isCurrent(int generation) => generation == _value;
}

/// 轨迹播放器控制器
///
/// 负责管理轨迹回放的状态和控制：
/// - 播放/暂停/停止
/// - 快进/后退（支持可配置步长）
/// - 速度调节
/// - 进度通知
class TrajectoryPlayerController extends ChangeNotifier {
  /// 轨迹点数据
  List<TrajectoryPoint> _points = [];

  /// 当前播放索引
  int _currentIndex = -1;

  /// 是否正在播放
  bool _isPlaying = false;

  /// 当前播放速度
  PlaybackSpeed _speed = PlaybackSpeed.normalX;

  /// 快进/后退步长（默认 1 帧）
  int _stepSize = 1;

  /// 定时器
  Timer? _timer;

  /// 获取轨迹点数据
  List<TrajectoryPoint> get points => _points;

  /// 获取当前播放索引
  int get currentIndex => _currentIndex;

  /// 获取是否正在播放
  bool get isPlaying => _isPlaying;

  /// 获取当前播放速度
  PlaybackSpeed get speed => _speed;

  /// 获取步长
  int get stepSize => _stepSize;

  /// 获取总点数
  int get totalCount => _points.length;

  /// 获取播放进度（0.0 ~ 1.0）
  double get progress {
    if (_points.isEmpty) return 0.0;
    return (_currentIndex + 1) / _points.length;
  }

  /// 获取当前时间戳
  String? get currentTimestamp {
    if (_currentIndex < 0 || _currentIndex >= _points.length) return null;
    return _points[_currentIndex].timestamp;
  }

  /// 获取开始时间戳
  String? get startTimestamp {
    if (_points.isEmpty) return null;
    return _points.first.timestamp;
  }

  /// 获取结束时间戳
  String? get endTimestamp {
    if (_points.isEmpty) return null;
    return _points.last.timestamp;
  }

  /// 设置轨迹点数据
  void setPoints(List<TrajectoryPoint> points) {
    _points = points;
    _currentIndex = points.isEmpty ? -1 : 0;
    _isPlaying = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  /// 开始播放
  void play() {
    if (_points.isEmpty || _isPlaying) return;

    // 如果已经播放到末尾，从头开始
    if (_currentIndex >= _points.length - 1) {
      _currentIndex = 0;
    }

    _isPlaying = true;
    _startTimer();
    notifyListeners();
  }

  /// 暂停播放
  void pause() {
    _isPlaying = false;
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  /// 切换播放/暂停
  void togglePlay() {
    if (_isPlaying) {
      pause();
    } else {
      play();
    }
  }

  /// 停止播放
  void stop() {
    pause();
    _currentIndex = 0;
    notifyListeners();
  }

  /// 跳转到指定位置
  void seekTo(int index) {
    if (_points.isEmpty) return;
    _currentIndex = index.clamp(0, _points.length - 1);
    notifyListeners();
  }

  /// 跳转到最接近指定时间的真实轨迹点。
  void seekToTimestamp(DateTime target) {
    if (_points.isEmpty) return;

    var nearestIndex = 0;
    var nearestDifference = _points.first.dateTime.difference(target).abs();
    for (var index = 1; index < _points.length; index++) {
      final difference = _points[index].dateTime.difference(target).abs();
      if (difference < nearestDifference) {
        nearestIndex = index;
        nearestDifference = difference;
      }
    }

    seekTo(nearestIndex);
  }

  /// 快进指定步数
  void stepForward([int? steps]) {
    if (_points.isEmpty) return;
    final actualSteps = steps ?? _stepSize;
    _currentIndex = (_currentIndex + actualSteps).clamp(0, _points.length - 1);

    // 如果播放到末尾，自动停止
    if (_currentIndex >= _points.length - 1) {
      pause();
    }
    notifyListeners();
  }

  /// 后退指定步数
  void stepBackward([int? steps]) {
    if (_points.isEmpty) return;
    final actualSteps = steps ?? _stepSize;
    _currentIndex = (_currentIndex - actualSteps).clamp(0, _points.length - 1);
    notifyListeners();
  }

  /// 设置播放速度
  void setSpeed(PlaybackSpeed speed) {
    _speed = speed;
    // 如果正在播放，重启定时器以应用新速度
    if (_isPlaying) {
      _startTimer();
    }
    notifyListeners();
  }

  /// 设置步长
  void setStepSize(int stepSize) {
    _stepSize = stepSize.clamp(1, 100);
    notifyListeners();
  }

  /// 切换到下一个速度档位
  void toggleSpeed() {
    setSpeed(_speed.next);
  }

  /// 启动定时器
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: _speed.intervalMs), (_) {
      if (_currentIndex < _points.length - 1) {
        _currentIndex++;
        notifyListeners();
      } else {
        // 播放完成
        pause();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
