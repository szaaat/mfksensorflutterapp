import 'dart:async';
import 'dart:io';

extension StringExtensions on String {
  Future<void> appendLineToFile(File file) async {
    await ('\$this\n').appendToFile(file);
  }

  Future<void> appendToFile(File file) async {
    try {
      if (await file.exists()) {
        // Append to existing file
        final sink = file.openWrite(mode: FileMode.append);
        sink.write(this);
        await sink.close();
      } else {
        // Create new file
        await file.writeAsString(this);
      }
    } catch (e) {
      throw Exception('Failed to write to file: \$e');
    }
  }
}
