final _deliveryUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _email = RegExp(
  r'^[A-Za-z0-9_+%-]+(?:\.[A-Za-z0-9_+%-]+)*@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$',
);

List<String>? validatedReportRecipients(String input) {
  final addresses = input
      .trim()
      .split(RegExp(r'[,\n]'))
      .map((e) => e.trim())
      .toList();
  if (addresses.isEmpty || addresses.length > 5) return null;
  final normalized = <String>[];
  for (final address in addresses) {
    final parts = address.split('@');
    if (address.length > 254 ||
        !_email.hasMatch(address) ||
        parts.length != 2 ||
        parts.first.length > 64 ||
        parts.last
            .split('.')
            .any(
              (label) =>
                  label.length > 63 ||
                  label.startsWith('-') ||
                  label.endsWith('-'),
            )) {
      return null;
    }
    normalized.add(address.toLowerCase());
  }
  if (normalized.toSet().length != normalized.length) return null;
  normalized.sort();
  return normalized;
}

class CloudReportDelivery {
  const CloudReportDelivery(
    this.id,
    this.previewId,
    this.recipients,
    this.state,
    this.createdAt,
  );
  final String id, previewId, state;
  final List<String> recipients;
  final DateTime createdAt;

  factory CloudReportDelivery.fromJson(
    Map<String, dynamic> json,
    String expectedPreviewId,
  ) {
    final id = json['id'];
    final previewId = json['preview_id'];
    final state = json['state'];
    final rawRecipients = json['recipients'];
    final created = json['created_at'];
    if (id is! String ||
        !_deliveryUuid.hasMatch(id) ||
        previewId != expectedPreviewId ||
        !{'pending', 'sent'}.contains(state) ||
        rawRecipients is! List ||
        rawRecipients.any((e) => e is! String) ||
        created is! String) {
      throw const FormatException('Invalid report delivery response');
    }
    final recipients = validatedReportRecipients(
      rawRecipients.cast<String>().join(','),
    );
    final createdAt = DateTime.tryParse(created);
    if (recipients == null || createdAt == null) {
      throw const FormatException('Invalid report delivery response');
    }
    return CloudReportDelivery(
      id,
      previewId as String,
      List.unmodifiable(recipients),
      state as String,
      createdAt,
    );
  }
}
