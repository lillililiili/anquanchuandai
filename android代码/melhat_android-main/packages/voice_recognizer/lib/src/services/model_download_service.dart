import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// 模型下载状态
enum DownloadState {
  idle,
  downloading,
  completed,
  error,
}

/// 模型下载服务
///
/// 负责从云端下载语音识别模型文件，并缓存到本地
class ModelDownloadService extends ChangeNotifier {
  static final ModelDownloadService instance = ModelDownloadService._();
  ModelDownloadService._();

  // 模型文件下载 URL
  String _modelUrl = '';
  String _tokensUrl = '';

  // 下载状态
  DownloadState _state = DownloadState.idle;
  double _progress = 0.0;
  String _errorMessage = '';

  // 模型存储目录名
  static const String _modelDirName = 'voice_model';

  /// 当前下载状态
  DownloadState get state => _state;

  /// 下载进度 (0.0 - 1.0)
  double get progress => _progress;

  /// 错误信息
  String get errorMessage => _errorMessage;

  /// 是否正在下载
  bool get isDownloading => _state == DownloadState.downloading;

  /// 模型是否已下载
  bool get isModelReady => _state == DownloadState.completed;

  /// 配置模型下载 URL
  void configure({
    required String modelUrl,
    required String tokensUrl,
  }) {
    _modelUrl = modelUrl;
    _tokensUrl = tokensUrl;
  }

  /// 获取模型存储目录
  Future<Directory> _getModelDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/$_modelDirName');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return modelDir;
  }

  /// 检查模型是否已下载
  Future<bool> checkModelExists() async {
    try {
      final modelDir = await _getModelDirectory();
      final modelFile = File('${modelDir.path}/model.int8.onnx');
      final tokensFile = File('${modelDir.path}/tokens.txt');

      final modelExists = await modelFile.exists();
      final tokensExists = await tokensFile.exists();

      if (modelExists && tokensExists) {
        // 检查文件大小，确保不是空文件
        final modelSize = await modelFile.length();
        final tokensSize = await tokensFile.length();

        if (modelSize > 1024 && tokensSize > 0) {
          _state = DownloadState.completed;
          notifyListeners();
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint('检查模型文件失败: $e');
      return false;
    }
  }

  /// 获取本地模型目录路径
  Future<String?> getModelPath() async {
    if (_state != DownloadState.completed) {
      final exists = await checkModelExists();
      if (!exists) return null;
    }

    final modelDir = await _getModelDirectory();
    return modelDir.path;
  }

  /// 下载模型文件
  Future<bool> downloadModel() async {
    if (_modelUrl.isEmpty || _tokensUrl.isEmpty) {
      _setError('模型下载地址未配置');
      return false;
    }

    if (_state == DownloadState.downloading) {
      return false;
    }

    _state = DownloadState.downloading;
    _progress = 0.0;
    _errorMessage = '';
    notifyListeners();

    try {
      final modelDir = await _getModelDirectory();

      // 下载模型文件（较大，约 78MB）
      debugPrint('开始下载模型文件: $_modelUrl');
      final modelSuccess = await _downloadFile(
        url: _modelUrl,
        savePath: '${modelDir.path}/model.int8.onnx',
        onProgress: (received, total) {
          if (total > 0) {
            _progress = received / total * 0.9; // 模型文件占 90% 进度
            notifyListeners();
          }
        },
      );

      if (!modelSuccess) {
        _setError('模型文件下载失败');
        return false;
      }

      // 下载 tokens 文件（较小）
      debugPrint('开始下载 tokens 文件: $_tokensUrl');
      _progress = 0.9;
      notifyListeners();

      final tokensSuccess = await _downloadFile(
        url: _tokensUrl,
        savePath: '${modelDir.path}/tokens.txt',
        onProgress: (received, total) {
          _progress = 0.9 + (total > 0 ? received / total * 0.1 : 0.1);
          notifyListeners();
        },
      );

      if (!tokensSuccess) {
        _setError('词表文件下载失败');
        return false;
      }

      // 下载完成
      _progress = 1.0;
      _state = DownloadState.completed;
      notifyListeners();
      debugPrint('模型下载完成');
      return true;
    } catch (e) {
      _setError('下载失败: $e');
      return false;
    }
  }

  /// 下载单个文件
  Future<bool> _downloadFile({
    required String url,
    required String savePath,
    required void Function(int received, int total) onProgress,
  }) async {
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        debugPrint('下载失败，状态码: ${response.statusCode}');
        return false;
      }

      final file = File(savePath);
      final sink = file.openWrite();
      int received = 0;
      final total = response.contentLength ?? 0;

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      // 验证文件大小
      if (await file.exists()) {
        final fileSize = await file.length();
        if (fileSize == 0) {
          debugPrint('下载的文件为空: $savePath');
          return false;
        }
        // 如果知道预期大小，校验是否完整下载
        if (total > 0 && fileSize < total) {
          debugPrint('下载不完整: 期望 $total bytes, 实际 $fileSize bytes');
          return false;
        }
        debugPrint('文件下载完成: $savePath ($fileSize bytes)');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('下载文件失败: $e');
      return false;
    }
  }

  /// 删除已下载的模型
  Future<void> deleteModel() async {
    try {
      final modelDir = await _getModelDirectory();
      if (await modelDir.exists()) {
        await modelDir.delete(recursive: true);
        debugPrint('模型文件已删除');
      }
      _state = DownloadState.idle;
      _progress = 0.0;
      notifyListeners();
    } catch (e) {
      debugPrint('删除模型文件失败: $e');
    }
  }

  /// 设置错误状态
  void _setError(String message) {
    _errorMessage = message;
    _state = DownloadState.error;
    _progress = 0.0;
    notifyListeners();
    debugPrint('ModelDownloadService 错误: $message');
  }

  /// 重置状态（从错误状态恢复）
  void reset() {
    _state = DownloadState.idle;
    _progress = 0.0;
    _errorMessage = '';
    notifyListeners();
  }
}
