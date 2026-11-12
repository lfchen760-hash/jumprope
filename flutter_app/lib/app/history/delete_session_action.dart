import 'package:flutter/material.dart';

import '../../data/data_repository.dart';
import '../../data/session_record.dart';
import '../../data/video_store.dart';
import 'delete_session.dart';

/// 确认后删除会话 + 录像，并提示结果；[onDeleted] 用来刷新首页/记录。
Future<void> deleteSessionAndRefresh(
  BuildContext context, {
  required DataRepository repo,
  required SessionRecord session,
  required VoidCallback onDeleted,
}) async {
  try {
    final ok = await confirmDeleteSession(
      context,
      repo: repo,
      session: session,
    );
    if (!ok) return;
    try {
      await VideoStore(repo).deleteForSession(session.id);
    } catch (_) {
      // 文件删不掉不影响会话删除
    }
    onDeleted();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('记录已删除')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('删除失败：$e')));
  }
}
