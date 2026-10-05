/// P30 — parses the release evidence produced by `.github/workflows/release.yml`
/// so the freeze (P36) can prove, on a laptop, what a CI run actually
/// published. Pure Dart: no Flutter, no network.
///
/// What this proves, and what it deliberately does not:
/// * [ReleaseEvidence.parse] accepts the exact `key=value` manifest the
///   workflow emits today (verified against the real `v1.0.0+3` download),
///   and a JSON object so a future `json`-shaped manifest keeps working.
/// * It REJECTS evidence that cannot be trusted: a blank required field, an
///   empty artifact list, an artifact whose name is not a build of the
///   declared app, or any listed artifact with no sha256 entry. A manifest
///   claiming `signed=true` therefore can never be recorded without digests
///   to back it.
/// * The unit tests are hermetic (synthetic manifests). Real digests come
///   from a real CI run — see the P30/P36 handoffs.
library;

import 'dart:convert';

/// Evidence sidecars the release uploads alongside the installable files.
/// These carry no app name by design, so the brand-consistency rule applies
/// only to actual build outputs.
const Set<String> kEvidenceSidecars = <String>{
  'SHA256SUMS.txt',
  'release-manifest.json',
  'PROVENANCE.md',
};

/// One published artifact with its digest.
class ReleaseArtifact {
  final String name;

  /// Size in bytes; 0 when the parser was not given the file itself (the
  /// manifest carries names + digests, not sizes).
  final int sizeBytes;

  final String sha256;

  const ReleaseArtifact({
    required this.name,
    required this.sizeBytes,
    required this.sha256,
  });

  /// True for the installable APK/AAB files a user can actually install.
  bool get isInstallable => name.endsWith('.apk') || name.endsWith('.aab');

  /// True for the universal APK (runs on every ABI).
  bool get isUniversalApk => name.endsWith('-universal.apk');

  @override
  String toString() => '$name ($sizeBytes bytes, sha256 $sha256)';
}

/// Parsed, validated release manifest + checksum list.
///
/// [ReleaseEvidence.parse] throws [FormatException] with a precise reason when
/// the evidence is incomplete or self-contradictory, so a broken release
/// cannot be recorded as verified.
class ReleaseEvidence {
  final String appName;
  final String packageName;
  final String versionName;
  final int versionCode;
  final String commit;
  final bool signed;
  final List<ReleaseArtifact> artifacts;

  const ReleaseEvidence({
    required this.appName,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.commit,
    required this.signed,
    required this.artifacts,
  });

  int get apkCount =>
      artifacts.where((ReleaseArtifact a) => a.name.endsWith('.apk')).length;

  bool get hasAab =>
      artifacts.any((ReleaseArtifact a) => a.name.endsWith('.aab'));

  bool get hasUniversalApk =>
      artifacts.any((ReleaseArtifact a) => a.isUniversalApk);

  /// Validates and builds evidence from the raw manifest and SHA256SUMS text.
  ///
  /// Throws [FormatException] on any inconsistency (see the library docs).
  factory ReleaseEvidence.parse({
    required String manifestJson,
    required String sha256Sums,
  }) {
    final Map<String, dynamic> manifest = _readManifest(manifestJson);

    final String appName = _requireString(manifest, 'appName');
    final String packageName = _requireString(manifest, 'package');
    final String commit = _requireString(manifest, 'commit');
    final bool signed = _requireBool(manifest, 'signed');

    // Compared separator-insensitively: the manifest spells the brand
    // "RailMate BD" while file names use "RailMate-BD".
    final String brand = _brandKey(appName);

    final List<String> names = _artifactNames(manifest);
    if (names.isEmpty) {
      throw const FormatException('manifest lists no artifacts');
    }

    final List<ReleaseArtifact> artifacts = <ReleaseArtifact>[];
    for (final String name in names) {
      if (!kEvidenceSidecars.contains(name) &&
          !_brandKey(name).contains(brand)) {
        throw FormatException(
          'artifact "$name" does not look like a "$appName" build',
        );
      }
      final String? digest = _digestFor(sha256Sums, name);
      if (digest == null) {
        throw FormatException(
          'artifact "$name" has no sha256 entry in SHA256SUMS.txt',
        );
      }
      artifacts.add(ReleaseArtifact(name: name, sizeBytes: 0, sha256: digest));
    }

    return ReleaseEvidence(
      appName: appName,
      packageName: packageName,
      versionName: _requireString(manifest, 'versionName'),
      versionCode: _requireInt(manifest, 'versionCode'),
      commit: commit,
      signed: signed,
      artifacts: artifacts,
    );
  }

