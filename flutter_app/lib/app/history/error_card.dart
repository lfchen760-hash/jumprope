import 'package:flutter/material.dart';

import '../ui.dart';

/// 读取失败时的重试卡片。
class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(fontSize: 12, color: Color(0xFFC62828)),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              onRetry();
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
