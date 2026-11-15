import 'package:flutter_test/flutter_test.dart';
import 'package:jumprope_app/data/chinese_number.dart';

void main() {
  test('个位与十位', () {
    expect(numberToChinese(0), '零');
    expect(numberToChinese(3), '三');
    expect(numberToChinese(10), '十');
    expect(numberToChinese(11), '十一');
    expect(numberToChinese(20), '二十');
    expect(numberToChinese(99), '九十九');
  });

  test('百位', () {
    expect(numberToChinese(100), '一百');
    expect(numberToChinese(101), '一百零一');
    expect(numberToChinese(110), '一百一十');
    expect(numberToChinese(111), '一百一十一');
    expect(numberToChinese(999), '九百九十九');
  });

  test('千位与万', () {
    expect(numberToChinese(1000), '一千');
    expect(numberToChinese(1001), '一千零一');
    expect(numberToChinese(1010), '一千零一十');
    expect(numberToChinese(10000), '一万');
    expect(numberToChinese(110000), '十一万');
  });
}
