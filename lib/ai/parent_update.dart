import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:llamadart/llamadart.dart';

import '../models/daily_entry.dart';
import '../models/student_profile.dart';

/// The parts of a parent update that the model writes. The greeting, headings,
/// reading ratings, thanks and sign-off around them are added by
/// [ParentUpdate.compose].
class ParentUpdateContent {
  const ParentUpdateContent({
    required this.progress,
    required this.reminders,
    required this.goals,
    required this.encouragement,
  });

  factory ParentUpdateContent.fromJson(Map<String, dynamic> json) =>
      ParentUpdateContent(
        progress: _lines(json['progress']),
        reminders: _lines(json['reminders']),
        goals: _lines(json['goals']),
        encouragement: (json['encouragement'] as String? ?? '').trim(),
      );

  /// What the student did, for the parent. Empty when the entry has no notes.
  final List<String> progress;

  /// Things the parent can do at home.
  final List<String> reminders;
  final List<String> goals;

  /// Praise addressed to the student.
  final String encouragement;

  static List<String> _lines(Object? value) => [
    for (final line in value as List<dynamic>? ?? const [])
      if (line is String && line.trim().isNotEmpty) line.trim(),
  ];
}

/// Writes the message a teacher sends to a parent about one day's classwork.
///
/// The model only writes the content, as JSON constrained to a schema, so the
/// message always comes out complete and in the same layout. The sentence
/// about the reading ratings is written here rather than by the model, so the
/// ratings a parent reads are always the ones the teacher entered.
abstract final class ParentUpdate {
  static const String systemPrompt =
      'You help a teacher write warm, simple classwork updates for a '
      "student's parent. The teacher's notes are short classroom shorthand; "
      'turn each one into a clear, kind sentence. Write about only the '
      'skills in the notes for this student; never add other skills, '
      'subjects or events.';

  /// Whether the teacher wrote anything beyond the two reading ratings.
  static bool hasNotes(DailyEntry entry) =>
      entry.accomplishments.trim().isNotEmpty || entry.notes.trim().isNotEmpty;

  /// JSON schema the model's reply for [entry] is constrained to.
  ///
  /// The upper bounds are well above what the worked example produces; they
  /// only stop a runaway line from using up the reply.
  static Map<String, dynamic> schema(DailyEntry entry) {
    final withProgress = hasNotes(entry);
    return {
      'type': 'object',
      'properties': {
        if (withProgress)
          'progress': {
            'type': 'array',
            'items': {'type': 'string', 'minLength': 20, 'maxLength': 240},
            'minItems': 1,
            'maxItems': 3,
          },
        'reminders': {
          'type': 'array',
          'items': {'type': 'string', 'minLength': 15, 'maxLength': 200},
          'minItems': 3,
          'maxItems': 4,
        },
        'goals': {
          'type': 'array',
          'items': {'type': 'string', 'minLength': 10, 'maxLength': 160},
          'minItems': 3,
          'maxItems': 4,
        },
        'encouragement': {'type': 'string', 'minLength': 20, 'maxLength': 220},
      },
      'required': [
        if (withProgress) 'progress',
        'reminders',
        'goals',
        'encouragement',
      ],
      'additionalProperties': false,
    };
  }

