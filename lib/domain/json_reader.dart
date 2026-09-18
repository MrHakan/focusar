/// Readers for values that came back off disk.
///
/// Stored state is only as good as the last write, and a half-written or
/// hand-edited preference should cost a default value rather than a crash on
/// launch. These never throw on a wrong type.
extension JsonReader on Map<String, dynamic> {
  double readDouble(String key, {double fallback = 0}) {
    final value = this[key];
    return value is num ? value.toDouble() : fallback;
  }

  int readInt(String key, {int fallback = 0}) {
    final value = this[key];
    return value is num ? value.toInt() : fallback;
  }

  bool readBool(String key, {bool fallback = false}) {
    final value = this[key];
    return value is bool ? value : fallback;
  }

  String? readString(String key) {
    final value = this[key];
    return value is String ? value : null;
  }

  Duration readDuration(String key) => Duration(seconds: readInt(key));

  DateTime? readDate(String key) {
    final value = readString(key);
    return value == null ? null : DateTime.tryParse(value);
  }

  List<Map<String, dynamic>> readObjects(String key) {
    final value = this[key];
    if (value is! List) return const [];
    return value.whereType<Map<String, dynamic>>().toList(growable: false);
  }
}
