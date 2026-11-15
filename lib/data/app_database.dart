import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/daily_entry.dart';
import '../models/student_profile.dart';

/// Local SQLite storage for student profiles and their daily entries.
///
/// Notifies listeners after every write so screens can refresh.
class AppDatabase extends ChangeNotifier {
  AppDatabase._(this._db);

  final Database _db;

  /// Opens (and on first launch creates) the database.
  ///
  /// [factory] and [path] exist so tests can use an in-memory database.
  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath =
        path ??
        p.join(await dbFactory.getDatabasesPath(), 'classwork_pulse.db');
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: _create,
        onUpgrade: _upgrade,
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE students (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        pronouns TEXT NOT NULL DEFAULT 'they',
        teacher_name TEXT NOT NULL DEFAULT '',
        parent_title TEXT NOT NULL DEFAULT 'Ma''am'
      )
    ''');
    await db.execute('''
      CREATE TABLE daily_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        entry_date TEXT NOT NULL,
        accomplishments TEXT NOT NULL DEFAULT '',
        reading_ability INTEGER NOT NULL,
        reading_comprehension INTEGER NOT NULL,
        notes TEXT NOT NULL DEFAULT '',
        parent_update TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students(id),
        UNIQUE (student_id, entry_date)
      )
    ''');
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) {
      // Version 2 added what parent updates need: pronouns, the teacher's
      // name, how the parent is addressed, and the saved update itself.
      await db.execute(
        "ALTER TABLE student ADD COLUMN pronouns TEXT NOT NULL DEFAULT 'they'",
      );
      await db.execute(
        "ALTER TABLE student ADD COLUMN teacher_name TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        'ALTER TABLE student ADD COLUMN parent_title TEXT NOT NULL '
        "DEFAULT 'Ma''am'",
      );
      await db.execute(
        'ALTER TABLE daily_entries ADD COLUMN parent_update TEXT',
      );
    }
    if (from < 3) {
      await db.execute('''
        CREATE TABLE students (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          pronouns TEXT NOT NULL DEFAULT 'they',
          teacher_name TEXT NOT NULL DEFAULT '',
          parent_title TEXT NOT NULL DEFAULT 'Ma''am'
        )
      ''');
      await db.execute(
        'INSERT INTO students (id, name, pronouns, teacher_name, parent_title) '
        'SELECT id, name, pronouns, teacher_name, parent_title FROM student',
      );
      await db.execute('''
        CREATE TABLE daily_entries_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          student_id INTEGER NOT NULL,
          entry_date TEXT NOT NULL,
          accomplishments TEXT NOT NULL DEFAULT '',
          reading_ability INTEGER NOT NULL,
          reading_comprehension INTEGER NOT NULL,
          notes TEXT NOT NULL DEFAULT '',
          parent_update TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (student_id) REFERENCES students(id),
          UNIQUE (student_id, entry_date)
        )
      ''');
      await db.execute(
        'INSERT INTO daily_entries_new '
        '(id, student_id, entry_date, accomplishments, reading_ability, '
        'reading_comprehension, notes, parent_update, created_at, updated_at) '
        'SELECT id, 1, entry_date, accomplishments, reading_ability, '
        'reading_comprehension, notes, parent_update, created_at, updated_at '
        'FROM daily_entries',
      );
      await db.execute('DROP TABLE daily_entries');
      await db.execute('ALTER TABLE daily_entries_new RENAME TO daily_entries');
      await db.execute('DROP TABLE student');
    }
  }

  /// All saved profiles, in the order they were added.
  Future<List<StudentProfile>> profiles() async {
    final rows = await _db.query('students', orderBy: 'id ASC');
    return rows.map(_profileFromRow).toList();
  }

  /// The selected profile, or the first profile before onboarding.
  Future<StudentProfile?> profile([int? studentId]) async {
    final rows = await _db.query(
      'students',
      where: studentId == null ? null : 'id = ?',
      whereArgs: studentId == null ? null : [studentId],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _profileFromRow(rows.first);
  }

  StudentProfile _profileFromRow(Map<String, Object?> row) => StudentProfile(
    id: row['id'] as int,
    studentName: row['name'] as String,
    pronouns: Pronouns.fromName(row['pronouns'] as String?),
    teacherName: row['teacher_name'] as String? ?? '',
    parentTitle:
        row['parent_title'] as String? ?? StudentProfile.defaultParentTitle,
  );

  /// Saves an existing profile or creates a new one.
  Future<StudentProfile> saveProfile(
    StudentProfile profile, {
    bool asNew = false,
  }) async {
    final values = {
      'name': profile.studentName.trim(),
      'pronouns': profile.pronouns.name,
      'teacher_name': profile.teacherName.trim(),
      'parent_title': profile.parentTitle,
    };
    final existingProfiles = asNew
        ? const <StudentProfile>[]
        : await profiles();
    final id =
        profile.id ??
        (existingProfiles.isEmpty ? null : existingProfiles.first.id);
    final savedId = id == null
        ? await _db.insert('students', values)
        : await _db
              .update('students', values, where: 'id = ?', whereArgs: [id])
              .then((_) => id);
    notifyListeners();
    return (await this.profile(savedId))!;
  }

  /// All entries for [studentId], newest first.
  Future<List<DailyEntry>> entries([int? studentId]) async {
    final id = await _requiredStudentId(studentId);
    final rows = await _db.query(
      'daily_entries',
      where: 'student_id = ?',
      whereArgs: [id],
      orderBy: 'entry_date DESC',
    );
    return rows.map(DailyEntry.fromMap).toList();
  }

  Future<DailyEntry?> entryFor(DateTime date, [int? studentId]) async {
    final id = await _requiredStudentId(studentId);
    final rows = await _db.query(
      'daily_entries',
      where: 'student_id = ? AND entry_date = ?',
      whereArgs: [id, dateKey(date)],
    );
    return rows.isEmpty ? null : DailyEntry.fromMap(rows.first);
  }

  /// Saves [entry], replacing any entry already recorded for the same day.
  ///
  /// A parent update saved for that day is kept only if the entry's content
  /// is unchanged, since it would otherwise describe the old content.
  Future<void> saveEntry(DailyEntry entry, [int? studentId]) async {
    final id = await _requiredStudentId(studentId);
    final now = DateTime.now().toIso8601String();
    final values = entry.toMap();
    await _db.transaction((txn) async {
      final existing = await txn.query(
        'daily_entries',
        where: 'student_id = ? AND entry_date = ?',
        whereArgs: [id, values['entry_date']],
      );
      if (existing.isEmpty) {
        await txn.insert('daily_entries', {
          ...values,
          'student_id': id,
          'created_at': now,
          'updated_at': now,
        });
        return;
      }
      final changed = values.keys.any(
        (column) => existing.first[column] != values[column],
      );
      await txn.update(
        'daily_entries',
        {
          ...values,
          'student_id': id,
          'updated_at': now,
          if (changed) 'parent_update': null,
        },
        where: 'student_id = ? AND entry_date = ?',
        whereArgs: [id, values['entry_date']],
      );
    });
    notifyListeners();
  }

  /// Stores the parent update written for the entry on [date].
  Future<void> saveParentUpdate(
    DateTime date,
    String text, [
    int? studentId,
  ]) async {
    final id = await _requiredStudentId(studentId);
    await _db.update(
      'daily_entries',
      {'parent_update': text},
      where: 'student_id = ? AND entry_date = ?',
      whereArgs: [id, dateKey(date)],
    );
    notifyListeners();
  }

  Future<void> deleteEntry(DateTime date, [int? studentId]) async {
    final id = await _requiredStudentId(studentId);
    await _db.delete(
      'daily_entries',
      where: 'student_id = ? AND entry_date = ?',
      whereArgs: [id, dateKey(date)],
    );
    notifyListeners();
  }

  Future<void> close() => _db.close();

  Future<int> _requiredStudentId(int? studentId) async {
    if (studentId != null) return studentId;
    final first = await profile();
    if (first?.id != null) return first!.id!;
    final created = await saveProfile(
      const StudentProfile(studentName: 'the student', pronouns: Pronouns.they),
      asNew: true,
    );
    return created.id!;
  }

  Future<void> deleteStudent(int studentId) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'daily_entries',
        where: 'student_id = ?',
        whereArgs: [studentId],
      );
      await txn.delete('students', where: 'id = ?', whereArgs: [studentId]);
    });
    notifyListeners();
  }

  Future<String?> studentName() async => (await profile())?.studentName;
}
