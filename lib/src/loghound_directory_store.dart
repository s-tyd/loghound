import 'dart:io';

import 'jsonl_log_store.dart';

/// Routes records into a flavor/platform/session directory tree.
class LogHoundDirectoryStore {
  /// Creates a routed store under [root].
  LogHoundDirectoryStore(
    this.root, {
    String? fallbackSessionId,
    DateTime Function()? now,
  }) : _fallbackSessionId = fallbackSessionId ?? _timestampSessionId(),
       _now = now ?? DateTime.now;

  /// Root directory that contains flavor folders and `catalog.jsonl`.
  final Directory root;
  final String _fallbackSessionId;
  final DateTime Function() _now;
  final Set<String> _knownCatalogKeys = {};
  Future<void>? _catalogLoad;

  /// File that records discovered sessions for app/session listing commands.
  File get catalogFile =>
      File('${root.path}${Platform.pathSeparator}catalog.jsonl');

  /// Appends [record] to its session file, latest file, and catalog.
  Future<void> append(Map<String, Object?> record) async {
    final route = LogHoundRoute.fromRecord(
      record,
      fallbackSessionId: _fallbackSessionId,
    );
    await Future.wait([
      JsonlLogStore(sessionFile(route)).append(record),
      JsonlLogStore(latestFile(route)).append(record),
      _appendCatalog(route),
    ]);
  }

  /// Returns the session JSONL file for [route].
  File sessionFile(LogHoundRoute route) {
    return File(
      [
        root.path,
        route.flavor,
        route.platform,
        'sessions',
        '${route.sessionId}.jsonl',
      ].join(Platform.pathSeparator),
    );
  }

  /// Returns the latest JSONL file for [route]'s flavor/platform route.
  File latestFile(LogHoundRoute route) {
    return File(
      [
        root.path,
        route.flavor,
        route.platform,
        'latest.jsonl',
      ].join(Platform.pathSeparator),
    );
  }

  /// Lists discovered apps and their flavors.
  Future<List<LogHoundAppSummary>> apps() async {
    final sessions = await this.sessions();
    final byApp = <String, Set<String>>{};
    for (final session in sessions) {
      byApp.putIfAbsent(session.appId, () => <String>{}).add(session.flavor);
    }

    final apps = [
      for (final entry in byApp.entries)
        LogHoundAppSummary(
          appId: entry.key,
          flavors: entry.value.toList()..sort(),
          sessionCount: sessions
              .where((session) => session.appId == entry.key)
              .length,
        ),
    ]..sort((a, b) => a.appId.compareTo(b.appId));
    return apps;
  }

  /// Lists discovered sessions, optionally filtered by app, flavor, and platform.
  Future<List<LogHoundSessionSummary>> sessions({
    String? appId,
    String? flavor,
    String? platform,
  }) async {
    final summaries = <String, LogHoundSessionSummary>{};
    if (!await root.exists()) {
      return [];
    }

    await _addAppLocalSessionSummaries(
      summaries,
      appId: appId,
      flavor: flavor,
      platform: platform,
    );
    await _addLegacySessionSummaries(
      summaries,
      appId: appId,
      flavor: flavor,
      platform: platform,
    );

    final sorted = summaries.values.toList();
    sorted.sort((a, b) {
      final byUpdated = b.updatedAt.compareTo(a.updatedAt);
      if (byUpdated != 0) {
        return byUpdated;
      }
      return a.sessionId.compareTo(b.sessionId);
    });
    return sorted;
  }

  Future<void> _addAppLocalSessionSummaries(
    Map<String, LogHoundSessionSummary> summaries, {
    String? appId,
    String? flavor,
    String? platform,
  }) async {
    await for (final flavorEntity in root.list()) {
      if (flavorEntity is! Directory) {
        continue;
      }
      final currentFlavor = _basename(flavorEntity.path);
      if (flavor != null && currentFlavor != flavor) {
        continue;
      }

      await for (final platformEntity in flavorEntity.list()) {
        if (platformEntity is! Directory) {
          continue;
        }
        final currentPlatform = _basename(platformEntity.path);
        if (currentPlatform == 'sessions') {
          continue;
        }
        if (platform != null && currentPlatform != platform) {
          continue;
        }

        await _addSessionSummaries(
          summaries,
          sessionsDir: Directory(
            '${platformEntity.path}${Platform.pathSeparator}sessions',
          ),
          pathAppId: null,
          flavor: currentFlavor,
          platform: currentPlatform,
          appIdFilter: appId,
          appLocal: true,
        );
      }
    }
  }

