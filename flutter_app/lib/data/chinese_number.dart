const List<String> _digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
const List<String> _units = ['千', '百', '十', ''];

/// 阿拉伯数字 → 中文读法，避免 TTS 把 110 读成「幺幺零」。
///
/// 覆盖跳绳会用到的范围（0–99999）；超出也按万进位拼。
String numberToChinese(int n) {
  if (n < 0) return '负${numberToChinese(-n)}';
  if (n == 0) return '零';
  if (n >= 10000) {
    final high = n ~/ 10000;
    final low = n % 10000;
    final head = '${_under10000(high)}万';
    if (low == 0) return head;
    return '$head${low < 1000 ? '零' : ''}${_under10000(low)}';
  }
  return _under10000(n);
}

String _under10000(int n) {
  final digits = [n ~/ 1000, (n ~/ 100) % 10, (n ~/ 10) % 10, n % 10];
  final out = StringBuffer();
  var started = false;
  var pendingZero = false;

  for (var i = 0; i < 4; i++) {
    final d = digits[i];
    if (d == 0) {
      if (started && i < 3) pendingZero = true;
      continue;
    }
    if (pendingZero) {
      out.write('零');
      pendingZero = false;
    }
    // 10–19 读「十X」而不是「一十X」
    if (!(d == 1 && i == 2 && !started)) out.write(_digits[d]);
    out.write(_units[i]);
    started = true;
  }
  return out.toString();
}
