import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../models/daily_entry.dart';
import '../models/student_profile.dart';

/// Turns the saved daily entries into the system prompt that the on-device
/// model answers questions from.
///
/// Trends are calculated here rather than left to the model: small models are
/// unreliable at arithmetic, and the key facts still cover every entry when
/// only the most recent ones fit in the context window.
abstract final class ProgressContext {
  /// Upper bound on listed records, whatever the token budget allows.
  static const int _maxRecords = 60;

  /// Longest free-text field passed to the model, in characters.
  static const int _maxFieldChars = 280;

  /// Entries needed before a trend is reported.
  static const int _minEntriesForTrend = 4;

  /// Builds the prompt with as many recent records as fit in [tokenBudget].
  ///
  /// [entries] may be in any order. [countTokens] should use the loaded
  /// model's tokenizer.
  static Future<String> fit({
    required StudentProfile profile,
    required List<DailyEntry> entries,
    required DateTime today,
    required Future<int> Function(String text) countTokens,
    required int tokenBudget,
  }) async {
    var count = math.min(entries.length, _maxRecords);
    while (true) {
      final prompt = build(
        profile: profile,
        entries: entries,
        today: today,
        recentCount: count,
      );
      if (count == 0) return prompt;
      final tokens = await countTokens(prompt);
      if (tokens <= tokenBudget) return prompt;
      final scaled = (count * tokenBudget / tokens * 0.9).floor();
      count = math.max(0, math.min(count - 1, scaled));
    }
  }

  /// Builds the prompt listing the [recentCount] most recent records (all of
  /// them when null). The key facts always cover every entry.
  static String build({
    required StudentProfile profile,
    required List<DailyEntry> entries,
    required DateTime today,
    int? recentCount,
  }) {
    final name = profile.studentName;
    final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
    final listed = recentCount == null || recentCount >= sorted.length
        ? sorted
        : sorted.sublist(sorted.length - math.max(0, recentCount));

    final out = StringBuffer()
      ..writeln(
        'You are the ClassWorkPulse assistant. A teacher is asking about a '
        'student named $name. Answer using only the reading records below.',
      )
      ..writeln()
      ..writeln('Today is ${DateFormat('EEEE, d MMMM y').format(today)}.')
      ..writeln(
        'Rating scale: '
        '${ReadingLevel.values.map((l) => '${l.score} = ${l.label}').join(', ')} '
        '(${ReadingLevel.maxScore} is best).',
      )
      ..writeln(
        'Reading ability means how accurately and fluently $name reads '
        'aloud. Reading comprehension means how well $name understands what '
        'was read.',
      )
      ..writeln();

    if (sorted.isEmpty) {
      out.writeln(
        'RECORDS: none. No daily entries have been saved yet. Reply that '
        'nothing has been recorded for $name yet, and suggest saving a daily '
        'entry in the Today tab first. Do not describe any progress.',
      );
      return out.toString();
    }

    // Facts are written as plain statements the model can repeat: small
    // models reuse stated facts far more reliably than they follow rules.
    out
      ..writeln('KEY FACTS (already calculated, trust these)')
      ..writeln("- $name's pronouns are ${profile.pronouns.label}.");
    if (sorted.length == 1) {
      out.writeln(
        '- 1 entry has been saved, on ${dateKey(sorted.single.date)}. '
        'Progress over time cannot be described yet.',
      );
    } else {
      out.writeln(
        '- ${sorted.length} entries have been saved, from '
        '${dateKey(sorted.first.date)} to ${dateKey(sorted.last.date)}.',
      );
    }
    final latest = sorted.last;
    out.writeln(
      '- Latest entry (${dateKey(latest.date)}): '
      '${latest.readingSentence(profile)}',
    );
    if (sorted.length >= _minEntriesForTrend) {
      out
        ..writeln(
          '- Reading ability over time: '
          '${_trend(sorted.map((e) => e.readingAbility.score).toList())}',
        )
        ..writeln(
          '- Reading comprehension over time: '
          '${_trend(sorted.map((e) => e.readingComprehension.score).toList())}',
        );
    } else if (sorted.length > 1) {
      out.writeln('- There are too few entries to describe a trend yet.');
    }
    out
      ..writeln(
        '- Ratings are only kept for reading. Nothing is rated or recorded '
        'for other subjects.',
      )
      ..writeln();

    if (listed.isNotEmpty) {
      final scope = listed.length < sorted.length
          ? 'only the ${listed.length} most recent of ${sorted.length} '
                'entries, oldest first'
          : 'oldest first';
      out.writeln('DAILY RECORDS ($scope)');
      for (final entry in listed) {
        out.writeln(_recordLine(entry));
      }
    }
    return out.toString();
  }

  /// The question behind the "Generate progress summary" button.
  static String summaryRequest(StudentProfile profile) {
    final name = profile.studentName;
    return "Summarize $name's reading progress so far: reading ability, "
        'reading comprehension, what $name accomplished, and what needs '
        'attention according to the notes.';
  }

  /// Adds the answering rules to a question.
  ///
  /// The rules travel with every question instead of sitting in the system
  /// prompt, because small models follow instructions far more reliably when
  /// they are next to the question, especially later in a conversation.
  static String question(StudentProfile profile, String question) =>
      '$question\n\n'
      '(Answer in two to five plain sentences, using only what '
      "${profile.studentName}'s records say. If the records say nothing "
      'about it, reply that it has not been recorded.)';

  /// Direction of one rating series (oldest first), comparing its earlier
  /// half with its recent half.
  static String _trend(List<int> scores) {
    final half = scores.length ~/ 2;
    final earlier = _average(scores.sublist(0, half));
    final recent = _average(scores.sublist(scores.length - half));
    final change = recent - earlier;
    final direction = change >= 0.5
        ? 'improving'
        : change < -0.5
        ? 'declining'
        : 'steady';
    return '$direction (earlier entries averaged '
        '${earlier.toStringAsFixed(1)} out of ${ReadingLevel.maxScore}, '
        'recent entries averaged ${recent.toStringAsFixed(1)}).';
  }

  static double _average(List<int> scores) =>
      scores.reduce((a, b) => a + b) / scores.length;

  static String _recordLine(DailyEntry entry) {
    final parts = [
      '${dateKey(entry.date)} ${DateFormat('EEE').format(entry.date)}',
      'Reading ability: ${entry.readingAbility.score} '
          '(${entry.readingAbility.label})',
      'Reading comprehension: ${entry.readingComprehension.score} '
          '(${entry.readingComprehension.label})',
    ];
    final accomplishments = _clean(entry.accomplishments);
    if (accomplishments.isNotEmpty) parts.add('Accomplished: $accomplishments');
    final notes = _clean(entry.notes);
    if (notes.isNotEmpty) parts.add('Notes: $notes');
    return parts.join(' | ');
  }

  /// Collapses whitespace to keep each record on one line, and caps length.
  static String _clean(String text) {
    final flat = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (flat.length <= _maxFieldChars) return flat;
    return '${flat.substring(0, _maxFieldChars).trimRight()}...';
  }
}
