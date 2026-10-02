/// MySQL can store the zero-date sentinel ('0000-00-00 00:00:00') instead of
/// NULL on older rows for any "stamped when this happened" timestamp column
/// — treat both as "not set".
bool isRealTimestamp(dynamic value) {
  final String v = value?.toString().trim() ?? '';
  return v.isNotEmpty && v != '0000-00-00 00:00:00';
}
