/// 单个姿态关键点（归一化坐标）。
class Landmark {
  final double x;
  final double y;
  final double z;
  final double visibility;

  const Landmark(this.x, this.y, this.z, this.visibility);

  static const Landmark zero = Landmark(0, 0, 0, 1);
}
