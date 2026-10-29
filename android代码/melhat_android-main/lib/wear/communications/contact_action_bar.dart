import 'package:flutter/material.dart';

import '../core.dart';

class ContactActionBar extends StatelessWidget {
  const ContactActionBar({
    super.key,
    required this.onVoice,
    required this.onVideo,
    required this.onBroadcast,
    this.showVoice = true,
    this.showVideo = true,
    this.showBroadcast = true,
    this.voicePending = false,
    this.voicePendingLabel = '待联调',
    this.videoPending = false,
    this.broadcastPending = false,
  });

  final VoidCallback? onVoice, onVideo, onBroadcast;
  final bool showVoice, showVideo, showBroadcast;
  final bool voicePending, videoPending, broadcastPending;
  final String voicePendingLabel;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 1,
    shadowColor: WearColors.line,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (showVoice)
            _button(
              context,
              '设备语音${voicePending ? ' · $voicePendingLabel' : ''}',
              Icons.call_outlined,
              onVoice,
            ),
          if (showVoice && (showVideo || showBroadcast))
            const SizedBox(width: 8),
          if (showVideo)
            _button(
              context,
              '视频通话${videoPending ? ' · 待联调' : ''}',
              Icons.videocam_outlined,
              onVideo,
            ),
          if (showVideo && showBroadcast) const SizedBox(width: 8),
          if (showBroadcast)
            _button(
              context,
              '文字播报${broadcastPending ? ' · 待联调' : ''}',
              Icons.volume_up_outlined,
              onBroadcast,
            ),
        ],
      ),
    ),
  );

  Widget _button(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback? onTap,
  ) => Expanded(
    child: TextButton(
      style: TextButton.styleFrom(
        textStyle: Theme.of(context).textTheme.labelLarge,
        foregroundColor: WearColors.brand,
        backgroundColor: const Color(0xFFE8F1FF),
        disabledBackgroundColor: const Color(0xFFF0F3F8),
        disabledForegroundColor: WearColors.muted,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}
