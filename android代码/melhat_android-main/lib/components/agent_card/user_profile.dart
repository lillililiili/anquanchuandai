import 'package:flutter/material.dart';

Widget buildUserProfile() {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        // 用户头像
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0x1410B981),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.person_outline,
            size: 24,
            color: Color(0xFF10B981),
          ),
        ),
        const SizedBox(width: 12),
        // 用户信息
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              '用户昵称',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
            SizedBox(height: 4),
            Text(
              '在线',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ],
    ),
  );
}
