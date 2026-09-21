import 'package:flutter/material.dart';

/// 语音录制浮层 — 全屏遮罩 + 麦克风动画 + 音量指示
class VoiceOverlay extends StatefulWidget {
  final double audioLevel;
  final bool isProcessing;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  const VoiceOverlay({
    super.key,
    required this.audioLevel,
    required this.isProcessing,
    required this.onStop,
    required this.onCancel,
  });

  @override
  State<VoiceOverlay> createState() => _VoiceOverlayState();
}

class _VoiceOverlayState extends State<VoiceOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isCanceling = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        // 上滑超过 80px 进入取消区域
        if (details.delta.dy < -5 && !_isCanceling) {
          setState(() => _isCanceling = true);
        } else if (details.delta.dy > 5 && _isCanceling) {
          setState(() => _isCanceling = false);
        }
      },
      onVerticalDragEnd: (_) {
        if (_isCanceling) {
          widget.onCancel();
        } else {
          widget.onStop();
        }
      },
      onTap: () => widget.onStop(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: _isCanceling
            ? Colors.black.withValues(alpha: 0.7)
            : Colors.black.withValues(alpha: 0.5),
        child: SafeArea(
          child: Column(
            children: [
              // 取消提示区域
              Expanded(
                flex: 2,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _isCanceling ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cancel_rounded,
                          color: Colors.white70,
                          size: 40,
                        ),
                        SizedBox(height: 8),
                        Text(
                          '松手取消',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 中间：麦克风 + 音量指示 + 识别文本
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 麦克风脉冲动画
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: widget.isProcessing
                              ? const Color(0xFFF59E0B)
                              : _isCanceling
                                  ? Colors.grey
                                  : const Color(0xFFDC2626),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (widget.isProcessing
                                      ? const Color(0xFFF59E0B)
                                      : _isCanceling
                                          ? Colors.grey
                                          : const Color(0xFFDC2626))
                                  .withValues(alpha: 0.4),
                              blurRadius: 20,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: widget.isProcessing
                            ? const Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                            : const Icon(
                                Icons.mic,
                                color: Colors.white,
                                size: 36,
                              ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 音量波形指示器
                    _buildAudioWave(),

                    const SizedBox(height: 16),

                    // 状态提示
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        widget.isProcessing ? '识别中...' : '正在录音...',
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 底部提示
              Expanded(
                flex: 2,
                child: Center(
                  child: Text(
                    widget.isProcessing ? '正在识别...' : '松手发送，上滑取消',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioWave() {
    final barCount = 30;
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(barCount, (i) {
          final distance = (i - barCount / 2).abs() / (barCount / 2);
          final height =
              (1.0 - distance * 0.6) * widget.audioLevel * 40 + 2;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 3,
            height: height.clamp(2.0, 40.0),
            decoration: BoxDecoration(
              color: _isCanceling
                  ? Colors.white24
                  : const Color(0xFFDC2626).withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(1.5),
            ),
          );
        }),
      ),
    );
  }
}
