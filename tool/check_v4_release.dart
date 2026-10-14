import 'dart:io';

import 'release_evidence.dart';

/// One-off P34 gate check: validates the REAL published v1.0.0+4 manifest +
/// SHA256SUMS against the parser rules. Not part of `flutter test` (it reads
/// files downloaded from the release).
///
/// Usage:
///   dart run tool/check_v4_release.dart <release-manifest.json> <SHA256SUMS.txt>
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('usage: check_v4_release.dart <manifest> <sums>');
    exit(2);
  }
  final evidence = ReleaseEvidence.parse(
    manifestJson: await File(args[0]).readAsString(),
    sha256Sums: await File(args[1]).readAsString(),
  );
  void check(bool ok, String message) {
    if (!ok) {
      stderr.writeln('EVIDENCE FAIL: $message');
      exit(1);
    }
  }

  check(evidence.versionName == '1.0.0', 'versionName is 1.0.0');
  check(evidence.versionCode == 4, 'versionCode is 4');
  check(evidence.apkCount == 4, 'exactly 4 APKs published');
  check(evidence.hasAab, 'an AAB is published');
  check(evidence.hasUniversalApk, 'a universal APK is published');
  check(
    isMonotonicVersionCode(previous: 3, next: evidence.versionCode),
    'build 4 is a valid update over the published build 3',
  );
  final distinct = evidence.artifacts.map((a) => a.sha256).toSet();
  check(
    distinct.length == evidence.artifacts.length,
    'every artifact has a distinct digest',
  );
  // ignore: avoid_print
  print(
    'v1.0.0+4 evidence OK: ${evidence.artifacts.length} artifacts, '
    'code ${evidence.versionCode}, commit ${evidence.commit}',
  );
}
