import 'package:flutter/material.dart';

import '../../data/data_repository.dart';
import '../../data/period.dart';
import '../../data/session_record.dart';

/// 弹确认框并删除；返回 true 表示已删除。
Future<bool> confirmDeleteSession(
  BuildContext context, {
  required DataRepository repo,
  required SessionRecord session,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('删除这条记录？'),
      content: Text(
        '${fullDate(session.localDate)} · ${session.count} 个\n删除后无法恢复。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFC62828)),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  await repo.deleteSession(session.id);
  return true;
}