  /// Builds evidence from an in-memory artifact listing.
  ///
  /// Used by tests and by the local freeze checklist when the listing is
  /// known but the file bytes are not.
  static ReleaseEvidence fromListing({
    required String appName,
    required String packageName,
    required String versionName,
    required int versionCode,
    required String commit,
    required List<ReleaseArtifact> artifacts,
    bool signed = true,
  }) {
    if (artifacts.isEmpty) {
      throw const FormatException(
        'a release must publish at least one artifact',
      );
    }
    if (artifacts.every((ReleaseArtifact a) => !a.isInstallable)) {
      throw const FormatException(
        'a release must publish at least one installable .apk or .aab',
      );
    }
    return ReleaseEvidence(
      appName: appName,
      packageName: packageName,
      versionName: versionName,
      versionCode: versionCode,
      commit: commit,
      signed: signed,
      artifacts: artifacts,
    );
  }

  /// Lowercases and strips separators/spaces so "RailMate BD" and
  /// "RailMate-BD" compare equal.
  static String _brandKey(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Reads the manifest as either the workflow's `key=value` block or JSON.
  static Map<String, dynamic> _readManifest(String raw) {
    final String text = raw.trim();
    if (text.startsWith('{')) {
      final Object? decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException catch (e) {
        throw FormatException('release-manifest.json is not valid JSON: $e');
      }
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('release-manifest.json is not an object');
      }
      return decoded;
    }

    final Map<String, dynamic> fields = <String, dynamic>{};
    final List<String> artifacts = <String>[];
    for (final String rawLine in text.split('\n')) {
      final String line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      if (line == 'artifacts:') {
        continue;
      }
      if (line.startsWith('- ')) {
        artifacts.add(line.substring(2).trim());
        continue;
      }
      final int eq = line.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      fields[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
    }
    if (artifacts.isNotEmpty) {
      fields['artifacts'] = artifacts;
    }
    return fields;
  }

  /// Artifact names from either the JSON list or the `artifacts:` block.
  static List<String> _artifactNames(Map<String, dynamic> manifest) {
    final Object? raw = manifest['artifacts'];
    if (raw is List) {
      return <String>[
        for (final Object? entry in raw)
          if (entry is String && entry.trim().isNotEmpty) entry.trim(),
      ];
    }
    return const <String>[];
  }

  static String _requireString(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('manifest field "$key" is missing or blank');
    }
    return value.trim();
  }

  /// Reads a boolean field from either a JSON `true` or the workflow's
  /// `signed=true` string form.
  static bool _requireBool(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final String normalized = value.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    throw FormatException(
      'manifest field "$key" is not a boolean (got ${value.runtimeType})',
    );
  }

  static int _requireInt(Map<String, dynamic> map, String key) {
    final Object? value = map[key];
    if (value is int) {
      return value;
    }
    if (value is String) {
      final int? parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    throw FormatException('manifest field "$key" is not an integer');
  }

  /// Extracts the digest for [name] from a `sha256sum`-style file
  /// (`<64 hex>  <name>`), or null when absent.
  ///
  /// `sha256sum` inside the dist directory emits a leading `./`, and may mark
  /// binary mode with `*`; both are stripped before matching.
  static String? _digestFor(String sums, String name) {
    for (final String rawLine in sums.split('\n')) {
      final String line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      final List<String> parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        continue;
      }
      final String digest = parts[0];
      String file = parts.last.replaceFirst('*', '');
      if (file.startsWith('./')) {
        file = file.substring(2);
      }
      if (file == name && digest.length == 64) {
        return digest;
      }
    }
    return null;
  }
}

/// P30 monotonic-versionCode check.
///
/// Android installs an update only when `versionCode` is strictly greater than
/// the installed one, so a release whose code is not greater than the previous
/// published code cannot update an existing install — the exact failure this
/// app must avoid.
bool isMonotonicVersionCode({required int previous, required int next}) =>
    next > previous;
