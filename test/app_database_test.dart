import 'dart:io';

import 'package:classwork_pulse/data/app_database.dart';
import 'package:classwork_pulse/models/daily_entry.dart';
import 'package:classwork_pulse/models/student_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DailyEntry _entry(
  DateTime date, {
  String accomplishments = '',
  ReadingLevel ability = ReadingLevel.developing,
  ReadingLevel comprehension = ReadingLevel.developing,
  String notes = '',
}) => DailyEntry(
  date: date,
  accomplishments: accomplishments,
  readingAbility: ability,
  readingComprehension: comprehension,
  notes: notes,
);

void main() {
  sqfliteFfiInit();
  late AppDatabase db;

  setUp(() async {
    db = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });

  tearDown(() => db.close());

  test('the profile is absent until saved, and can be changed', () async {
    expect(await db.profile(), isNull);

    await db.saveProfile(
      const StudentProfile(studentName: '  Maya ', pronouns: Pronouns.she),
    );
    var profile = (await db.profile())!;
    expect(profile.studentName, 'Maya');
    expect(profile.pronouns, Pronouns.she);
    expect(profile.teacherName, '');
    expect(profile.parentTitle, "Ma'am");

    await db.saveProfile(
      const StudentProfile(
        studentName: 'Maya R.',
        pronouns: Pronouns.they,
        teacherName: ' Coleen ',
        parentTitle: 'Sir',
      ),
    );
    profile = (await db.profile())!;
    expect(profile.studentName, 'Maya R.');
    expect(profile.pronouns, Pronouns.they);
    expect(profile.teacherName, 'Coleen');
    expect(profile.parentTitle, 'Sir');
  });

  test('an entry round-trips with all of its fields', () async {
    await db.saveEntry(
      _entry(
        DateTime(2026, 11, 12, 15, 30),
        accomplishments: 'Read chapter 3 aloud',
        ability: ReadingLevel.onTrack,
        comprehension: ReadingLevel.needsSupport,
        notes: 'Tired after lunch',
      ),
    );

    final saved = await db.entryFor(DateTime(2026, 11, 12));
    expect(saved, isNotNull);
    expect(saved!.date, DateTime(2026, 11, 12));
    expect(saved.accomplishments, 'Read chapter 3 aloud');
    expect(saved.readingAbility, ReadingLevel.onTrack);
    expect(saved.readingComprehension, ReadingLevel.needsSupport);
    expect(saved.notes, 'Tired after lunch');
    expect(saved.parentUpdate, isNull);
  });

  test('saving the same day again updates the entry', () async {
    final day = DateTime(2026, 11, 12);
    await db.saveEntry(_entry(day, accomplishments: 'First draft'));
    final firstId = (await db.entryFor(day))!.id;

    await db.saveEntry(
      _entry(
        day,
        accomplishments: 'Corrected',
        ability: ReadingLevel.excelling,
      ),
    );

    final entries = await db.entries();
    expect(entries, hasLength(1));
    expect(entries.single.id, firstId);
    expect(entries.single.accomplishments, 'Corrected');
    expect(entries.single.readingAbility, ReadingLevel.excelling);
  });

  test(
    'a saved parent update is kept until the entry content changes',
    () async {
      final day = DateTime(2026, 11, 12);
      await db.saveEntry(_entry(day, accomplishments: 'Read aloud'));
      await db.saveParentUpdate(day, 'Hello!');
      expect((await db.entryFor(day))!.parentUpdate, 'Hello!');

      // Saving the same content again keeps it.
      await db.saveEntry(_entry(day, accomplishments: 'Read aloud'));
      expect((await db.entryFor(day))!.parentUpdate, 'Hello!');

      // Changing the entry drops it, as it would describe the old notes.
      await db.saveEntry(_entry(day, accomplishments: 'Read two chapters'));
      expect((await db.entryFor(day))!.parentUpdate, isNull);
    },
  );

  test('entries are listed newest first, and can be deleted', () async {
    await db.saveEntry(_entry(DateTime(2026, 11, 10)));
    await db.saveEntry(_entry(DateTime(2026, 11, 12)));
    await db.saveEntry(_entry(DateTime(2026, 11, 11)));

    expect((await db.entries()).map((e) => e.date.day), [12, 11, 10]);

    await db.deleteEntry(DateTime(2026, 11, 11));
    expect((await db.entries()).map((e) => e.date.day), [12, 10]);
    expect(await db.entryFor(DateTime(2026, 11, 11)), isNull);
  });

  test('listeners are notified after each write', () async {
    var notifications = 0;
    db.addListener(() => notifications++);

    await db.saveProfile(
      const StudentProfile(studentName: 'Maya', pronouns: Pronouns.she),
    );
    await db.saveEntry(_entry(DateTime(2026, 11, 12)));
    await db.saveParentUpdate(DateTime(2026, 11, 12), 'Hello!');
    await db.deleteEntry(DateTime(2026, 11, 12));

    expect(notifications, 4);
  });

  test('students have isolated entries and can be deleted', () async {
    final maya = await db.saveProfile(
      const StudentProfile(studentName: 'Maya', pronouns: Pronouns.she),
    );
    final nikko = await db.saveProfile(
      const StudentProfile(studentName: 'Nikko', pronouns: Pronouns.he),
      asNew: true,
    );

    await db.saveEntry(_entry(DateTime(2026, 11, 12)), maya.id);
    await db.saveEntry(
      _entry(DateTime(2026, 11, 12), accomplishments: 'Read comics'),
      nikko.id,
    );

    expect((await db.entries(maya.id)).single.accomplishments, '');
    expect((await db.entries(nikko.id)).single.accomplishments, 'Read comics');

    await db.deleteStudent(maya.id!);
    expect(await db.profile(maya.id), isNull);
    expect(await db.entries(maya.id), isEmpty);
    expect((await db.profiles()).map((p) => p.studentName), ['Nikko']);
  });

  test(
    'parent updates stay with the student whose entry they describe',
    () async {
      final nikko = await db.saveProfile(
        const StudentProfile(studentName: 'Nikko', pronouns: Pronouns.he),
      );
      final brian = await db.saveProfile(
        const StudentProfile(studentName: 'Brian', pronouns: Pronouns.he),
        asNew: true,
      );
      final date = DateTime(2026, 11, 15);

      await db.saveEntry(_entry(date, accomplishments: 'Read aloud'), nikko.id);
      await db.saveEntry(
        _entry(date, accomplishments: 'Retold the story'),
        brian.id,
      );
      await db.saveParentUpdate(date, 'Nikko update', nikko.id);
      await db.saveParentUpdate(date, 'Brian update', brian.id);

      expect((await db.entryFor(date, nikko.id))!.parentUpdate, 'Nikko update');
      expect((await db.entryFor(date, brian.id))!.parentUpdate, 'Brian update');
    },
  );

  test('a version 1 database is upgraded without losing data', () async {
    final dir = Directory.systemTemp.createTempSync('classwork_pulse');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = p.join(dir.path, 'v1.db');

    final v1 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE student (id INTEGER PRIMARY KEY CHECK (id = 1), '
            'name TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE daily_entries (id INTEGER PRIMARY KEY '
            'AUTOINCREMENT, entry_date TEXT NOT NULL UNIQUE, accomplishments '
            "TEXT NOT NULL DEFAULT '', reading_ability INTEGER NOT NULL, "
            'reading_comprehension INTEGER NOT NULL, notes TEXT NOT NULL '
            "DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
          );
          await db.insert('student', {'id': 1, 'name': 'Nikko'});
          await db.insert('daily_entries', {
            'entry_date': '2026-11-10',
            'accomplishments': 'Read in one go',
            'reading_ability': 3,
            'reading_comprehension': 2,
            'notes': '',
            'created_at': 'x',
            'updated_at': 'x',
          });
        },
      ),
    );
    await v1.close();

    final upgraded = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(upgraded.close);

    final profile = (await upgraded.profile())!;
    expect(profile.studentName, 'Nikko');
    expect(profile.pronouns, Pronouns.they);
    expect(profile.parentTitle, "Ma'am");

    final entry = (await upgraded.entryFor(DateTime(2026, 11, 10)))!;
    expect(entry.accomplishments, 'Read in one go');
    expect(entry.parentUpdate, isNull);
    await upgraded.saveParentUpdate(entry.date, 'Hello!');
    expect((await upgraded.entryFor(entry.date))!.parentUpdate, 'Hello!');
  });
}
