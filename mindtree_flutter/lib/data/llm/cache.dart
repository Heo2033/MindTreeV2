import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// FNV-1a hash compatible with the original TypeScript implementation.
String fnv1a32(String input) {
  var hash = 0x811c9dc5 & 0xffffffff;
  for (final byte in utf8.encode(input)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toString();
}

/// Eventual cache file name for a key (same scheme as TS: hash36-length36).
String _fileNameForKey(String key) {
  final hash = fnv1a32(key).isEmpty ? 0 : int.parse(fnv1a32(key));
  final hashBase36 = hash.toRadixString(36);
  final lenBase36 = key.length.toRadixString(36);
  return '$hashBase36-$lenBase36';
}

class CacheEntry<T> {
  final T value;
  final int expiresAt;
  CacheEntry(this.value, this.expiresAt);
}

/// A TTL-based LRU-ish cache with optional disk persistence.
class LLMCache {
  final Map<String, CacheEntry<Object?>> _store = {};
  final int maxEntries;
  final int ttlMs;
  final String? persistDir;
  int _hits = 0;
  int _misses = 0;

  LLMCache({this.maxEntries = 1000, int? ttlMs, this.persistDir})
      : ttlMs = ttlMs ?? 24 * 60 * 60 * 1000 {
    if (persistDir != null) _loadFromDisk();
  }

  static String buildKey({
    required String model,
    required String operation,
    required String promptVersion,
    required String contextHash,
  }) =>
      '$model|$operation|$promptVersion|$contextHash';

  T? get<T>(String key) {
    final entry = _store[key];
    if (entry == null) {
      _misses++;
      return null;
    }
    if (DateTime.now().millisecondsSinceEpoch > entry.expiresAt) {
      _store.remove(key);
      _deleteFile(key);
      _misses++;
      return null;
    }
    _hits++;
    return entry.value as T;
  }

  void set(String key, Object? value, {int? ttlMs}) {
    if (_store.length >= maxEntries && !_store.containsKey(key)) {
      _evictOldest();
    }
    final expiresAt = DateTime.now().millisecondsSinceEpoch + (ttlMs ?? this.ttlMs);
    _store[key] = CacheEntry(value, expiresAt);
    if (persistDir != null) _writeFile(key, value, expiresAt);
  }

  bool has(String key) {
    final entry = _store[key];
    if (entry == null) return false;
    if (DateTime.now().millisecondsSinceEpoch > entry.expiresAt) {
      _store.remove(key);
      _deleteFile(key);
      return false;
    }
    return true;
  }

  void invalidate([String? pattern]) {
    if (pattern == null) {
      final keys = _store.keys.toList();
      _store.clear();
      for (final k in keys) {
        _deleteFile(k);
      }
      return;
    }
    for (final key in _store.keys.toList()) {
      if (key.contains(pattern)) {
        _store.remove(key);
        _deleteFile(key);
      }
    }
  }

  Map<String, int> stats() => {'hits': _hits, 'misses': _misses, 'size': _store.length};

  void _evictOldest() {
    // LinkedHashMap preserves insertion order in Dart.
    if (_store.isNotEmpty) {
      final firstKey = _store.keys.first;
      _store.remove(firstKey);
      _deleteFile(firstKey);
    }
  }

  void _loadFromDisk() {
    final dir = Directory(persistDir!);
    if (!dir.existsSync()) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final file in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      try {
        final parsed = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final key = parsed['key'];
        final expiresAt = parsed['expiresAt'];
        if (key is! String || expiresAt is! num || expiresAt <= now) continue;
        if (!_store.containsKey(key)) {
          _store[key] = CacheEntry(parsed['value'], expiresAt.toInt());
        }
      } catch (_) {
        // skip
      }
    }
  }

  void _writeFile(String key, Object? value, int expiresAt) {
    if (persistDir == null) return;
    try {
      final dir = Directory(persistDir!);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final entry = {
        'key': key,
        'value': value,
        'expiresAt': expiresAt,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };
      File(p.join(dir.path, '${_fileNameForKey(key)}.json'))
          .writeAsStringSync(jsonEncode(entry));
    } catch (_) {
      // ignore
    }
  }

  void _deleteFile(String key) {
    if (persistDir == null) return;
    try {
      final f = File(p.join(persistDir!, '${_fileNameForKey(key)}.json'));
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // ignore
    }
  }
}

/// FNV-based hash of arbitrary JSON data used as a cache context key.
String contextHash(Object? data) {
  final bytes = utf8.encode(jsonEncode(data));
  return sha256.convert(bytes).toString().substring(0, 12);
}