  Future<void> _addLegacySessionSummaries(
    Map<String, LogHoundSessionSummary> summaries, {
    String? appId,
    String? flavor,
    String? platform,
  }) async {
    await for (final appEntity in root.list()) {
      if (appEntity is! Directory) {
        continue;
      }
      final currentApp = _basename(appEntity.path);
      if (appId != null && currentApp != appId) {
        continue;
      }

      await for (final flavorEntity in appEntity.list()) {
        if (flavorEntity is! Directory) {
          continue;
        }
        final currentFlavor = _basename(flavorEntity.path);
        if (flavor != null && currentFlavor != flavor) {
          continue;
        }

        final legacySessionsDir = Directory(
          '${flavorEntity.path}${Platform.pathSeparator}sessions',
        );
        if (platform == null || platform == 'unknown') {
          await _addSessionSummaries(
            summaries,
            sessionsDir: legacySessionsDir,
            pathAppId: currentApp,
            flavor: currentFlavor,
            platform: 'unknown',
            appIdFilter: appId,
            appLocal: false,
          );
        }

        await for (final platformEntity in flavorEntity.list()) {
          if (platformEntity is! Directory) {
            continue;
          }
          final currentPlatform = _basename(platformEntity.path);
          if (currentPlatform == 'sessions') {
            continue;
          }
          if (platform != null && currentPlatform != platform) {
            continue;
          }

          await _addSessionSummaries(
            summaries,
            sessionsDir: Directory(
              '${platformEntity.path}${Platform.pathSeparator}sessions',
            ),
            pathAppId: currentApp,
            flavor: currentFlavor,
            platform: currentPlatform,
            appIdFilter: appId,
            appLocal: false,
          );
        }
      }
    }
  }

  Future<void> _addSessionSummaries(
    Map<String, LogHoundSessionSummary> summaries, {
    required Directory sessionsDir,
    required String? pathAppId,
    required String flavor,
    required String platform,
    required String? appIdFilter,
    required bool appLocal,
  }) async {
    if (!await sessionsDir.exists()) {
      return;
    }

    await for (final sessionEntity in sessionsDir.list()) {
      if (sessionEntity is! File || !sessionEntity.path.endsWith('.jsonl')) {
        continue;
      }
      final firstRecord = await _readFirstRecord(sessionEntity);
      final recordAppId = _recordAppId(firstRecord);
      final recordFlavor = _recordFlavor(firstRecord);
      final recordPlatform = _recordPlatform(firstRecord);

      if (appLocal) {
        if (recordFlavor != null &&
            _safeSegment(recordFlavor, fallback: flavor) != flavor) {
          continue;
        }
        if (recordPlatform != null &&
            _safeSegment(recordPlatform, fallback: platform) != platform) {
          continue;
        }
      } else if (recordAppId != null &&
          _safeSegment(recordAppId, fallback: pathAppId ?? 'unknown-app') !=
              pathAppId) {
        continue;
      }

      final summaryAppId = _safeSegment(
        recordAppId ?? pathAppId,
        fallback: 'unknown-app',
      );
      if (appIdFilter != null && summaryAppId != appIdFilter) {
        continue;
      }

      final stat = await sessionEntity.stat();
      final summary = LogHoundSessionSummary(
        appId: summaryAppId,
        flavor: flavor,
        platform: platform,
        sessionId: _basename(
          sessionEntity.path,
        ).replaceAll(RegExp(r'\.jsonl$'), ''),
        file: sessionEntity,
        updatedAt: stat.modified,
      );
      summaries.putIfAbsent(sessionEntity.absolute.path, () => summary);
    }
  }

  Future<Map<String, Object?>?> _readFirstRecord(File file) async {
    await for (final record in JsonlLogStore(file).readStream()) {
      return record;
    }
    return null;
  }

  Future<void> _appendCatalog(LogHoundRoute route) async {
    await _ensureCatalogLoaded();
    final key = route.key;
    if (!_knownCatalogKeys.add(key)) {
      return;
    }

    final record = {
      'kind': 'session',
      'app_id': route.appId,
      'flavor': route.flavor,
      'platform': route.platform,
      'session_id': route.sessionId,
      if (route.device != null) 'device': route.device,
      'file': _relativePath(sessionFile(route)),
      'updated_at': _now().toIso8601String(),
    };
    await JsonlLogStore(catalogFile).append(record);
  }

  Future<void> _ensureCatalogLoaded() {
    return _catalogLoad ??= () async {
      await for (final record in JsonlLogStore(catalogFile).readStream()) {
        final appId = record['app_id'];
        final flavor = record['flavor'];
        final platform = record['platform'] ?? 'unknown';
        final sessionId = record['session_id'];
        if (appId != null && flavor != null && sessionId != null) {
          _knownCatalogKeys.add('$appId/$flavor/$platform/$sessionId');
        }
      }
    }();
  }

  String _relativePath(File file) {
    final rootPath = root.absolute.path;
    final filePath = file.absolute.path;
    if (filePath.startsWith('$rootPath${Platform.pathSeparator}')) {
      return filePath.substring(rootPath.length + 1);
    }
    return file.path;
  }
}

/// Sanitized app metadata plus flavor/platform/session routing for one record.
class LogHoundRoute {
  /// Creates a route from already sanitized path segments.
  const LogHoundRoute({
    required this.appId,
    required this.flavor,
    required this.sessionId,
    this.platform = 'unknown',
    this.device,
  });

