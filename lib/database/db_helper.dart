// lib/database/db_helper.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/task.dart';
import '../models/document.dart';

class DBHelper {
  DBHelper._();
  static final DBHelper instance = DBHelper._();
  static Database? _db;

  Future<Database> get database async => _db ??= await _init();

  Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'nudge_v2.db');
    return openDatabase(path, version: 3, onCreate: _create, onUpgrade: _migrate);
  }

  Future<void> _migrate(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE tasks ADD COLUMN completedAt INTEGER');
    }
    if (oldVersion < 3) {
      await db.execute(
          "ALTER TABLE tasks ADD COLUMN description TEXT NOT NULL DEFAULT ''");
      await db.execute(
          "ALTER TABLE tasks ADD COLUMN referenceLink TEXT NOT NULL DEFAULT ''");
    }
  }

  Future<void> _create(Database db, int _) async {
    await db.execute('''
      CREATE TABLE tasks (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        deadline    TEXT    NOT NULL,
        isDone      INTEGER NOT NULL DEFAULT 0,
        priority    TEXT    NOT NULL DEFAULT 'normal',
        taskType    TEXT    NOT NULL DEFAULT 'assignment',
        subject     TEXT    NOT NULL DEFAULT '',
        docId          INTEGER,
        completedAt    INTEGER,
        description    TEXT NOT NULL DEFAULT '',
        referenceLink  TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE documents (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        filePath TEXT    NOT NULL,
        mimeType TEXT    NOT NULL,
        subject  TEXT    NOT NULL DEFAULT '',
        note     TEXT    NOT NULL DEFAULT '',
        savedAt  TEXT    NOT NULL,
        taskId   INTEGER
      )
    ''');
  }

  // ── Tasks ──────────────────────────────────────────────────────────────

  Future<int> createTask(Task task) async {
    final db = await database;
    final map = task.toMap()..remove('id');
    return db.insert('tasks', map);
  }

  Future<List<Task>> getAllTasks() async {
    final db = await database;
    final rows = await db.query('tasks', orderBy: 'deadline ASC');
    return rows.map(Task.fromMap).toList();
  }

  Future<List<Task>> getTodayTasks() async {
    final db = await database;
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final rows = await db.query(
      'tasks',
      where: 'isDone = 0 AND deadline <= ?',
      whereArgs: [end.toIso8601String()],
      orderBy: 'deadline ASC',
    );
    return rows.map(Task.fromMap).toList();
  }

  Future<void> updateTask(Task task) async {
    final db = await database;
    await db.update('tasks', task.toMap(),
        where: 'id = ?', whereArgs: [task.id]);
  }

  Future<void> deleteTask(int id) async {
    final db = await database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  // ── Documents ──────────────────────────────────────────────────────────

  Future<int> createDocument(NudgeDocument doc) async {
    final db = await database;
    final map = doc.toMap()..remove('id');
    return db.insert('documents', map);
  }

  Future<List<NudgeDocument>> getAllDocuments() async {
    final db = await database;
    final rows = await db.query('documents', orderBy: 'savedAt DESC');
    return rows.map(NudgeDocument.fromMap).toList();
  }

  Future<List<String>> getSubjects() async {
    final db = await database;
    final taskSubjects = await db.rawQuery(
        'SELECT DISTINCT subject FROM tasks WHERE subject != "" ORDER BY subject ASC');
    final docSubjects = await db.rawQuery(
        'SELECT DISTINCT subject FROM documents WHERE subject != "" ORDER BY subject ASC');
    final all = <String>{};
    for (final r in taskSubjects) {
      all.add(r['subject'] as String);
    }
    for (final r in docSubjects) {
      all.add(r['subject'] as String);
    }
    final list = all.toList()..sort();
    return list;
  }

  Future<List<NudgeDocument>> getDocumentsBySubject(String subject) async {
    final db = await database;
    final rows = await db.query(
      'documents',
      where: 'subject = ?',
      whereArgs: [subject],
      orderBy: 'savedAt DESC',
    );
    return rows.map(NudgeDocument.fromMap).toList();
  }

  Future<NudgeDocument?> getDocumentById(int id) async {
    final db = await database;
    final rows =
    await db.query('documents', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return NudgeDocument.fromMap(rows.first);
  }

  // Returns ALL documents linked to a task via taskId (supports multiple files)
  Future<List<NudgeDocument>> getDocumentsByTaskId(int taskId) async {
    final db = await database;
    final rows = await db.query(
      'documents',
      where: 'taskId = ?',
      whereArgs: [taskId],
      orderBy: 'savedAt ASC',
    );
    return rows.map(NudgeDocument.fromMap).toList();
  }

  Future<void> updateDocument(NudgeDocument doc) async {
    final db = await database;
    await db.update('documents', doc.toMap(),
        where: 'id = ?', whereArgs: [doc.id]);
  }

  Future<void> deleteDocument(int id) async {
    final db = await database;
    await db.delete('documents', where: 'id = ?', whereArgs: [id]);
  }

  Future<Task?> getTaskById(int id) async {
    final db = await database;
    final rows = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Task.fromMap(rows.first);
  }
}