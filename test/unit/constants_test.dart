import 'package:flutter_test/flutter_test.dart';
import 'package:iron_yard/core/constants/app_constants.dart';

void main() {
  group('UserRole', () {
    test('parses known wire values', () {
      expect(UserRole.fromString('admin'), UserRole.admin);
      expect(UserRole.fromString('trainer'), UserRole.trainer);
      expect(UserRole.fromString('member'), UserRole.member);
    });

    test('returns null for unknown or missing values', () {
      expect(UserRole.fromString('owner'), isNull);
      expect(UserRole.fromString(null), isNull);
      expect(UserRole.fromString(''), isNull);
    });

    test('round-trips through wireValue', () {
      for (final role in UserRole.values) {
        expect(UserRole.fromString(role.wireValue), role);
      }
    });
  });

  group('AttendanceSource', () {
    test('uses snake_case wire values matching the attendance table', () {
      expect(AttendanceSource.qrScan.wireValue, 'qr_scan');
      expect(AttendanceSource.selfReported.wireValue, 'self_reported');
    });

    test('round-trips through wireValue', () {
      for (final source in AttendanceSource.values) {
        expect(AttendanceSource.fromString(source.wireValue), source);
      }
    });

    test('rejects the enum name for the multi-word value', () {
      // Guards against accidentally persisting `selfReported` instead of
      // `self_reported`, which would silently split attendance reporting.
      expect(AttendanceSource.fromString('selfReported'), isNull);
    });
  });

  group('PaymentMethod', () {
    test('round-trips through wireValue', () {
      for (final method in PaymentMethod.values) {
        expect(PaymentMethod.fromString(method.wireValue), method);
      }
    });

    test('exposes UPI as a distinct method', () {
      // pitch.md promises UPI as its own option; brain.md §6.5 lists only
      // cash/bank/external. Open question #4 in tasks.md.
      expect(PaymentMethod.fromString('upi'), PaymentMethod.upi);
      expect(PaymentMethod.upi.label, 'UPI');
    });

    test('every method has a non-empty label', () {
      for (final method in PaymentMethod.values) {
        expect(method.label, isNotEmpty);
      }
    });
  });
}
