import 'package:classwork_pulse/data/app_database.dart';
import 'package:classwork_pulse/main.dart';
import 'package:classwork_pulse/models/daily_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Database calls complete on real time, which widget tests do not advance,
/// so wait in real time until [finder] matches.
Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('Timed out waiting for $finder');
}

void main() {
  sqfliteFfiInit();

  testWidgets('first launch asks for a name, then entries can be logged', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = (await tester.runAsync(
      () => AppDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      ),
    ))!;

    await tester.pumpWidget(ClassWorkPulseApp(database: db));

    // Onboarding: no student has been saved yet.
    await _pumpUntilFound(tester, find.text('Welcome to ClassWorkPulse'));
    await tester.enterText(find.byType(TextField).first, 'Maya');
    await tester.pump();
    await tester.tap(find.text('Get started'));
    await _pumpUntilFound(tester, find.text("Maya's daily log"));
    expect(await tester.runAsync(db.studentName), 'Maya');

    // Saving without ratings is refused.
    await tester.tap(find.text('Save entry'));
    await tester.pump();
    expect(find.text('Choose a rating to save the entry.'), findsNWidgets(2));

    // Fill in today's entry and save it.
    await tester.enterText(
      find.byType(TextField).first,
      'Read a picture book aloud',
    );
    await tester.tap(find.text('On track').first);
    await tester.tap(find.text('Developing').last);
    await tester.pump();
    await tester.tap(find.text('Save entry'));
    await _pumpUntilFound(tester, find.text('Update entry'));

    final saved = (await tester.runAsync(db.entries))!;
    expect(saved, hasLength(1));
    expect(saved.single.date, dateOnly(DateTime.now()));
    expect(saved.single.accomplishments, 'Read a picture book aloud');
    expect(saved.single.readingAbility, ReadingLevel.onTrack);
    expect(saved.single.readingComprehension, ReadingLevel.developing);

    // The entry shows up in the history.
    await tester.tap(find.text('History'));
    await _pumpUntilFound(tester, find.text('Reading ability: On track'));
    expect(find.text('Comprehension: Developing'), findsOneWidget);

    await tester.runAsync(db.close);
  });
}