  /// Builds a safe route from a log [record].
  factory LogHoundRoute.fromRecord(
    Map<String, Object?> record, {
    required String fallbackSessionId,
  }) {
    return LogHoundRoute(
      appId: _safeSegment(
        _lookup(record, const ['app_id', 'appId', 'app', 'service_name']) ??
            _lookup(record['attributes'], const [
              'app_id',
              'appId',
              'app',
              'service.name',
              'service_name',
            ]),
        fallback: 'unknown-app',
      ),
      flavor: _safeSegment(
        _lookup(record, const ['flavor', 'environment', 'env']) ??
            _lookup(record['attributes'], const [
              'flavor',
              'environment',
              'env',
            ]),
        fallback: 'default',
      ),
      sessionId: _safeSegment(
        _lookup(record, const ['session_id', 'sessionId']) ??
            _lookup(record['data'], const ['session_id', 'sessionId']) ??
            _lookup(record['attributes'], const ['session_id', 'sessionId']),
        fallback: fallbackSessionId,
      ),
      platform: _safeSegment(
        _lookup(record, const ['platform']) ??
            _lookup(record['attributes'], const ['platform']),
        fallback: 'unknown',
      ),
      device:
          _lookup(record, const ['device'])?.toString() ??
          _lookup(record['attributes'], const ['device'])?.toString(),
    );
  }

  /// Application identifier kept as metadata for catalog and filtering.
  final String appId;

  /// Flavor or environment used as the first route segment.
  final String flavor;

  /// Session identifier used as the JSONL file name.
  final String sessionId;

  /// Platform reported by the app, or `unknown` when missing.
  final String platform;

  /// Optional device label reported by the app.
  final String? device;

  /// Stable catalog key for this route.
  String get key => '$appId/$flavor/$platform/$sessionId';
}

/// Summary of an app discovered in a routed log store.
class LogHoundAppSummary {
  /// Creates an app summary.
  const LogHoundAppSummary({
    required this.appId,
    required this.flavors,
    required this.sessionCount,
  });

  /// Application identifier.
  final String appId;

  /// Flavors discovered for this app.
  final List<String> flavors;

  /// Number of sessions discovered for this app.
  final int sessionCount;

  /// Converts this summary to a JSON-friendly map.
  Map<String, Object?> toJson() => {
    'app_id': appId,
    'flavors': flavors,
    'sessions': sessionCount,
  };
}

/// Summary of a session discovered in a routed log store.
class LogHoundSessionSummary {
  /// Creates a session summary.
  const LogHoundSessionSummary({
    required this.appId,
    required this.flavor,
    this.platform = 'unknown',
    required this.sessionId,
    required this.file,
    required this.updatedAt,
  });

  /// Application identifier.
  final String appId;

  /// Flavor or environment for this session.
  final String flavor;

  /// Platform for this session.
  final String platform;

  /// Session identifier.
  final String sessionId;

  /// JSONL file that stores this session.
  final File file;

  /// Last modification time of the session file.
  final DateTime updatedAt;

  /// Converts this summary to a JSON-friendly map.
  Map<String, Object?> toJson() => {
    'app_id': appId,
    'flavor': flavor,
    'platform': platform,
    'session_id': sessionId,
    'file': file.path,
    'updated_at': updatedAt.toIso8601String(),
  };
}

Object? _lookup(Object? source, List<String> keys) {
  if (source is! Map) {
    return null;
  }
  for (final key in keys) {
    if (source.containsKey(key)) {
      return source[key];
    }
  }
  return null;
}

Object? _recordAppId(Map<String, Object?>? record) {
  return _lookup(record, const ['app_id', 'appId', 'app', 'service_name']) ??
      _lookup(record?['attributes'], const [
        'app_id',
        'appId',
        'app',
        'service.name',
        'service_name',
      ]);
}

Object? _recordFlavor(Map<String, Object?>? record) {
  return _lookup(record, const ['flavor', 'environment', 'env']) ??
      _lookup(record?['attributes'], const ['flavor', 'environment', 'env']);
}

Object? _recordPlatform(Map<String, Object?>? record) {
  return _lookup(record, const ['platform']) ??
      _lookup(record?['attributes'], const ['platform']);
}

String _safeSegment(Object? value, {required String fallback}) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == '.' || text == '..') {
    return fallback;
  }
  final normalized = text.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
  if (normalized.isEmpty || normalized == '.' || normalized == '..') {
    return fallback;
  }
  return normalized;
}

String _basename(String path) {
  final normalized = path.replaceAll(RegExp(r'\\'), '/');
  final slashIndex = normalized.lastIndexOf('/');
  if (slashIndex == -1) {
    return normalized;
  }
  return normalized.substring(slashIndex + 1);
}

String _timestampSessionId() {
  final now = DateTime.now().toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return [
    now.year.toString().padLeft(4, '0'),
    two(now.month),
    two(now.day),
    'T',
    two(now.hour),
    two(now.minute),
    two(now.second),
    'Z',
  ].join();
}
