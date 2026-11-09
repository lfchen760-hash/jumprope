import 'dart:math';

/// 非敏感设置。放同一个 SQLite 库，导出时一起带走。
class AppSettings {
  final bool onboardingDone;
  final bool voiceEnabled;
  final int voiceEvery; // 10 / 20 / 0(不报)
  final bool countSound;
  final bool keepAwake;
  final bool showSkeleton;
  final int? lastExportAtMs;
  final String installId;

  const AppSettings({
    required this.onboardingDone,
    required this.voiceEnabled,
    required this.voiceEvery,
    required this.countSound,
    required this.keepAwake,
    required this.showSkeleton,
    required this.lastExportAtMs,
    required this.installId,
  });

  factory AppSettings.defaults() => AppSettings(
    onboardingDone: false,
    voiceEnabled: true,
    voiceEvery: 10,
    countSound: false,
    keepAwake: true,
    showSkeleton: true,
    lastExportAtMs: null,
    installId: newInstallId(),
  );

  AppSettings copyWith({
    bool? onboardingDone,
    bool? voiceEnabled,
    int? voiceEvery,
    bool? countSound,
    bool? keepAwake,
    bool? showSkeleton,
    int? lastExportAtMs,
  }) => AppSettings(
    onboardingDone: onboardingDone ?? this.onboardingDone,
    voiceEnabled: voiceEnabled ?? this.voiceEnabled,
    voiceEvery: voiceEvery ?? this.voiceEvery,
    countSound: countSound ?? this.countSound,
    keepAwake: keepAwake ?? this.keepAwake,
    showSkeleton: showSkeleton ?? this.showSkeleton,
    lastExportAtMs: lastExportAtMs ?? this.lastExportAtMs,
    installId: installId,
  );

  Map<String, dynamic> toJson() => {
    'onboardingDone': onboardingDone,
    'voiceEnabled': voiceEnabled,
    'voiceEvery': voiceEvery,
    'countSound': countSound,
    'keepAwake': keepAwake,
    'showSkeleton': showSkeleton,
    'lastExportAt': lastExportAtMs,
    'installId': installId,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    final id = (j['installId'] as String?)?.trim() ?? '';
    return AppSettings(
      onboardingDone: j['onboardingDone'] == true,
      voiceEnabled: j['voiceEnabled'] != false,
      voiceEvery: (j['voiceEvery'] as num?)?.toInt() ?? 10,
      countSound: j['countSound'] == true,
      keepAwake: j['keepAwake'] != false,
      showSkeleton: j['showSkeleton'] != false,
      lastExportAtMs: (j['lastExportAt'] as num?)?.toInt(),
      installId: id.isEmpty ? newInstallId() : id,
    );
  }
}

String newInstallId() {
  final r = Random.secure();
  return List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