  /// The conversation sent to the model for [entry]: instructions, one worked
  /// example, then the real request. The example is what teaches a small
  /// model the tone and how to turn a teacher's shorthand into sentences.
  static List<LlamaChatMessage> messages(
    StudentProfile profile,
    DailyEntry entry,
  ) {
    final withNotes = hasNotes(entry);
    // The example carries the same ratings as the real entry, so anything the
    // model borrows from it about reading is still true.
    final exampleEntry = DailyEntry(
      date: DateTime(2026, 1, 12),
      accomplishments: withNotes
          ? 'Can spell 3 letter words\nCan add numbers up to 10'
          : '',
      readingAbility: entry.readingAbility,
      readingComprehension: entry.readingComprehension,
      notes: '',
    );
    return [
      const LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text: systemPrompt,
      ),
      LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: request(_exampleProfile, exampleEntry),
      ),
      LlamaChatMessage.fromText(
        role: LlamaChatRole.assistant,
        text: jsonEncode(withNotes ? _exampleWithNotes : _exampleReadingOnly),
      ),
      LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: request(profile, entry),
      ),
    ];
  }

  static const StudentProfile _exampleProfile = StudentProfile(
    studentName: 'Liam',
    pronouns: Pronouns.he,
  );

  static const Map<String, Object> _exampleWithNotes = {
    'progress': [
      'Liam is doing well in class and can now spell three-letter words '
          'correctly.',
      'He can also add numbers up to 10 with confidence.',
    ],
    'reminders': [
      'Encourage Liam to spell simple words aloud at home.',
      'Give him small addition problems using toys or snacks.',
      'Read a short story together every day and let him read some lines '
          'aloud.',
    ],
    'goals': [
      'To spell longer words correctly.',
      'To add numbers up to 20.',
      'To read short sentences smoothly.',
    ],
    'encouragement':
        'Keep up the great work, Liam! You are working so hard on your '
        'spelling and adding. Keep practicing and you will get even better!',
  };

  static const Map<String, Object> _exampleReadingOnly = {
    'reminders': [
      'Read a short story together every day and let him read some lines '
          'aloud.',
      'Ask him to tell you what the story was about.',
      'Praise him when he sounds out a difficult word.',
    ],
    'goals': [
      'To read short sentences smoothly.',
      'To retell a short story in his own words.',
      'To read a little every day.',
    ],
    'encouragement':
        'Keep up the great work, Liam! You are trying so hard with your '
        'reading. Keep practicing and you will get even better!',
  };

  /// The request sent to the model for [entry].
  static String request(StudentProfile profile, DailyEntry entry) {
    final name = profile.studentName;
    final out = StringBuffer()
      ..writeln(
        "Write today's classwork update for the parent of $name "
        '(${profile.pronouns.label}).',
      )
      ..writeln()
      ..writeln(
        "Teacher's notes for "
        '${DateFormat('EEEE, d MMMM y').format(entry.date)}:',
      );
    final accomplishments = _flatten(entry.accomplishments);
    if (accomplishments.isNotEmpty) {
      out.writeln('- What $name did: $accomplishments');
    }
    final notes = _flatten(entry.notes);
    if (notes.isNotEmpty) out.writeln('- Other notes: $notes');
    out
      ..writeln('- Reading: ${entry.readingSentence(profile)}')
      ..writeln()
      ..writeln('Reply with JSON:');
    if (hasNotes(entry)) {
      out.writeln(
        '- "progress": 1 to 3 sentences telling the parent what $name did '
        'and can do, from the notes only. Leave out the reading line; it is '
        'added separately.',
      );
    }
    out
      ..writeln(
        '- "reminders": 3 or 4 short things the parent can do at home to '
        'help $name practise these same skills.',
      )
      ..writeln(
        '- "goals": 3 or 4 short next steps for these same skills, each '
        'starting with "To".',
      )
      ..writeln(
        '- "encouragement": praise said directly to $name, starting with '
        '"Keep up the great work, $name!".',
      );
    return out.toString();
  }

  /// Lays the model's content out as the finished message.
  static String compose(
    StudentProfile profile,
    DailyEntry entry,
    ParentUpdateContent content,
  ) {
    final name = profile.studentName;
    final parent = profile.parentTitle;
    final teacher = profile.teacherName.trim();
    final signOff = teacher.isEmpty ? "$name's teacher" : 'Teacher $teacher';
    final praise = content.encouragement.isEmpty
        ? 'Keep up the great work, $name!'
        : content.encouragement;

    return [
      "Hello $parent! 👋😊 This is an update on $name's classwork progress.",
      '📚 CLASSWORK PROGRESS',
      ...content.progress,
      entry.readingSentence(profile),
      '📌 INSTRUCTIONS / REMINDERS',
      ...content.reminders,
      '🎯 GOALS',
      ...content.goals,
      '$praise 👏',
      'Thank you so much, $parent, for your support at home! Regular '
          'practice with $name will help ${profile.pronouns.object} '
          'strengthen these skills even more. Thank you for your guidance '
          'and encouragement! 🥰🩵',
      'See you in our next class, $name!',
      '— $signOff 🩵',
    ].join('\n\n');
  }

  /// Joins multi-line notes into one line so they read as a single item.
  static String _flatten(String text) => text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) => RegExp(r'[.!?]$').hasMatch(line) ? line : '$line.')
      .join(' ');
}
