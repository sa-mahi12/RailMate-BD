import 'package:flutter_test/flutter_test.dart';

import '../tool/release_evidence.dart';

/// V4 P30 — release-evidence validation rules (hermetic: synthetic JSON, no
/// network, no real release required).
void main() {
  const String longDigestA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const String longDigestB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const String longDigestD =
      'dddddddddddddddddddddddddddddddd'
      'dddddddddddddddddddddddddddddddd';
  const String longDigestE =
      'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
      'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';

  String manifest({
    String appName = 'RailMate BD',
    String sha = longDigestA,
    List<String>? artifacts,
    String signed = 'true',
  }) {
    final List<String> names =
        artifacts ??
        <String>[
          'RailMate-BD-1.0.0-universal.apk',
          'RailMate-BD-1.0.0-arm64-v8a.apk',
          'RailMate-BD-1.0.0.aab',
          'SHA256SUMS.txt',
          'release-manifest.json',
        ];
    return '''
{
  "appName": "$appName",
  "package": "bd.railmate.railmate_bd",
  "versionName": "1.0.0",
  "versionCode": 2,
  "commit": "0badc0de0badc0de0badc0de0badc0de0badc0de",
  "signed": $signed,
  "sha256": "$sha",
  "artifacts": [${names.map((String n) => '"$n"').join(',')}]
}
''';
  }

  String sums(List<String>? names) {
    final List<String> files =
        names ??
        <String>[
          'RailMate-BD-1.0.0-universal.apk',
          'RailMate-BD-1.0.0-arm64-v8a.apk',
          'RailMate-BD-1.0.0.aab',
          'SHA256SUMS.txt',
          'release-manifest.json',
        ];
    final StringBuffer buffer = StringBuffer();
    for (final String name in files) {
      buffer.writeln('$longDigestB  $name');
    }
    return buffer.toString();
  }

  /// The exact manifest shape `.github/workflows/release.yml` emits today
  /// (a `key=value` block, verified against the real `v1.0.0+3` download).
  String realWorldManifest({List<String>? artifacts}) {
    final List<String> names =
        artifacts ??
        <String>[
          'RailMate-BD-1.0.0-arm64-v8a.apk',
          'RailMate-BD-1.0.0-armeabi-v7a.apk',
          'RailMate-BD-1.0.0-universal.apk',
          'RailMate-BD-1.0.0-x86_64.apk',
          'RailMate-BD-1.0.0.aab',
        ];
    final StringBuffer buffer = StringBuffer()
      ..writeln('appName=RailMate BD')
      ..writeln('package=bd.railmate.railmate_bd')
      ..writeln('versionName=1.0.0')
      ..writeln('versionCode=3')
      ..writeln('commit=5107c059575b250b4ad5ba1088a310653ae7bb4c')
      ..writeln('builtBy=GitHub Actions release workflow')
      ..writeln('signed=true')
      ..writeln('supabaseUrl=https://psuzlyingfmstnyfvlnj.supabase.co')
      ..writeln('artifacts:');
    for (final String name in names) {
      buffer.writeln('  - $name');
    }
    return buffer.toString();
  }

  /// Real `SHA256SUMS.txt` from the v1.0.0+3 release (digests copied from the
  /// published file; entries keep the leading `./` sha256sum emits).
  const String realWorldSums =
      ''
      'e65311d9541d62ee0753ae121b831af9ad494336784b1c00a7feb45df8bee665  '
      './RailMate-BD-1.0.0-arm64-v8a.apk\n'
      '4b4fd4122eab8d7eaf735573a33d2f3f9db6c17bf990510a1157023ef4a0d38f  '
      './RailMate-BD-1.0.0-armeabi-v7a.apk\n'
      '7a679eebb9814da6b197e04705e29ce37f275ffdb59232a6e6d75d39439d464c  '
      './RailMate-BD-1.0.0-universal.apk\n'
      '0a5436c64f158ac6fa7e480e96421e750b80e179a568e065460bcb5d8d38ca07  '
      './RailMate-BD-1.0.0-x86_64.apk\n'
      '6b4e14a2de52e81849941c5b345434f782750684aab61835410c921df4d35149  '
      './RailMate-BD-1.0.0.aab\n';

  group('REAL published v1.0.0+3 evidence', () {
    test(
      'parses the actual workflow output, including ./ prefixed digests',
      () {
        final ReleaseEvidence evidence = ReleaseEvidence.parse(
          manifestJson: realWorldManifest(),
          sha256Sums: realWorldSums,
        );
        expect(evidence.appName, 'RailMate BD');
        expect(evidence.packageName, 'bd.railmate.railmate_bd');
        expect(evidence.versionName, '1.0.0');
        expect(evidence.versionCode, 3);
        expect(evidence.signed, isTrue);
        expect(evidence.apkCount, 4);
        expect(evidence.hasAab, isTrue);
        expect(evidence.hasUniversalApk, isTrue);
        expect(evidence.artifacts.length, 5);
        // The universal APK digest is the one a user verifies before install.
        final ReleaseArtifact universal = evidence.artifacts.firstWhere(
          (ReleaseArtifact a) => a.isUniversalApk,
        );
        expect(
          universal.sha256,
          '7a679eebb9814da6b197e04705e29ce37f275ffdb59232a6e6d75d39439d464c',
        );
      },
    );

    test('the real digests are all distinct 64-char hex', () {
      final ReleaseEvidence evidence = ReleaseEvidence.parse(
        manifestJson: realWorldManifest(),
        sha256Sums: realWorldSums,
      );
      final Set<String> digests = evidence.artifacts
          .map((ReleaseArtifact a) => a.sha256)
          .toSet();
      expect(digests.length, evidence.artifacts.length);
      for (final String digest in digests) {
        expect(digest.length, 64);
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(digest), isTrue);
      }
    });

    test('versionCode 3 is a valid update over the published build 2', () {
      expect(isMonotonicVersionCode(previous: 2, next: 3), isTrue);
    });
  });

  group('ReleaseEvidence.parse', () {
    test('accepts a complete, consistent manifest', () {
      final ReleaseEvidence evidence = ReleaseEvidence.parse(
        manifestJson: manifest(),
        sha256Sums: sums(null),
      );
      expect(evidence.appName, 'RailMate BD');
      expect(evidence.packageName, 'bd.railmate.railmate_bd');
      expect(evidence.versionName, '1.0.0');
      expect(evidence.versionCode, 2);
      expect(evidence.commit, '0badc0de0badc0de0badc0de0badc0de0badc0de');
      expect(evidence.signed, isTrue);
      expect(evidence.apkCount, 2);
      expect(evidence.hasAab, isTrue);
      expect(evidence.hasUniversalApk, isTrue);
      expect(evidence.artifacts.length, 5);
    });

    test('REJECT: every listed artifact must carry a sha256 digest', () {
      // This is the guarantee behind "signed" evidence: the manifest may
      // claim signed=true, but a listed artifact with no digest is
      // unverifiable and must fail the parse.
      expect(
        () => ReleaseEvidence.parse(
          manifestJson: manifest(),
          sha256Sums: sums(<String>['RailMate-BD-1.0.0.aab']),
        ),
        throwsFormatException,
      );
      expect(
        () => ReleaseEvidence.parse(manifestJson: manifest(), sha256Sums: ''),
        throwsFormatException,
      );
    });

    test('REJECT: artifact with no sha256 entry', () {
      expect(
        () => ReleaseEvidence.parse(
          manifestJson: manifest(),
          sha256Sums: sums(<String>['RailMate-BD-1.0.0.aab']),
        ),
        throwsFormatException,
      );
    });

    test('REJECT: artifact name contradicting the declared app name', () {
      expect(
        () => ReleaseEvidence.parse(
          manifestJson: manifest(artifacts: <String>['SomeOtherApp-1.0.0.apk']),
          sha256Sums: sums(<String>['SomeOtherApp-1.0.0.apk']),
        ),
        throwsFormatException,
      );
    });

    test('REJECT: empty or malformed artifact list', () {
      expect(
        () => ReleaseEvidence.parse(
          manifestJson: manifest(artifacts: <String>[]),
          sha256Sums: sums(null),
        ),
        throwsFormatException,
      );
    });

    test('REJECT: missing required manifest fields', () {
      const String noPackage =
          '{"appName":"RailMate-BD","versionName":"1.0.0",'
          '"versionCode":1,"commit":"abc","signed":false,"artifacts":["a"]}';
      expect(
        () => ReleaseEvidence.parse(
          manifestJson: noPackage,
          sha256Sums: '${'c' * 64}  a\n',
        ),
        throwsFormatException,
      );
    });

    test('REJECT: invalid JSON', () {
      expect(
        () => ReleaseEvidence.parse(manifestJson: 'not json', sha256Sums: ''),
        throwsFormatException,
      );
    });

    test('accepts binary-mode sha256sum lines (star prefix)', () {
      final String starSums = '$longDigestD *RailMate-BD-1.0.0.aab\n';
      final ReleaseEvidence evidence = ReleaseEvidence.parse(
        manifestJson: manifest(artifacts: <String>['RailMate-BD-1.0.0.aab']),
        sha256Sums: starSums,
      );
      expect(evidence.artifacts.single.sha256, longDigestD);
    });
  });

  group('fromListing installability rule', () {
    List<ReleaseArtifact> artifacts(List<String> names) => <ReleaseArtifact>[
      for (final String n in names)
        ReleaseArtifact(name: n, sizeBytes: 1, sha256: longDigestE),
    ];

    test('a release must ship something installable', () {
      expect(
        () => ReleaseEvidence.fromListing(
          appName: 'RailMate-BD',
          packageName: 'bd.railmate.railmate_bd',
          versionName: '1.0.0',
          versionCode: 2,
          commit: 'abc',
          artifacts: artifacts(<String>['SHA256SUMS.txt']),
        ),
        throwsFormatException,
      );
      expect(
        () => ReleaseEvidence.fromListing(
          appName: 'RailMate-BD',
          packageName: 'bd.railmate.railmate_bd',
          versionName: '1.0.0',
          versionCode: 2,
          commit: 'abc',
          artifacts: artifacts(<String>[]),
        ),
        throwsFormatException,
      );
    });

    test('a signed installable listing is accepted', () {
      final ReleaseEvidence evidence = ReleaseEvidence.fromListing(
        appName: 'RailMate-BD',
        packageName: 'bd.railmate.railmate_bd',
        versionName: '1.0.0',
        versionCode: 3,
        commit: 'def',
        artifacts: artifacts(<String>['RailMate-BD-1.0.0-universal.apk']),
      );
      expect(evidence.hasUniversalApk, isTrue);
      expect(evidence.versionCode, 3);
    });
  });

  group('monotonic versionCode', () {
    test('an update requires a strictly greater code', () {
      expect(isMonotonicVersionCode(previous: 2, next: 3), isTrue);
      expect(isMonotonicVersionCode(previous: 2, next: 2), isFalse);
      expect(isMonotonicVersionCode(previous: 3, next: 2), isFalse);
    });
  });
}
