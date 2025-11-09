// lib/utils/time_helper.dart

// Időkezelés helper függvények
extension DateTimeExtensions on DateTime {
  String toUtcIsoString() {
    return toUtc().toIso8601String();
  }

  String toLocalIsoString() {
    return toLocal().toIso8601String();
  }
}

// String konverzió
String convertToUtcIsoString(String localTimeString) {
  try {
    final localTime = DateTime.parse(localTimeString);
    return localTime.toUtc().toIso8601String();
  } catch (e) {
    // Ha a parse nem sikerül, visszatérünk az aktuális UTC idővel
    // Ez egy biztonsági háló, de érdemes lehet naplózni a hibát.
    print('Error parsing date string "$localTimeString": $e');
    return DateTime.now().toUtc().toIso8601String();
  }
}