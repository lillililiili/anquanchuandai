# Voice Recognizer

基于阿里 Paraformer-zh 模型的 Flutter 离线语音识别组件，支持语音录入、文本纠错等实用功能。

## 功能特性

- **离线识别**：基于 sherpa_onnx 的本地语音识别，无需网络连接
- **长按录音**：类似微信的交互方式，长按开始录音，松开结束识别
- **弹窗模式**：简洁的全屏语音录入弹窗，带有丰富的动画效果
- **按钮组件**：可直接嵌入页面的录音按钮
- **文本纠错**：支持拼音匹配和模糊匹配，自动修正识别错误
- **热词配置**：通过 JSON 文件配置热词，提高特定词汇识别准确率
- **丰富动画**：脉冲呼吸、波纹扩散、音量指示等动画效果
- **全局服务**：支持提前初始化，提升用户体验
- **跨平台**：支持 iOS 和 Android

## 安装

### 1. 添加依赖

```yaml
dependencies:
  voice_recognizer: ^1.0.0
```

或使用命令行：

```bash
flutter pub add voice_recognizer
```

### 2. 平台配置

#### iOS

在 `ios/Runner/Info.plist` 中添加麦克风权限：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>需要使用麦克风进行语音输入</string>
```

#### Android

在 `android/app/src/main/AndroidManifest.xml` 中添加权限：

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

### 3. 运行 flutter pub get

```bash
flutter pub get
```

## 使用方法

### 导入

```dart
import 'package:voice_recognizer/voice_recognizer.dart';
```

### 推荐：提前初始化

为了避免用户每次使用语音功能时等待模型加载，**强烈建议**在应用启动时提前初始化：

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 提前初始化语音识别服务（异步，不阻塞启动）
  VoiceRecognizerRegistry.instance.preInitialize();
  
  runApp(MyApp());
}
```

这样用户打开语音功能时就能立即使用，无需等待模型加载。

### 发热与耗电优化（移动端）

语音识别在设备上做神经网络推理，可能引起发热与耗电。可采取：

1. **推理线程数**：移动端已默认使用 1 个线程以减轻发热。若仍发热明显，可在初始化前显式配置：
   ```dart
   VoiceRecognizerRegistry.instance.configure(numThreads: 1);
   VoiceRecognizerRegistry.instance.preInitialize();
   ```
2. **避免连续长时间识别**：单次识别结束后留出间隔，避免短时间内多次长录音。
3. **缩短单次最长录音**：通过 `maxDuration` 限制单段时长（如 10 秒以内）。

### 方式一：使用按钮组件

最简单的使用方式，直接使用 `VoiceRecordButton` 组件：

```dart
VoiceRecordButton(
  themeColor: Theme.of(context).primaryColor,
  maxDuration: 10,
  showDuration: true,
  showRipple: true,
  enableHaptic: true,
  onResult: (text) {
    print('识别结果: $text');
  },
  onPartialResult: (text) {
    print('实时结果: $text');
  },
  onRecordingStateChanged: (isRecording) {
    print('录音状态: $isRecording');
  },
  onError: (error) {
    print('错误: $error');
  },
)
```

### 方式二：使用弹窗

使用 `showVoiceRecordOverlay` 显示全屏语音录入弹窗（新设计，只有背景动画和按钮）：

```dart
void _showVoiceInput() async {
  final result = await showVoiceRecordOverlay(
    context: context,
    themeColor: Theme.of(context).primaryColor,
    maxDuration: 10,
  );

  if (result != null && result.isNotEmpty) {
    print('识别结果: $result');
  }
}
```

弹窗交互：
- 长按按钮开始录音
- 松开按钮结束录音并自动识别
- 录音中或识别中点击外部不会退出
- 没有录音时点击外部区域退出弹窗
- 识别成功后自动返回结果

### 方式三：集成到输入框

将语音输入集成到 TextField：

```dart
TextField(
  controller: _controller,
  decoration: InputDecoration(
    hintText: '输入或语音输入...',
    suffixIcon: IconButton(
      icon: Icon(Icons.mic),
      onPressed: () async {
        final result = await showVoiceRecordOverlay(
          context: context,
          maxDuration: 10,
        );
        if (result != null) {
          _controller.text = result;
        }
      },
    ),
  ),
)
```

## 文本纠错

`GlobalTextCorrector` 提供了语音识别结果的纠错功能，支持三种匹配模式：

1. **精确匹配** - 直接字符串替换
2. **拼音匹配** - 同音字自动纠正
3. **模糊匹配** - 基于编辑距离的相似词纠正

### 配置热词（推荐方式）

创建 JSON 文件（如 `assets/hotwords.json`），格式为 `拼音 -> 正确文本`：

```json
{
  "shi ce shi liang": "实测实量",
  "chuang tai": "窗台",
  "ping gu": "评估"
}
```

