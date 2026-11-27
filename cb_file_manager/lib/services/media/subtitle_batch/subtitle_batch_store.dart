import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common/sqlite_api.dart';

import '../../../models/database/desktop_database_factory.dart';
import '../../../models/database/sqlite_database_provider.dart';
import 'subtitle_batch_models.dart';
import 'subtitle_generated_metadata.dart';

enum SubtitleBatchLease { acquired, renewed, denied }

/// Priority of waiting videos, based on the source file's modification date.
enum SubtitleBatchOrder { newestFirst, oldestFirst }

/// Rules, jobs and queue state in the application's shared SQLite database.
/// Every window reads the same tables; [tryLease] keeps a single runner.
class SubtitleBatchStore {
  static final instance = SubtitleBatchStore();

  final Future<Database> Function() _open;
  Future<Database>? _ready;
  Future<Database>? _generatedReady;
  Future<void>? _fileModifiedReady;
  final DateTime Function() _now;

  SubtitleBatchStore({
    Future<Database> Function()? openDatabase,
    DateTime Function()? now,
  }) : _open = openDatabase ?? SqliteDatabaseProvider().getDatabase,
       _now = now ?? DateTime.now;

  static const _rules = 'subtitle_batch_rules';
  static const _jobs = 'subtitle_batch_jobs';
  static const _state = 'subtitle_batch_state';
  static const _generated = 'subtitle_batch_generated';

  // Separate from queue rows: clearing completed history does not erase
  // the provenance of an exported subtitle.
  Future<Database> _generatedDatabase() =>
      _generatedReady ??= _initializeGenerated().catchError((Object e) {
        _generatedReady = null;
        throw e;
      });

