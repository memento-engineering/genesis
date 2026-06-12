/// The dart:ui-shaped integer Rect (register A23): cell-space geometry with
/// `dart:ui` naming, no engine import.
library;

import 'package:genesis_typesetting/genesis_typesetting.dart';
import 'package:test/test.dart';

void main() {
  group('Rect', () {
    test('fromLTWH fields and exclusive right/bottom', () {
      const r = Rect.fromLTWH(2, 3, 10, 4);
      expect(r.left, 2);
      expect(r.top, 3);
      expect(r.width, 10);
      expect(r.height, 4);
      expect(r.right, 12, reason: 'right = left + width, exclusive');
      expect(r.bottom, 7, reason: 'bottom = top + height, exclusive');
      expect(r.isEmpty, isFalse);
    });

    test('contains is left/top-inclusive, right/bottom-exclusive '
        '(dart:ui semantics)', () {
      const r = Rect.fromLTWH(2, 3, 10, 4);
      expect(r.contains(2, 3), isTrue);
      expect(r.contains(11, 6), isTrue);
      expect(r.contains(12, 3), isFalse);
      expect(r.contains(2, 7), isFalse);
      expect(r.contains(1, 3), isFalse);
    });

    test('zero is empty and contains nothing', () {
      expect(Rect.zero.isEmpty, isTrue);
      expect(Rect.zero.contains(0, 0), isFalse);
    });

    test('value equality', () {
      expect(const Rect.fromLTWH(1, 2, 3, 4), const Rect.fromLTWH(1, 2, 3, 4));
      expect(
        const Rect.fromLTWH(1, 2, 3, 4),
        isNot(const Rect.fromLTWH(1, 2, 3, 5)),
      );
      expect(
        const Rect.fromLTWH(1, 2, 3, 4).hashCode,
        const Rect.fromLTWH(1, 2, 3, 4).hashCode,
      );
    });
  });
}
