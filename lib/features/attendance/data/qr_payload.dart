import 'dart:convert';

/// The contents of a member's QR membership card (brain.md §6.2).
///
/// Encoded as a compact JSON object with a version tag so the format can change
/// without old cards scanning as garbage:
///
/// ```json
/// {"v":1,"id":"<member uuid>","n":"<full name>"}
/// ```
///
/// **This is an identifier, not a credential.** Anyone who can read the code can
/// reproduce it, exactly like a printed membership number. The card is scanned
/// by gym staff on a staff-authenticated device, and the server still applies
/// RLS to the resulting write, so a forged card cannot create attendance a real
/// card could not. The name is embedded only so the scanner can show who was
/// scanned while offline, before any database lookup.
///
/// Signing the payload was considered and rejected: it would need a shared
/// secret on every member device, which is a larger exposure than the thing it
/// protects.
class QrPayload {
  const QrPayload({required this.memberId, required this.fullName});

  /// Current payload version.
  static const int version = 1;

  final String memberId;
  final String fullName;

  /// The string to render as a QR code.
  String encode() => jsonEncode({
    'v': version,
    'id': memberId,
    'n': fullName,
  });

  /// Parses a scanned code, or returns null if it is not one of our cards.
  ///
  /// Scanners pick up every barcode in view — shop labels, other apps' codes —
  /// so this must reject anything unrecognised rather than throwing.
  static QrPayload? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }

    if (decoded is! Map<String, dynamic>) return null;

    // Reject a newer format rather than misreading its fields.
    final version = decoded['v'];
    if (version is! int || version > QrPayload.version) return null;

    final id = decoded['id'];
    if (id is! String || id.isEmpty) return null;

    final name = decoded['n'];

    return QrPayload(
      memberId: id,
      fullName: name is String ? name : '',
    );
  }
}
