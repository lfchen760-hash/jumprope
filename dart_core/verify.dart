/// 用黄金向量验证 Dart 移植版与 JS 版是否完全一致。
///
///   dart verify.dart ../jumprope/test/golden
import 'dart:convert';
import 'dart:io';

import 'lib/counter.dart';

void main(List<String> args) {
  final dir = args.isNotEmpty ? args[0] : '../jumprope/test/golden';
  final List<File> files;
  final ent = FileSystemEntity.typeSync(dir);
  if (ent == FileSystemEntityType.file) {
    files = [File(dir)];
  } else {
    files = Directory(dir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  if (args.contains('--count')) {
    final data = jsonDecode(files.first.readAsStringSync()) as Map<String, dynamic>;
    final counter = Counter();
    for (final fr in (data['frames'] as List)) {
      final f7 = fr as List;
      counter.feed((f7[1] as num).toDouble(), (f7[2] as num).toDouble(),
          (f7[0] as num).toDouble(),
          PoseContext(
              hipX: (f7[3] as num).toDouble(),
              tilt: (f7[4] as num).toDouble(),
              kneeL: (f7[5] as num).toDouble(),
              kneeR: (f7[6] as num).toDouble()));
    }
    print(counter.count);
    exit(0);
  }

  if (files.isEmpty) {
    stderr.writeln('没有找到向量文件: $dir');
    exit(1);
  }

  var allPass = true;

  print('${'向量'.padRight(18)}${'标注'.padLeft(6)}${'JS期望'.padLeft(8)}'
      '${'Dart'.padLeft(8)}  结果');
  print('-' * 56);

  for (final f in files) {
    final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final name = data['name'] as String;
    final labelCount = (data['labelCount'] as num?)?.toInt() ?? 0;
    final expected = (data['expected'] as num?);
    final frames = data['frames'] as List;

    final counter = Counter();
    for (final fr in frames) {
      final f7 = fr as List;
      final t = (f7[0] as num).toDouble();
      final hipY = (f7[1] as num).toDouble();
      final torso = (f7[2] as num).toDouble();
      final hipX = (f7[3] as num).toDouble();
      final tilt = (f7[4] as num).toDouble();
      final kneeL = (f7[5] as num).toDouble();
      final kneeR = (f7[6] as num).toDouble();
      counter.feed(hipY, torso, t,
          PoseContext(hipX: hipX, tilt: tilt, kneeL: kneeL, kneeR: kneeR));
    }

    final ok = expected == null || counter.count == expected;
    if (!ok) allPass = false;
    print('${name.padRight(18)}${labelCount.toString().padLeft(6)}'
        '${(expected ?? '-').toString().padLeft(8)}'
        '${counter.count.toString().padLeft(8)}  ${ok ? '✅' : '❌ 不一致'}');
  }

  print('-' * 56);
  print(allPass ? '全部一致 ✅' : '存在不一致 ❌');
  exit(allPass ? 0 : 1);
}