  Future<Database> _initializeGenerated() async {
    final db = await _database();
    await db.execute('''CREATE TABLE IF NOT EXISTS $_generated (
      path TEXT NOT NULL, signature TEXT NOT NULL, metadata TEXT NOT NULL,
      output_path TEXT, generated_at INTEGER NOT NULL,
      PRIMARY KEY(path, signature))''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS subtitle_batch_generated_output '
      'ON $_generated(output_path, generated_at DESC)',
    );
    return db;
  }

  Future<void> recordGenerated(
    SubtitleBatchJob job,
    SubtitleGeneratedMetadata metadata,
  ) async {
    final db = await _generatedDatabase();
    await db.insert(_generated, {
      'path': job.path,
      'signature': job.settings.signature,
      'metadata': jsonEncode(metadata.toJson()),
      'output_path': metadata.outputPath,
      'generated_at': metadata.generatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<SubtitleGeneratedMetadata?> generatedMetadata(
    SubtitleBatchJob job,
  ) async {
    final db = await _generatedDatabase();
    final rows = await db.query(
      _generated,
      columns: ['metadata'],
      where: 'path = ? AND signature = ?',
      whereArgs: [job.path, job.settings.signature],
    );
    if (rows.isEmpty) return null;
    return SubtitleGeneratedMetadata.fromJson(
      Map<String, Object?>.from(
        jsonDecode(rows.single['metadata'] as String) as Map,
      ),
    );
  }

  Future<bool> ownsGeneratedOutput(SubtitleBatchJob job, String output) async {
    final db = await _generatedDatabase();
    final rows = await db.query(
      _generated,
      columns: ['path', 'signature'],
      where: 'output_path = ?',
      whereArgs: [output],
      orderBy: 'generated_at DESC, rowid DESC',
      limit: 1,
    );
    return rows.isNotEmpty &&
        rows.single['path'] == job.path &&
        rows.single['signature'] == job.settings.signature;
  }

  Future<bool> hasGeneratedOutput(String output) async {
    final db = await _generatedDatabase();
    return (await db.query(
      _generated,
      columns: ['path'],
      where: 'output_path = ?',
      whereArgs: [output],
      limit: 1,
    )).isNotEmpty;
  }

  /// Reset all completed twins because they share the same generated result.
  Future<void> resetCleanedGeneration(SubtitleBatchJob job) async {
    final db = await _generatedDatabase();
    final (where, args) = _group(job);
    await db.runAppTransaction((txn) async {
      await txn.update(
        _jobs,
        {
          'status': SubtitleBatchStatus.pending.name,
          'progress': 0,
          'message': null,
          'output_path': null,
          'updated_at': _ms,
        },
        where: '$where AND status = ?',
        whereArgs: [...args, SubtitleBatchStatus.done.name],
      );
      await txn.delete(_generated, where: where, whereArgs: args);
    });
  }

  Future<Database> _database() =>
      _ready ??= _initialize().catchError((Object e) {
        _ready = null;
        throw e;
      });

  /// A hot reload can preserve the already-open database future. Keep this
  /// additive migration separate from connection initialization so callers
  /// using the new column cannot bypass it on an existing store instance.
  Future<Database> _databaseWithFileModified() async {
    final db = await _database();
    await (_fileModifiedReady ??= _ensureFileModified(db).catchError((
      Object e,
    ) {
      _fileModifiedReady = null;
      throw e;
    }));
    return db;
  }

  /// Each rule owns its jobs: the same video queued by two rules is two
  /// jobs. Version 1 shared one job per path and settings across rules.
  static const _jobsSchema = 'UNIQUE(path, rule_id, signature)';

  static Future<String?> _jobsSql(DatabaseExecutor db) async =>
      (await db.rawQuery(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
            [_jobs],
          )).firstOrNull?['sql']
          as String?;

  Future<Database> _initialize() async {
    final db = await _open();
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (?, ?, ?)",
      [_rules, _jobs, _state],
    );
    if (tables.length == 3 &&
        ((await _jobsSql(db))?.contains(_jobsSchema) ?? false)) {
      return db;
    }
    await db.runAppTransaction((txn) async {
      await txn.execute('''CREATE TABLE IF NOT EXISTS $_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT NOT NULL,
        created_at INTEGER NOT NULL)''');
      await txn.execute('''CREATE TABLE IF NOT EXISTS $_state (
        key TEXT PRIMARY KEY, value TEXT)''');
      final existing = await _jobsSql(txn);
      if (existing != null && existing.contains(_jobsSchema)) return;
      if (existing != null) {
        await txn.execute('DROP INDEX IF EXISTS subtitle_batch_jobs_status');
        await txn.execute('ALTER TABLE $_jobs RENAME TO ${_jobs}_v1');
      }
      await txn.execute('''CREATE TABLE $_jobs (
        id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL,
        rule_id INTEGER NOT NULL DEFAULT 0, rule_name TEXT,
        settings TEXT NOT NULL, signature TEXT NOT NULL, status TEXT NOT NULL,
        progress REAL NOT NULL DEFAULT 0, message TEXT, output_path TEXT,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
        file_modified_at INTEGER,
        $_jobsSchema)''');
      if (existing != null) {
        await txn.execute('''INSERT OR IGNORE INTO $_jobs
          (id, path, rule_id, rule_name, settings, signature, status, progress,
            message, output_path, created_at, updated_at)
          SELECT id, path, COALESCE(rule_id, 0), rule_name, settings,
          signature, status, progress, message, output_path, created_at,
          updated_at FROM ${_jobs}_v1''');
        await txn.execute('DROP TABLE ${_jobs}_v1');
      }
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS subtitle_batch_jobs_status '
        'ON $_jobs(status, id)',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS subtitle_batch_jobs_rule '
        'ON $_jobs(rule_id, status)',
      );
    });
    return db;
  }

  /// Add metadata in place: never recreate a current queue or reset its jobs.
  Future<void> _ensureFileModified(Database db) async {
    await db.runAppTransaction((txn) async {
      final columns = await txn.rawQuery('PRAGMA table_info($_jobs)');
      if (!columns.any((row) => row['name'] == 'file_modified_at')) {
        await txn.execute(
          'ALTER TABLE $_jobs ADD COLUMN file_modified_at INTEGER',
        );
      }
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS subtitle_batch_jobs_modified '
        'ON $_jobs(status, NULLIF(file_modified_at, 0) DESC, id)',
      );
    });
    // Existing rows are migrated once. File I/O is outside write transactions,
    // and an unavailable file gets a zero sentinel, so it cannot stall forever.
    while (true) {
      final rows = await db.query(
        _jobs,
        columns: ['path'],
        distinct: true,
        where: 'file_modified_at IS NULL',
        limit: 128,
      );
      if (rows.isEmpty) return;
      final paths = rows.map((row) => row['path'] as String).toList();
      final modified = await _fileTimes(paths);
      await db.runAppTransaction((txn) async {
        final batch = txn.batch();
        for (final path in paths) {
          batch.update(
            _jobs,
            {'file_modified_at': modified[path]},
            where: 'path = ? AND file_modified_at IS NULL',
            whereArgs: [path],
          );
        }
        await batch.commit(noResult: true);
      });
    }
  }

  static Future<Map<String, int>> _fileTimes(List<String> paths) async {
    final times = <String, int>{};
    for (var start = 0; start < paths.length; start += 32) {
      await Future.wait(
        paths.skip(start).take(32).map((path) async {
          try {
            final stat = await File(
              path,
            ).stat().timeout(const Duration(seconds: 2));
            times[path] = stat.type == FileSystemEntityType.file
                ? stat.modified.millisecondsSinceEpoch
                : 0;
          } catch (_) {
            times[path] = 0;
          }
        }),
      );
    }
    return times;
  }

  /// `rule_id = ?` for one rule, or nothing for every rule.
  static (String?, List<Object>) _ruleFilter(int? ruleId) =>
      ruleId == null ? (null, const []) : ('rule_id = ?', [ruleId]);

  int get _ms => _now().millisecondsSinceEpoch;

  // ---------------------------------------------------------------- rules

  Future<List<SubtitleBatchRule>> rules() async {
    final db = await _database();
    final rows = await db.query(_rules, orderBy: 'id');
    return [
      for (final row in rows)
        if (_decode(row['data'] as String?) case final json?)
          SubtitleBatchRule.fromJson(json, id: row['id'] as int),
    ];
  }

  Future<SubtitleBatchRule> saveRule(SubtitleBatchRule rule) async {
    final db = await _database();
    if (rule.id == null) {
      final id = await db.insert(_rules, {
        'data': rule.encode(),
        'created_at': _ms,
      });
      return rule.copyWith(id: id);
    }
    await db.update(
      _rules,
      {'data': rule.encode()},
      where: 'id = ?',
      whereArgs: [rule.id],
    );
    return rule;
  }

  /// Deletes the rule and every job it queued. Subtitle files already
  /// written stay on disk.
  Future<void> deleteRule(int id) async {
    final db = await _database();
    await db.runAppTransaction((txn) async {
      await txn.delete(_rules, where: 'id = ?', whereArgs: [id]);
      await txn.delete(_jobs, where: 'rule_id = ?', whereArgs: [id]);
      // An in-flight scan in another window may still hold this rule ID.
      // Remember deletion so its late enqueue cannot recreate orphan jobs.
      await txn.insert(_state, {
        'key': 'deleted_rule:$id',
        'value': 'true',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final scope = await txn.query(
        _state,
        where: 'key = ?',
        whereArgs: ['run_rule'],
      );
      if (scope.firstOrNull?['value'] == '$id') {
        await txn.insert(_state, {
          'key': 'run',
          'value': 'false',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.delete(_state, where: 'key = ?', whereArgs: ['run_rule']);
      }
    });
  }

  /// Applies an edited rule to the jobs it has not started yet. Running and
  /// finished jobs keep the settings they were generated with.
  Future<void> updateRuleJobs(
    int ruleId, {
    required String ruleName,
    required SubtitleBatchSettings settings,
  }) async {
    final db = await _database();
    await db.runAppTransaction((txn) async {
      await txn.update(
        _jobs,
        {'rule_name': ruleName},
        where: 'rule_id = ?',
        whereArgs: [ruleId],
      );
      await txn.rawUpdate(
        'UPDATE OR IGNORE $_jobs SET settings = ?, signature = ?, '
        'updated_at = ? WHERE rule_id = ? AND status = ?',
        [
          jsonEncode(settings.toJson()),
          settings.signature,
          _ms,
          ruleId,
          SubtitleBatchStatus.pending.name,
        ],
      );
      // A waiting job that already had a twin with the new settings.
      await txn.delete(
        _jobs,
        where: 'rule_id = ? AND status = ? AND signature != ?',
        whereArgs: [
          ruleId,
          SubtitleBatchStatus.pending.name,
          settings.signature,
        ],
      );
    });
  }

  // ----------------------------------------------------------------- jobs

  /// Queues [paths] for one rule; a video that rule already queued with the
  /// same settings is kept as it is. Returns how many jobs were added.
  Future<int> enqueue(
    Iterable<String> paths, {
    required SubtitleBatchSettings settings,
    int? ruleId,
    required String ruleName,
    SubtitleBatchStatus status = SubtitleBatchStatus.pending,
    Map<String, String> outputs = const {},
    String? message,
  }) async {
    final db = await _databaseWithFileModified();
    final encoded = jsonEncode(settings.toJson());
    final signature = settings.signature;
    final all = paths.toList();
    var added = 0;
    const chunk = 400;
    for (var i = 0; i < all.length; i += chunk) {
      final paths = all.skip(i).take(chunk).toList();
      final modified = await _fileTimes(paths);
      final now = _ms;
      final results = await db.runAppTransaction((txn) async {
        if (ruleId != null &&
            (await txn.query(
              _state,
              columns: ['key'],
              where: 'key = ?',
              whereArgs: ['deleted_rule:$ruleId'],
            )).isNotEmpty) {
          return <Object?>[];
        }
        final batch = txn.batch();
        for (final path in paths) {
          batch.insert(_jobs, {
            'path': path,
            'rule_id': ruleId ?? 0,
            'rule_name': ruleName,
            'settings': encoded,
            'signature': signature,
            'status': status.name,
            'progress': status == SubtitleBatchStatus.pending ? 0 : 1,
            'message': message,
            'output_path': outputs[path],
            'created_at': now,
            'updated_at': now,
            'file_modified_at': modified[path],
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        final inserted = await batch.commit();
        // Rescanning refreshes metadata for jobs already present, without
        // changing status, progress, or their queue update timestamps.
        final metadata = txn.batch();
        for (final path in paths) {
          metadata.update(
            _jobs,
            {'file_modified_at': modified[path]},
            where:
                'path = ? AND (file_modified_at IS NULL OR file_modified_at != ?)',
            whereArgs: [path, modified[path]],
          );
        }
        await metadata.commit(noResult: true);
        // A video another rule already generated (or is generating) with
        // the same settings shares that work instead of running twice.
        await _attachTwins(txn, done: true);
        return inserted;
      });
      // An ignored insert reports 0 (or null on some backends).
      added += results.whereType<int>().where((id) => id > 0).length;
    }
    return added;
  }

  /// Jobs of different rules for the same video and settings are twins:
  /// one generation serves all of them.
  static const _twin =
      't.path = $_jobs.path AND t.signature = $_jobs.signature';

  /// Waiting jobs join a running twin, and with [done] also take over a
  /// finished twin's result.
  Future<void> _attachTwins(DatabaseExecutor txn, {required bool done}) async {
    final running = SubtitleBatchStatus.running.name;
    final pending = SubtitleBatchStatus.pending.name;
    await txn.rawUpdate(
      '''UPDATE $_jobs SET status = ?,
        progress = (SELECT MAX(t.progress) FROM $_jobs t
          WHERE $_twin AND t.status = ?)
      WHERE status = ? AND EXISTS (SELECT 1 FROM $_jobs t
        WHERE $_twin AND t.status = ?)''',
      [running, running, pending, running],
    );
    if (!done) return;
    final finished = SubtitleBatchStatus.done.name;
    await txn.rawUpdate(
      '''UPDATE $_jobs SET status = ?, progress = 1,
        output_path = (SELECT t.output_path FROM $_jobs t
          WHERE $_twin AND t.status = ? LIMIT 1),
        message = (SELECT t.message FROM $_jobs t
          WHERE $_twin AND t.status = ? LIMIT 1)
      WHERE status = ? AND EXISTS (SELECT 1 FROM $_jobs t
        WHERE $_twin AND t.status = ?)''',
      [finished, finished, finished, pending, finished],
    );
  }

  /// `path = ? AND signature = ?` of [job]'s twin group.
  static (String, List<Object>) _group(SubtitleBatchJob job) =>
      ('path = ? AND signature = ?', [job.path, job.settings.signature]);

  /// How many jobs of [job]'s twin group still want it generated.
  Future<int> runningTwins(SubtitleBatchJob job) async {
    final db = await _database();
    final (where, args) = _group(job);
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM $_jobs WHERE $where AND status = ?',
      [...args, SubtitleBatchStatus.running.name],
    );
    return rows.single['n'] as int;
  }

  /// Running first, then source videos in the saved processing order, then recent
  /// finished jobs.
  Future<List<SubtitleBatchJob>> jobs({
    Set<SubtitleBatchStatus>? statuses,
    int? ruleId,
    int limit = 20000,
  }) async {
    final db = await _databaseWithFileModified();
    final direction = await processingOrder() == SubtitleBatchOrder.oldestFirst
        ? 'ASC'
        : 'DESC';
    final (rule, ruleArgs) = _ruleFilter(ruleId);
    final where = [
      ?rule,
      if (statuses != null && statuses.isNotEmpty)
        'status IN (${List.filled(statuses.length, '?').join(', ')})',
    ];
    final rows = await db.query(
      _jobs,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: [...ruleArgs, ...?statuses?.map((s) => s.name)],
      orderBy:
          "CASE status WHEN 'running' THEN 0 WHEN 'pending' THEN 1 ELSE 2 END, "
          "CASE WHEN status = 'pending' THEN NULLIF(file_modified_at, 0) IS NULL END, "
          "CASE WHEN status = 'pending' THEN NULLIF(file_modified_at, 0) END $direction, "
          "CASE WHEN status IN ('running', 'pending') THEN id ELSE -updated_at END, id",
      limit: limit,
    );
    return rows.map(SubtitleBatchJob.fromRow).toList();
  }

  Future<SubtitleBatchJob?> job(int id) async {
    final db = await _database();
    final rows = await db.query(_jobs, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : SubtitleBatchJob.fromRow(rows.single);
  }

  Future<Map<SubtitleBatchStatus, int>> counts({int? ruleId}) async {
    final db = await _database();
    final (rule, args) = _ruleFilter(ruleId);
    final rows = await db.rawQuery(
      'SELECT status, COUNT(*) AS n FROM $_jobs '
      '${rule == null ? '' : 'WHERE $rule '}GROUP BY status',
      args,
    );
    return {
      for (final row in rows)
        SubtitleBatchStatus.parse(row['status'] as String?): row['n'] as int,
    };
  }

  /// Job counts per rule id and status, for the rule list.
  Future<Map<int, Map<SubtitleBatchStatus, int>>> ruleCounts() async {
    final db = await _database();
    final rows = await db.rawQuery(
      'SELECT rule_id, status, COUNT(*) AS n FROM $_jobs '
      'GROUP BY rule_id, status',
    );
    final result = <int, Map<SubtitleBatchStatus, int>>{};
    for (final row in rows) {
      final counts = result[row['rule_id'] as int] ??= {};
      counts[SubtitleBatchStatus.parse(row['status'] as String?)] =
          row['n'] as int;
    }
    return result;
  }

  /// Marks the next pending video in the saved order running, together with its twins in other
  /// rules, and returns it: whichever rule comes first runs it for all.
  ///
  /// [ruleId] runs only that rule's videos; their twins in other rules still
  /// finish with them.
  ///
  /// A video that is already being generated, with any settings, is skipped:
  /// parallel jobs never decode the same file or write its cache at once.
  Future<SubtitleBatchJob?> claimNext({int? ruleId}) async {
    final db = await _databaseWithFileModified();
    final direction = await processingOrder() == SubtitleBatchOrder.oldestFirst
        ? 'ASC'
        : 'DESC';
    final (rule, ruleArgs) = _ruleFilter(ruleId);
    return db.runAppTransaction((txn) async {
      final rows = await txn.query(
        _jobs,
        where: [
          'status = ?',
          'path NOT IN (SELECT path FROM $_jobs WHERE status = ?)',
          ?rule,
        ].join(' AND '),
        whereArgs: [
          SubtitleBatchStatus.pending.name,
          SubtitleBatchStatus.running.name,
          ...ruleArgs,
        ],
        orderBy:
            'NULLIF(file_modified_at, 0) IS NULL, '
            'NULLIF(file_modified_at, 0) $direction, id',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final id = rows.single['id'] as int;
      await txn.update(
        _jobs,
        {
          'status': SubtitleBatchStatus.running.name,
          'message': null,
          'updated_at': _ms,
        },
        where: 'path = ? AND signature = ? AND status = ?',
        whereArgs: [
          rows.single['path'],
          rows.single['signature'],
          SubtitleBatchStatus.pending.name,
        ],
      );
      final claimed = await txn.query(_jobs, where: 'id = ?', whereArgs: [id]);
      return SubtitleBatchJob.fromRow(claimed.single);
    });
  }

  /// Finishes [job] and its running twins. Only rows still running change,
  /// so a cancel or removal from another window is never overwritten.
  /// Returns whether any row applied.
  Future<bool> finish(
    SubtitleBatchJob job,
    SubtitleBatchStatus status, {
    double? progress,
    String? message,
    String? outputPath,
  }) async {
    final db = await _database();
    final (where, args) = _group(job);
    final changed = await db.update(
      _jobs,
      {
        'status': status.name,
        'progress': ?progress,
        'message': message,
        'output_path': outputPath,
        'updated_at': _ms,
      },
      where: '$where AND status = ?',
      whereArgs: [...args, SubtitleBatchStatus.running.name],
    );
    return changed > 0;
  }

  Future<void> reportProgress(SubtitleBatchJob job, double progress) async {
    final db = await _database();
    final (where, args) = _group(job);
    await db.update(
      _jobs,
      {'progress': progress.clamp(0.0, 1.0)},
      where: '$where AND status = ?',
      whereArgs: [...args, SubtitleBatchStatus.running.name],
    );
  }

  Future<void> cancel(Iterable<int> ids) => _setStatus(
    ids,
    SubtitleBatchStatus.cancelled,
    from: const [SubtitleBatchStatus.pending, SubtitleBatchStatus.running],
  );

  /// Requeues jobs; one whose twin is generating right now joins it.
  Future<void> retry(Iterable<int> ids) async {
    await _setStatus(
      ids,
      SubtitleBatchStatus.pending,
      from: const [
        SubtitleBatchStatus.failed,
        SubtitleBatchStatus.cancelled,
        SubtitleBatchStatus.done,
        SubtitleBatchStatus.skipped,
      ],
      resetProgress: true,
    );
    await _attachTwins(await _database(), done: false);
  }

  /// Requeues every failed (and cancelled) job, of one rule or of all.
  Future<int> retryFailed({int? ruleId}) async {
    final db = await _database();
    final (rule, args) = _ruleFilter(ruleId);
    return db.update(
      _jobs,
      {
        'status': SubtitleBatchStatus.pending.name,
        'progress': 0,
        'message': null,
        'updated_at': _ms,
      },
      where: ['status IN (?, ?)', ?rule].join(' AND '),
      whereArgs: [
        SubtitleBatchStatus.failed.name,
        SubtitleBatchStatus.cancelled.name,
        ...args,
      ],
    );
  }

  Future<void> remove(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final db = await _database();
    await db.delete(
      _jobs,
      where: 'id IN (${List.filled(list.length, '?').join(', ')})',
      whereArgs: list,
    );
  }

  /// Removes done, skipped and cancelled jobs, of one rule or of all.
  Future<int> clearFinished({int? ruleId}) async {
    final db = await _database();
    final (rule, args) = _ruleFilter(ruleId);
    return db.delete(
      _jobs,
      where: ['status IN (?, ?, ?)', ?rule].join(' AND '),
      whereArgs: [
        SubtitleBatchStatus.done.name,
        SubtitleBatchStatus.skipped.name,
        SubtitleBatchStatus.cancelled.name,
        ...args,
      ],
    );
  }

  /// Puts a running job back in line, keeping its progress: chunks already
  /// generated are in the subtitle cache and are not processed again.
  Future<void> requeue(
    SubtitleBatchJob job, {
    String? message,
    double? progress,
  }) async {
    final db = await _database();
    final (where, args) = _group(job);
    await db.update(
      _jobs,
      {
        'status': SubtitleBatchStatus.pending.name,
        'progress': ?progress,
        'message': message,
        'updated_at': _ms,
      },
      where: '$where AND status = ?',
      whereArgs: [...args, SubtitleBatchStatus.running.name],
    );
  }

  /// Jobs left running by a runner that is gone go back to pending.
  Future<void> resetRunning() async {
    final db = await _database();
    await db.update(
      _jobs,
      {'status': SubtitleBatchStatus.pending.name},
      where: 'status = ?',
      whereArgs: [SubtitleBatchStatus.running.name],
    );
  }

  Future<void> _setStatus(
    Iterable<int> ids,
    SubtitleBatchStatus status, {
    required List<SubtitleBatchStatus> from,
    bool resetProgress = false,
  }) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final db = await _database();
    await db.update(
      _jobs,
      {
        'status': status.name,
        if (resetProgress) ...{
          'progress': 0,
          'message': null,
          'output_path': null,
        },
        'updated_at': _ms,
      },
      where:
          'id IN (${List.filled(list.length, '?').join(', ')}) '
          'AND status IN (${List.filled(from.length, '?').join(', ')})',
      whereArgs: [...list, ...from.map((s) => s.name)],
    );
  }

  // ---------------------------------------------------------------- state

  Future<String?> _get(String key) async {
    final db = await _database();
    final rows = await db.query(_state, where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.single['value'] as String?;
  }

  Future<void> _put(String key, String? value) async {
    final db = await _database();
    await db.insert(_state, {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Whether the user wants the queue to run. Survives restarts.
  Future<bool> runRequested() async => await _get('run') == 'true';
  Future<void> setRunRequested(bool value) => _put('run', '$value');

  /// The rule the user started; null runs every rule.
  Future<int?> runRule() async => int.tryParse(await _get('run_rule') ?? '');
  Future<void> setRunRule(int? ruleId) => _put('run_rule', ruleId?.toString());

  /// Whether [job]'s generation is still wanted by a job of [ruleId].
  Future<bool> servesRule(SubtitleBatchJob job, int ruleId) async {
    final db = await _database();
    final (where, args) = _group(job);
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM $_jobs WHERE $where AND status = ? '
      'AND rule_id = ?',
      [...args, SubtitleBatchStatus.running.name, ruleId],
    );
    return (rows.single['n'] as int) > 0;
  }

  /// Upper bound for [parallelJobs]. Every job loads its own speech and
  /// translation models, so memory grows with each one.
  static const maxParallelJobs = 4;

  /// Stored for [parallelJobs] when the queue picks the number itself.
  static const autoParallelJobs = 0;

  /// Shared across windows and retained after restart. Unknown dates go last.
  Future<SubtitleBatchOrder> processingOrder() async =>
      await _get('processing_order') == SubtitleBatchOrder.oldestFirst.name
      ? SubtitleBatchOrder.oldestFirst
      : SubtitleBatchOrder.newestFirst;

  Future<void> setProcessingOrder(SubtitleBatchOrder value) =>
      _put('processing_order', value.name);

  /// How many videos are generated at the same time; [autoParallelJobs]
  /// (the default) lets the queue choose from its measured speed.
  Future<int> parallelJobs() async =>
      (int.tryParse(await _get('parallel_jobs') ?? '') ?? autoParallelJobs)
          .clamp(autoParallelJobs, maxParallelJobs);
  Future<void> setParallelJobs(int value) => _put(
    'parallel_jobs',
    '${value.clamp(autoParallelJobs, maxParallelJobs)}',
  );

  /// Yield to a video being watched. On by default.
  Future<bool> pauseWhileWatching() async =>
      await _get('pause_while_watching') != 'false';
  Future<void> setPauseWhileWatching(bool value) =>
      _put('pause_while_watching', '$value');

  /// Takes or renews the runner lease. A lease older than [ttl] belongs to a
  /// window that closed or crashed and can be taken over.
  Future<SubtitleBatchLease> tryLease(String owner, Duration ttl) async {
    final db = await _database();
    return db.runAppTransaction((txn) async {
      final rows = await txn.query(
        _state,
        where: 'key IN (?, ?)',
        whereArgs: ['lease_owner', 'lease_at'],
      );
      final values = {
        for (final row in rows) row['key'] as String: row['value'] as String?,
      };
      final holder = values['lease_owner'];
      final at = int.tryParse(values['lease_at'] ?? '') ?? 0;
      final now = _ms;
      final mine = holder == owner;
      if (!mine && holder != null && now - at < ttl.inMilliseconds) {
        return SubtitleBatchLease.denied;
      }
      for (final entry in {'lease_owner': owner, 'lease_at': '$now'}.entries) {
        await txn.insert(_state, {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      return mine ? SubtitleBatchLease.renewed : SubtitleBatchLease.acquired;
    });
  }

  Future<void> releaseLease(String owner) async {
    final db = await _database();
    await db.runAppTransaction((txn) async {
      final rows = await txn.query(
        _state,
        where: 'key = ?',
        whereArgs: ['lease_owner'],
      );
      if (rows.isNotEmpty && rows.single['value'] == owner) {
        await txn.delete(
          _state,
          where: 'key IN (?, ?)',
          whereArgs: ['lease_owner', 'lease_at'],
        );
      }
    });
  }

  /// Publish only the current runner's explicitly registered child processes.
  /// The owner is included so a stale snapshot cannot follow a new lease.
  Future<void> publishProcessIds(String owner, List<int> ids) async {
    final db = await _database();
    final data = jsonEncode({'owner': owner, 'ids': ids});
    await db.runAppTransaction((txn) async {
      final rows = await txn.query(
        _state,
        where: 'key IN (?, ?)',
        whereArgs: ['lease_owner', 'process_ids'],
      );
      final values = {for (final row in rows) row['key']: row['value']};
      if (values['lease_owner'] != owner || values['process_ids'] == data) {
        return;
      }
      await txn.insert(_state, {
        'key': 'process_ids',
        'value': data,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<int>> queueProcessIds(Duration ttl) async {
    final db = await _database();
    final rows = await db.query(
      _state,
      where: 'key IN (?, ?, ?)',
      whereArgs: ['lease_owner', 'lease_at', 'process_ids'],
    );
    final values = {
      for (final row in rows) row['key']: row['value'] as String?,
    };
    final owner = values['lease_owner'];
    final at = int.tryParse(values['lease_at'] ?? '') ?? 0;
    if (owner == null || _ms - at >= ttl.inMilliseconds) return const [];
    final data = _decode(values['process_ids']);
    if (data?['owner'] != owner || data?['ids'] is! List) return const [];
    return (data!['ids'] as List)
        .whereType<int>()
        .where((id) => id > 0)
        .toSet()
        .toList();
  }

  static Map<String, Object?>? _decode(String? data) {
    if (data == null) return null;
    try {
      return Map<String, Object?>.from(jsonDecode(data) as Map);
    } catch (_) {
      return null;
    }
  }
}
