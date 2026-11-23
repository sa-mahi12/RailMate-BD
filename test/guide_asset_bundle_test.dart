import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bundled guide can load every local script it references', (
    WidgetTester tester,
  ) async {
    await tester.runAsync(() async {
      // Load the generated Flutter asset bundle, not source files on disk.
      // Omitting a guide module from pubspec breaks the actual WebView load.
      final String html = await rootBundle.loadString('web-guide/index.html');
      final Iterable<String> scripts = RegExp(r'<script\b[^>]*\bsrc="([^"]+)"')
          .allMatches(html)
          .map((RegExpMatch match) => match.group(1)!);
      final List<String> localScripts = scripts
          .where((String script) => !Uri.parse(script).hasScheme)
          .toList();
      expect(localScripts, isNotEmpty);
      for (final String script in localScripts) {
        final ByteData bytes = await rootBundle.load('web-guide/$script');
        expect(bytes.lengthInBytes, greaterThan(0), reason: script);
      }
    });
  });
}