在应用启动时加载：

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 加载热词文件
  await GlobalTextCorrector.instance.loadFromAsset('assets/hotwords.json');
  
  // 初始化语音识别
  VoiceRecognizerRegistry.instance.preInitialize();
  
  runApp(MyApp());
}
```

在识别结果中使用纠错：

```dart
// 方式一：自动纠错（在组件内部）
// showVoiceRecordOverlay 已自动纠错

// 方式二：手动纠错
final corrected = GlobalTextCorrector.instance.correct(recognizedText);
```

### 配置纠错参数

```dart
GlobalTextCorrector.instance.configure(
  enabled: true,              // 是否启用纠错
  pinyinMatchEnabled: true,   // 是否启用拼音匹配
  fuzzyMatchEnabled: true,     // 是否启用模糊匹配
  fuzzyThreshold: 0.7,        // 模糊匹配阈值（0.0-1.0）
);
```

### 动态添加热词

```dart
// 添加单个热词（自动生成拼音）
GlobalTextCorrector.instance.addHotword('实测实量');

// 批量添加热词
GlobalTextCorrector.instance.addHotwords(['实测实量', '窗台', '评估']);

// 添加拼音映射（已知拼音时）
GlobalTextCorrector.instance.addPinyinMapping('shi ce shi liang', '实测实量');
```

## API 文档

### VoiceRecordButton

长按录音按钮组件。

| 属性 | 类型 | 默认值 | 说明 |
|-----|------|-------|------|
| `onResult` | `Function(String)?` | - | 识别结果回调 |
| `onPartialResult` | `Function(String)?` | - | 实时识别结果回调 |
| `onRecordingStateChanged` | `Function(bool)?` | - | 录音状态变化回调 |
| `onError` | `Function(String)?` | - | 错误回调 |
| `themeColor` | `Color?` | 主题色 | 按钮主题颜色 |
| `size` | `double` | 64 | 按钮大小 |
| `maxDuration` | `int` | 10 | 最大录音时长（秒） |
| `showDuration` | `bool` | true | 是否显示录音时长 |
| `showRipple` | `bool` | true | 是否显示波纹动画 |
| `enableHaptic` | `bool` | true | 是否启用触感反馈 |
| `icon` | `IconData?` | - | 自定义按钮图标 |
| `useGlobalService` | `bool` | true | 是否使用全局服务（推荐开启） |

### showVoiceRecordOverlay

显示语音录入弹窗。

```dart
Future<String?> showVoiceRecordOverlay({
  required BuildContext context,
  Color? themeColor,
  int maxDuration = 10,
  bool useGlobalService = true,
})
```

返回识别结果文本（已自动纠错），如果取消则返回 `null`。

### VoiceRecognizerRegistry

语音识别服务注册中心，提供全局单例管理，支持提前初始化。

```dart
// 配置（可选，需要在初始化前调用）
VoiceRecognizerRegistry.instance.configure(
  modelAssetPath: 'your/custom/path',
  modelFileName: 'model.onnx',
  numThreads: 1,  // 移动端建议 1 以减轻发热
  tokensFileName: 'tokens.txt',
);

// 提前初始化（异步，不阻塞）
VoiceRecognizerRegistry.instance.preInitialize();

// 等待初始化完成
await VoiceRecognizerRegistry.instance.ensureInitialized();

// 查询状态
if (VoiceRecognizerRegistry.instance.isInitialized) {
  // 已初始化完成
}

// 获取识别器实例
final recognizer = VoiceRecognizerRegistry.instance.recognizer;

// 重置服务
VoiceRecognizerRegistry.instance.reset();
```

| 属性/方法 | 类型 | 说明 |
|----------|------|------|
| `instance` | `VoiceRecognizerRegistry` | 单例实例 |
| `isInitialized` | `bool` | 是否已初始化完成 |
| `isInitializing` | `bool` | 是否正在初始化 |
| `hasError` | `bool` | 是否初始化失败 |
| `errorMessage` | `String?` | 错误信息 |
| `recognizer` | `SimpleParaformerRecognizer?` | 识别器实例 |
| `configure()` | `void` | 配置参数（需在初始化前调用） |
| `preInitialize()` | `Future<bool>` | 提前异步初始化 |
| `ensureInitialized()` | `Future<bool>` | 确保已初始化（会自动触发初始化） |
| `reset()` | `void` | 重置服务，释放资源 |

### GlobalTextCorrector

全局文本纠错器，支持拼音匹配和模糊匹配。

```dart
// 从 JSON 文件加载热词
await GlobalTextCorrector.instance.loadFromAsset('assets/hotwords.json');

// 从 JSON 字符串加载热词
GlobalTextCorrector.instance.loadFromJson('{"pin yin": "拼音"}');

