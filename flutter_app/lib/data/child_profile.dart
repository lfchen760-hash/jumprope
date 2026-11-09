enum Gender { male, female, unspecified }

Gender genderFromValue(Object? value) {
  for (final g in Gender.values) {
    if (g.name == value) return g;
  }
  return Gender.unspecified;
}

String genderLabel(Gender g) => switch (g) {
  Gender.male => '男生',
  Gender.female => '女生',
  Gender.unspecified => '不填',
};

/// 孩子档案。所有字段都可空；不填就不显示参考线。
class ChildProfile {
  static const String fallbackNickname = '小朋友';

  final String nickname;
  final int? birthYear;
  final int? grade; // 1..6
  final Gender gender;
  final bool showBenchmark;
  final int? createdAtMs;
  final int? updatedAtMs;

  const ChildProfile({
    this.nickname = fallbackNickname,
    this.birthYear,
    this.grade,
    this.gender = Gender.unspecified,
    this.showBenchmark = false,
    this.createdAtMs,
    this.updatedAtMs,
  });

  static const ChildProfile defaults = ChildProfile();

  int? get age {
    final y = birthYear;
    if (y == null) return null;
    final a = DateTime.now().year - y;
    return (a >= 3 && a <= 18) ? a : null;
  }

  bool get hasBenchmark => grade != null && gender != Gender.unspecified;

  String get displayGrade => grade == null ? '未填年级' : '$grade 年级';

  Map<String, dynamic> toMap() => {
    'nickname': nickname,
    'birth_year': birthYear,
    'grade': grade,
    'gender': gender.name,
    'show_benchmark': showBenchmark ? 1 : 0,
    'created_at': createdAtMs,
    'updated_at': updatedAtMs,
  };

  factory ChildProfile.fromMap(Map<String, dynamic> map) {
    final raw = (map['nickname'] as String?)?.trim() ?? '';
    return ChildProfile(
      nickname: raw.isEmpty ? fallbackNickname : raw,
      birthYear: _int(map['birth_year']),
      grade: _int(map['grade']),
      gender: genderFromValue(map['gender']),
      showBenchmark: _bool(map['show_benchmark']),
      createdAtMs: _int(map['created_at']),
      updatedAtMs: _int(map['updated_at']),
    );
  }

  ChildProfile copyWith({
    String? nickname,
    int? birthYear,
    int? grade,
    Gender? gender,
    bool? showBenchmark,
    int? updatedAtMs,
  }) => ChildProfile(
    nickname: nickname ?? this.nickname,
    birthYear: birthYear ?? this.birthYear,
    grade: grade ?? this.grade,
    gender: gender ?? this.gender,
    showBenchmark: showBenchmark ?? this.showBenchmark,
    createdAtMs: createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
  );
}

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v');

bool _bool(Object? v) => v == true || v == 1 || v == '1' || v == 'true';
