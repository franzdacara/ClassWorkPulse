import 'package:classwork_pulse/ai/progress_context.dart';
import 'package:classwork_pulse/models/daily_entry.dart';
import 'package:classwork_pulse/models/student_profile.dart';
import 'package:flutter_test/flutter_test.dart';

DailyEntry _entry(
  int day, {
  int ability = 2,
  int comprehension = 2,
  String accomplishments = '',
  String notes = '',
}) => DailyEntry(
  date: DateTime(2026, 11, day),
  accomplishments: accomplishments,
  readingAbility: ReadingLevel.fromScore(ability),
  readingComprehension: ReadingLevel.fromScore(comprehension),
  notes: notes,
);

const _maya = StudentProfile(studentName: 'Maya', pronouns: Pronouns.she);
final _today = DateTime(2026, 11, 15);

void main() {
  test('with no entries the prompt says nothing has been recorded', () {
    final prompt = ProgressContext.build(
      profile: _maya,
      entries: const [],
      today: _today,
    );

    expect(prompt, contains('Maya'));
    expect(prompt, contains('RECORDS: none'));
    expect(prompt, isNot(contains('DAILY RECORDS')));
  });

  test('records are listed oldest first with ratings and text', () {
    final prompt = ProgressContext.build(
      profile: _maya,
      // Newest first, as the database returns them.
      entries: [
        _entry(12, ability: 3, comprehension: 4, notes: 'Asked for more'),
        _entry(
          10,
          ability: 1,
          comprehension: 2,
          accomplishments: 'Read a\nshort   story',
        ),
      ],
      today: _today,
    );

    expect(prompt, contains('Today is Sunday, 15 November 2026.'));
    expect(
      prompt,
      contains(
        '2026-11-10 Tue | Reading ability: 1 (Needs support) | '
        'Reading comprehension: 2 (Developing) | '
        'Accomplished: Read a short story',
      ),
    );
    expect(
      prompt,
      contains(
        '2026-11-12 Thu | Reading ability: 3 (On track) | '
        'Reading comprehension: 4 (Excelling) | Notes: Asked for more',
      ),
    );
    expect(
      prompt.indexOf('2026-11-10 Tue'),
      lessThan(prompt.indexOf('2026-11-12 Thu')),
    );
  });

  test('key facts state the latest ratings in words, with pronouns', () {
    final prompt = ProgressContext.build(
      profile: _maya,
      entries: [_entry(12, ability: 3, comprehension: 2)],
      today: _today,
    );

    expect(prompt, contains("Maya's pronouns are she/her."));
    expect(prompt, contains('1 entry has been saved, on 2026-11-12.'));
    expect(
      prompt,
      contains(
        'Latest entry (2026-11-12): Maya is on track with reading aloud, and '
        'her understanding of what was read is still developing.',
      ),
    );
    expect(prompt, isNot(contains('over time:')));
  });

  test('trends are reported once there are enough entries', () {
    final prompt = ProgressContext.build(
      profile: _maya,
      entries: [
        _entry(9, ability: 1, comprehension: 3),
        _entry(10, ability: 2, comprehension: 3),
        _entry(11, ability: 3, comprehension: 3),
        _entry(12, ability: 4, comprehension: 2),
      ],
      today: _today,
    );

    expect(prompt, contains('4 entries have been saved, from 2026-11-09'));
    expect(
      prompt,
      contains(
        'Reading ability over time: improving (earlier entries averaged 1.5 '
        'out of 4, recent entries averaged 3.5).',
      ),
    );
    expect(prompt, contains('Reading comprehension over time: steady'));
  });

  test('a falling series is reported as declining', () {
    final prompt = ProgressContext.build(
      profile: _maya,
      entries: [
        for (final (day, score) in [(1, 4), (2, 4), (3, 2), (4, 1)])
          _entry(day, ability: score),
      ],
      today: _today,
    );

    expect(prompt, contains('Reading ability over time: declining'));
  });

  test('limiting the listed records keeps the key facts complete', () {
    final prompt = ProgressContext.build(
      profile: _maya,
      entries: [for (var day = 1; day <= 10; day++) _entry(day)],
      today: _today,
      recentCount: 3,
    );

    expect(prompt, contains('10 entries have been saved'));
    expect(prompt, contains('only the 3 most recent of 10 entries'));
    expect(prompt, isNot(contains('2026-11-07 Sat |')));
    expect(prompt, contains('2026-11-08 Sun |'));
    expect(prompt, contains('2026-11-10 Tue |'));
  });

  test('long notes are shortened', () {
    final prompt = ProgressContext.build(
      profile: _maya,
      entries: [_entry(12, notes: 'word ' * 200)],
      today: _today,
    );

    final line = prompt.split('\n').firstWhere((l) => l.contains('Notes:'));
    expect(line.length, lessThan(420));
    expect(line, endsWith('...'));
  });

  test('fit drops the oldest records until the prompt fits', () async {
    final entries = [
      for (var day = 1; day <= 28; day++)
        _entry(day, accomplishments: 'Read pages $day to ${day + 5} aloud'),
    ];
    // Roughly four characters per token.
    Future<int> countTokens(String text) async => (text.length / 4).ceil();

    final full = ProgressContext.build(
      profile: _maya,
      entries: entries,
      today: _today,
    );
    final budget = await countTokens(full) ~/ 2;

    final fitted = await ProgressContext.fit(
      profile: _maya,
      entries: entries,
      today: _today,
      countTokens: countTokens,
      tokenBudget: budget,
    );

    expect(await countTokens(fitted), lessThanOrEqualTo(budget));
    expect(fitted, contains('28 entries have been saved'));
    expect(fitted, contains('2026-11-28 Sat |'), reason: 'newest is kept');
    expect(
      fitted,
      isNot(contains('2026-11-01 Sun |')),
      reason: 'oldest is dropped',
    );
  });

  test('questions carry the answering rules', () {
    final wrapped = ProgressContext.question(_maya, 'How is Maya doing?');
    expect(wrapped, startsWith('How is Maya doing?\n\n('));
    expect(wrapped, contains("using only what Maya's records say"));
  });
}
