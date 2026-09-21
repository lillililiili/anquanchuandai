import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:lpinyin/lpinyin.dart';

/// 中文文本纠错工具
///
/// 用于纠正语音识别结果中的常见错误，支持三种匹配模式：
/// 1. 精确匹配替换 - 直接字符串替换
/// 2. 拼音匹配替换 - 同音字自动纠正
/// 3. 模糊匹配替换 - 基于编辑距离的相似词纠正
class TextCorrector {
  /// 纠错词典：错误词 -> 正确词
  final Map<String, String> _corrections;

  /// 热词拼音映射：拼音 -> 正确文本
  final Map<String, String> _pinyinToText;

  /// 是否启用
  bool enabled;

  /// 是否启用拼音匹配
  bool pinyinMatchEnabled;

  /// 是否启用模糊匹配
  bool fuzzyMatchEnabled;

  /// 模糊匹配阈值（0.0-1.0，越高要求越严格）
  double fuzzyThreshold;

  TextCorrector({
    Map<String, String>? corrections,
    Map<String, String>? pinyinToText,
    this.enabled = true,
    this.pinyinMatchEnabled = true,
    this.fuzzyMatchEnabled = true,
    this.fuzzyThreshold = 0.7,
  })  : _corrections = corrections ?? {},
        _pinyinToText = pinyinToText ?? {};

  /// 获取文本的拼音（不带声调，空格分隔）
  String _getPinyin(String text) {
    return PinyinHelper.getPinyinE(text, separator: ' ', defPinyin: '#');
  }

  /// 计算两个字符串的编辑距离（Levenshtein Distance）
  int _editDistance(String s1, String s2) {
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> prev = List.generate(s2.length + 1, (i) => i);
    List<int> curr = List.filled(s2.length + 1, 0);

    for (int i = 1; i <= s1.length; i++) {
      curr[0] = i;
      for (int j = 1; j <= s2.length; j++) {
        int cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        curr[j] = [
          curr[j - 1] + 1,
          prev[j] + 1,
          prev[j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }
    return prev[s2.length];
  }

  /// 计算相似度（0.0-1.0）
  double _similarity(String s1, String s2) {
    if (s1.isEmpty && s2.isEmpty) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final maxLen = s1.length > s2.length ? s1.length : s2.length;
    final distance = _editDistance(s1, s2);
    return 1.0 - (distance / maxLen);
  }

  /// 添加纠错规则
  void addCorrection(String wrong, String correct) {
    _corrections[wrong] = correct;
  }

  /// 批量添加纠错规则
  void addCorrections(Map<String, String> corrections) {
    _corrections.addAll(corrections);
  }

  /// 添加热词（从文本，自动生成拼音）
  void addHotwords(List<String> words) {
    for (final word in words) {
      final pinyin = _getPinyin(word);
      _pinyinToText[pinyin] = word;
    }
  }

  /// 添加热词映射（拼音 -> 文本）
  void addPinyinMapping(String pinyin, String text) {
    _pinyinToText[pinyin] = text;
  }

  /// 批量添加热词映射
  void addPinyinMappings(Map<String, String> mappings) {
    _pinyinToText.addAll(mappings);
  }

  /// 从 JSON 文件加载热词（格式：{"pinyin": "text", ...}）
  Future<void> loadFromAsset(String assetPath) async {
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      loadFromJson(jsonString);
    } catch (e) {
      throw Exception('加载热词文件失败: $e');
    }
  }

  /// 从 JSON 字符串加载热词
  void loadFromJson(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    for (final entry in json.entries) {
      _pinyinToText[entry.key] = entry.value as String;
    }
  }

  /// 移除纠错规则
  void removeCorrection(String wrong) {
    _corrections.remove(wrong);
  }

  /// 移除热词（通过拼音）
  void removeHotwordByPinyin(String pinyin) {
    _pinyinToText.remove(pinyin);
  }

  /// 移除热词（通过文本）
  void removeHotword(String text) {
    _pinyinToText.removeWhere((_, v) => v == text);
  }

  /// 清空所有规则
  void clear() {
    _corrections.clear();
    _pinyinToText.clear();
  }

  /// 拼音匹配纠正
  String pinyinCorrect(String text) {
    var result = _getPinyin(text);
    if (_pinyinToText.containsKey(result)) {
      return _pinyinToText[result]!;
    }
    return text;
  }

  /// 纠正文本
  ///
  /// 处理顺序：
  /// 1. 精确匹配替换
  /// 2. 拼音匹配替换（同音字）
  /// 3. 模糊匹配替换（相似字）
  String correct(String text) {
    if (!enabled || text.isEmpty) {
      return text;
    }

    var result = text;

    // 步骤1: 精确匹配替换
    if (_corrections.isNotEmpty) {
      final sortedKeys = _corrections.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length));

      for (final wrong in sortedKeys) {
        final correct = _corrections[wrong]!;
        if (wrong != correct) {
          result = result.replaceAll(wrong, correct);
        }
      }
      return result;
    }

    // 步骤2 & 3: 拼音匹配和模糊匹配
    if (_pinyinToText.isNotEmpty && (pinyinMatchEnabled || fuzzyMatchEnabled)) {
      result = _correctByHotwords(result);
    }

    return result;
  }