// 配置参数
GlobalTextCorrector.instance.configure(
  enabled: true,
  pinyinMatchEnabled: true,
  fuzzyMatchEnabled: true,
  fuzzyThreshold: 0.7,
);

// 纠正文本
final corrected = GlobalTextCorrector.instance.correct('识别结果');

// 动态添加热词
GlobalTextCorrector.instance.addHotword('实测实量');

// 批量添加热词
GlobalTextCorrector.instance.addHotwords(['实测实量', '窗台']);

// 添加拼音映射
GlobalTextCorrector.instance.addPinyinMapping('shi ce shi liang', '实测实量');

// 获取状态
print('热词数量: ${GlobalTextCorrector.instance.hotwordCount}');

// 清空规则
GlobalTextCorrector.instance.clear();
```

| 属性/方法 | 类型 | 说明 |
|----------|------|------|
| `instance` | `GlobalTextCorrector` | 单例实例 |
| `enabled` | `bool` | 是否启用纠错 |
| `pinyinMatchEnabled` | `bool` | 是否启用拼音匹配 |
| `fuzzyMatchEnabled` | `bool` | 是否启用模糊匹配 |
| `fuzzyThreshold` | `double` | 模糊匹配阈值（0.0-1.0） |
| `ruleCount` | `int` | 精确匹配规则数量 |
| `hotwordCount` | `int` | 热词数量 |
| `correct()` | `String` | 纠正文本 |
| `loadFromAsset()` | `Future<void>` | 从 JSON 文件加载热词 |
| `loadFromJson()` | `void` | 从 JSON 字符串加载热词 |
| `configure()` | `void` | 配置纠错参数 |
| `addHotword()` | `void` | 添加单个热词 |
| `addHotwords()` | `void` | 批量添加热词 |
| `addPinyinMapping()` | `void` | 添加拼音映射 |
| `clear()` | `void` | 清空所有规则 |

### SimpleParaformerRecognizer

简化版离线识别器。

```dart
final recognizer = SimpleParaformerRecognizer();

await recognizer.initialize();
recognizer.startListening();

// 录音过程中处理音频
recognizer.processAudioData(pcmData);

// 停止并获取结果
final result = await recognizer.stopListening();
print(result.text);
```

## 动画组件

包内提供了多个可复用的动画组件：

### PulseAnimation

脉冲呼吸动画效果。

```dart
PulseAnimation(
  isAnimating: true,
  minScale: 1.0,
  maxScale: 1.15,
  child: YourWidget(),
)
```

### RippleAnimation

波纹扩散动画效果。

```dart
RippleAnimation(
  isAnimating: true,
  color: Colors.blue,
  size: 120,
  ringCount: 3,
)
```

### SoundLevelIndicator

音量指示器（圆环显示）。

```dart
SoundLevelIndicator(
  level: 0.5,  // 0.0 - 1.0
  color: Colors.blue,
  size: 100,
)
```

### WaveformDisplay

波形显示组件。

```dart
WaveformDisplay(
  soundLevel: 0.5,
  color: Colors.blue,
  height: 60,
  isActive: true,
)
```

## 模型说明

本组件使用阿里 Paraformer-zh 中文语音识别模型：

- **模型文件**：`model.int8.onnx` (量化后的 ONNX 模型)
- **词表文件**：`tokens.txt`
- **采样率**：16000 Hz
- **支持语言**：中文、英文
- **解码方式**：greedy_search（Paraformer 模型不支持热词功能）

模型文件位于 `assets/` 目录下，首次使用时会自动复制到临时目录。

## 注意事项

1. **提前初始化**：强烈建议在应用启动时调用 `VoiceRecognizerRegistry.instance.preInitialize()`，避免用户使用时等待
2. **首次初始化**：首次使用时会将模型文件从 assets 复制到临时目录，可能需要几秒钟
3. **内存占用**：模型加载后会占用 50-100MB 内存，可通过 `VoiceRecognizerRegistry.instance.reset()` 释放
4. **录音权限**：使用前需要获取麦克风权限
5. **最大时长**：建议设置合理的最大录音时长（默认 10 秒），避免生成过大的音频数据
6. **热词说明**：Paraformer 模型不支持原生热词功能，本组件通过 `GlobalTextCorrector` 进行后处理实现热词纠错
7. **全局服务**：`useGlobalService` 默认开启，会复用已初始化的识别器实例，节省资源

## 依赖

- `sherpa_onnx: ^1.12.23` - ONNX 语音识别引擎
- `record: ^6.1.2` - 跨平台音频录制
- `permission_handler: ^11.3.1` - 权限管理
- `path_provider: ^2.1.4` - 路径获取
- `lpinyin: ^2.0.3` - 汉字转拼音

## 许可证

MIT License
