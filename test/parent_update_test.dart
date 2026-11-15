import 'dart:convert';

import 'package:classwork_pulse/ai/parent_update.dart';
import 'package:classwork_pulse/models/daily_entry.dart';
import 'package:classwork_pulse/models/student_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';

const _nikko = StudentProfile(
  studentName: 'Nikko',
  pronouns: Pronouns.she,
  teacherName: 'Coleen',
);

DailyEntry _entry({String accomplishments = '', String notes = ''}) =>
    DailyEntry(
      date: DateTime(2026, 11, 15),
      accomplishments: accomplishments,
      readingAbility: ReadingLevel.onTrack,
      readingComprehension: ReadingLevel.developing,
      notes: notes,
    );

void main() {
  test('compose lays the content out like the sample message', () {
    final text = ParentUpdate.compose(
      _nikko,
      _entry(accomplishments: 'Can read in one go'),
      const ParentUpdateContent(
        progress: ['Nikko can read a text in one go.'],
        reminders: ['Encourage Nikko to read aloud at home.'],
        goals: ['To read longer passages smoothly.'],
        encouragement: 'Keep up the great work, Nikko! You are doing great!',
      ),
    );

    expect(
      text,
      "Hello Ma'am! 👋😊 This is an update on Nikko's classwork progress.\n\n"
      '📚 CLASSWORK PROGRESS\n\n'
      'Nikko can read a text in one go.\n\n'
      'Nikko is on track with reading aloud, and her understanding of what '
      'was read is still developing.\n\n'
      '📌 INSTRUCTIONS / REMINDERS\n\n'
      'Encourage Nikko to read aloud at home.\n\n'
      '🎯 GOALS\n\n'
      'To read longer passages smoothly.\n\n'
      'Keep up the great work, Nikko! You are doing great! 👏\n\n'
      "Thank you so much, Ma'am, for your support at home! Regular practice "
      'with Nikko will help her strengthen these skills even more. Thank you '
      'for your guidance and encouragement! 🥰🩵\n\n'
      'See you in our next class, Nikko!\n\n'
      '— Teacher Coleen 🩵',
    );
  });

  test('without a teacher name the sign-off still reads naturally', () {
    final text = ParentUpdate.compose(
      const StudentProfile(
        studentName: 'Sam',
        pronouns: Pronouns.he,
        parentTitle: 'Sir',
      ),
      _entry(),
      const ParentUpdateContent(
        progress: [],
        reminders: [],
        goals: [],
        encouragement: '',
      ),
    );

    expect(text, startsWith('Hello Sir!'));
    expect(text, contains('help him strengthen'));
    expect(text, contains('Keep up the great work, Sam! 👏'));
    expect(text, endsWith("— Sam's teacher 🩵"));
  });

  test('the request passes the teacher notes and the ratings in words', () {
    final request = ParentUpdate.request(
      _nikko,
      _entry(accomplishments: 'Can Read in one go\nCan write numbers'),
    );

    expect(request, contains('parent of Nikko (she/her)'));
    expect(
      request,
      contains('- What Nikko did: Can Read in one go. Can write numbers.'),
    );
    expect(request, contains('- Reading: Nikko is on track with reading'));
    expect(request, contains('"progress"'));
  });

  test('entries with only ratings ask for no progress sentences', () {
    final entry = _entry();
    expect(ParentUpdate.hasNotes(entry), isFalse);
    expect(ParentUpdate.request(_nikko, entry), isNot(contains('"progress"')));
    expect(
      (ParentUpdate.schema(entry)['required'] as List),
      isNot(contains('progress')),
    );
  });

  test('both schemas are accepted by the constrained decoder', () {
    for (final entry in [_entry(), _entry(notes: 'Tired today')]) {
      expect(
        () => LlamaStructuredOutput<ParentUpdateContent>.jsonSchema(
          schema: ParentUpdate.schema(entry),
          decoder: ParentUpdateContent.fromJson,
        ),
        returnsNormally,
      );
    }
  });

  test('the worked example matches the schema it teaches', () {
    for (final entry in [_entry(), _entry(notes: 'Tired today')]) {
      final messages = ParentUpdate.messages(_nikko, entry);
      expect(messages, hasLength(4));
      final example = jsonDecode(messages[2].content) as Map<String, dynamic>;
      final schema = ParentUpdate.schema(entry);
      expect(example.keys.toSet(), (schema['properties'] as Map).keys.toSet());
    }
  });

  test('content parsing ignores blank lines', () {
    final content = ParentUpdateContent.fromJson({
      'progress': ['  One.  ', ''],
      'reminders': ['Two.'],
      'goals': <String>[],
      'encouragement': ' Three. ',
    });
    expect(content.progress, ['One.']);
    expect(content.encouragement, 'Three.');
  });
}