  /// 通过热词进行纠正（拼音匹配 + 模糊匹配）
  String _correctByHotwords(String text) {
    var result = text;

    // 按热词长度降序排列，优先匹配长词
    final sortedEntries = _pinyinToText.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    for (final entry in sortedEntries) {
      final hotwordPinyin = entry.key;
      final hotwordText = entry.value;
      final hotwordLen = hotwordText.length;

      // 滑动窗口查找
      var i = 0;
      while (i <= result.length - hotwordLen) {
        final segment = result.substring(i, i + hotwordLen);

        // 跳过已经正确的词
        if (segment == hotwordText) {
          i += hotwordLen;
          continue;
        }

        bool matched = false;

        // 优先尝试拼音匹配（同音字）
        if (pinyinMatchEnabled) {
          final segmentPinyin = _getPinyin(segment);
          if (segmentPinyin == hotwordPinyin) {
            result = result.substring(0, i) +
                hotwordText +
                result.substring(i + hotwordLen);
            matched = true;
          }
        }

        // 如果拼音不匹配，尝试模糊匹配
        if (!matched && fuzzyMatchEnabled) {
          final similarity = _similarity(segment, hotwordText);
          if (similarity >= fuzzyThreshold) {
            result = result.substring(0, i) +
                hotwordText +
                result.substring(i + hotwordLen);
            matched = true;
          }
        }

        i += matched ? hotwordLen : 1;
      }
    }

    return result;
  }

  /// 获取当前规则数量
  int get ruleCount => _corrections.length;

  /// 获取热词数量
  int get hotwordCount => _pinyinToText.length;

  /// 获取所有规则
  Map<String, String> get rules => Map.unmodifiable(_corrections);

  /// 获取所有热词映射
  Map<String, String> get pinyinMappings => Map.unmodifiable(_pinyinToText);
}

/// 全局文本纠错器单例
class GlobalTextCorrector {
  static final GlobalTextCorrector _instance = GlobalTextCorrector._();
  static GlobalTextCorrector get instance => _instance;

  final TextCorrector _corrector = TextCorrector();

  GlobalTextCorrector._();

  /// 配置纠错规则
  ///
  /// ```dart
  /// GlobalTextCorrector.instance.configure(
  ///   // 精确匹配替换
  ///   corrections: {
  ///     '川台': '窗台',
  ///   },
  ///   // 热词（自动生成拼音）
  ///   hotwords: ['实测实量', '窗台', '评估'],
  /// );
  /// ```
  void configure({
    Map<String, String>? corrections,
    List<String>? hotwords,
    bool? enabled,
    bool? pinyinMatchEnabled,
    bool? fuzzyMatchEnabled,
    double? fuzzyThreshold,
  }) {
    if (corrections != null) {
      _corrector.addCorrections(corrections);
    }
    if (hotwords != null) {
      _corrector.addHotwords(hotwords);
    }
    if (enabled != null) {
      _corrector.enabled = enabled;
    }
    if (pinyinMatchEnabled != null) {
      _corrector.pinyinMatchEnabled = pinyinMatchEnabled;
    }
    if (fuzzyMatchEnabled != null) {
      _corrector.fuzzyMatchEnabled = fuzzyMatchEnabled;
    }
    if (fuzzyThreshold != null) {
      _corrector.fuzzyThreshold = fuzzyThreshold;
    }
  }

  /// 从 JSON 文件异步加载热词
  ///
  /// JSON 文件格式（拼音 -> 文本）:
  /// ```json
  /// {
  ///   "shi ce shi liang": "实测实量",
  ///   "chuang tai": "窗台",
  ///   "ping gu": "评估"
  /// }
  /// ```
  Future<void> loadFromAsset(String assetPath) async {
    await _corrector.loadFromAsset(assetPath);
  }

  /// 从 JSON 字符串加载热词
  void loadFromJson(String jsonString) {
    _corrector.loadFromJson(jsonString);
  }

  /// 添加单条纠错规则
  void addRule(String wrong, String correct) {
    _corrector.addCorrection(wrong, correct);
  }

  /// 添加热词（自动生成拼音）
  void addHotword(String word) {
    _corrector.addHotwords([word]);
  }

  /// 批量添加热词（自动生成拼音）
  void addHotwords(List<String> words) {
    _corrector.addHotwords(words);
  }

  /// 添加热词映射（拼音 -> 文本）
  void addPinyinMapping(String pinyin, String text) {
    _corrector.addPinyinMapping(pinyin, text);
  }

  /// 批量添加热词映射
  void addPinyinMappings(Map<String, String> mappings) {
    _corrector.addPinyinMappings(mappings);
  }

  /// 纠正文本
  String correct(String text) => _corrector.correct(text);

  /// 拼音匹配纠正
  String pinyinCorrect(String text) => _corrector.pinyinCorrect(text);

  /// 是否启用
  bool get enabled => _corrector.enabled;
  set enabled(bool value) => _corrector.enabled = value;

  /// 是否启用拼音匹配
  bool get pinyinMatchEnabled => _corrector.pinyinMatchEnabled;
  set pinyinMatchEnabled(bool value) => _corrector.pinyinMatchEnabled = value;

  /// 是否启用模糊匹配
  bool get fuzzyMatchEnabled => _corrector.fuzzyMatchEnabled;
  set fuzzyMatchEnabled(bool value) => _corrector.fuzzyMatchEnabled = value;

  /// 模糊匹配阈值
  double get fuzzyThreshold => _corrector.fuzzyThreshold;
  set fuzzyThreshold(double value) => _corrector.fuzzyThreshold = value;

  /// 规则数量
  int get ruleCount => _corrector.ruleCount;

  /// 热词数量
  int get hotwordCount => _corrector.hotwordCount;

  /// 清空规则
  void clear() => _corrector.clear();
}
