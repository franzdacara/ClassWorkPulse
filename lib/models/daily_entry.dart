import 'student_profile.dart';

/// Four-step scale used for both reading ability and reading comprehension.
enum ReadingLevel {
  needsSupport(1, 'Needs support'),
  developing(2, 'Developing'),
  onTrack(3, 'On track'),
  excelling(4, 'Excelling');

  const ReadingLevel(this.score, this.label);

  /// Numeric value stored in the database (1 = lowest, 4 = highest).
  final int score;
  final String label;

  static const int maxScore = 4;

  static ReadingLevel fromScore(int score) => values.firstWhere(
    (level) => level.score == score,
    orElse: () => ReadingLevel.developing,
  );
}

/// One day's record of what the student did and how their reading went.
class DailyEntry {
  DailyEntry({
    this.id,
    required DateTime date,
    required this.accomplishments,
    required this.readingAbility,
    required this.readingComprehension,
    required this.notes,
    this.parentUpdate,
  }) : date = dateOnly(date);

  final int? id;

  /// Calendar day of the entry (time of day is always midnight).
  final DateTime date;
  final String accomplishments;
  final ReadingLevel readingAbility;
  final ReadingLevel readingComprehension;
  final String notes;

  /// The parent update last written for this entry, if any. It is dropped
  /// when the entry's content changes.
  final String? parentUpdate;

  factory DailyEntry.fromMap(Map<String, Object?> map) => DailyEntry(
    id: map['id'] as int?,
    date: DateTime.parse(map['entry_date'] as String),
    accomplishments: map['accomplishments'] as String? ?? '',
    readingAbility: ReadingLevel.fromScore(map['reading_ability'] as int),
    readingComprehension: ReadingLevel.fromScore(
      map['reading_comprehension'] as int,
    ),
    notes: map['notes'] as String? ?? '',
    parentUpdate: map['parent_update'] as String?,
  );

  /// The two reading ratings as one plain sentence, for example "Maya is on
  /// track with reading aloud, and her understanding of what was read is
  /// still developing."
  ///
  /// Written here rather than by the model, so the ratings are always stated
  /// exactly as they were entered.
  String readingSentence(StudentProfile profile) {
    final name = profile.studentName;
    final aloud = switch (readingAbility) {
      ReadingLevel.needsSupport =>
        '$name still needs support when reading aloud',
      ReadingLevel.developing => "$name's reading aloud is still developing",
      ReadingLevel.onTrack => '$name is on track with reading aloud',
      ReadingLevel.excelling => '$name is excelling at reading aloud',
    };
    final understanding = switch (readingComprehension) {
      ReadingLevel.needsSupport => 'still needs support',
      ReadingLevel.developing => 'is still developing',
      ReadingLevel.onTrack => 'is on track',
      ReadingLevel.excelling => 'is excellent',
    };
    return '$aloud, and ${profile.pronouns.possessive} understanding of '
        'what was read $understanding.';
  }

  /// The content columns of the `daily_entries` table (no id, timestamps or
  /// parent update).
  Map<String, Object?> toMap() => {
    'entry_date': dateKey(date),
    'accomplishments': accomplishments,
    'reading_ability': readingAbility.score,
    'reading_comprehension': readingComprehension.score,
    'notes': notes,
  };
}

/// Strips the time of day.
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// `yyyy-MM-dd`, the form dates are stored in.
String dateKey(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
