// Temporary harness: runs the real prompt builders against the bundled model
// on this machine. Not part of the app.
import 'dart:io';

import 'package:classwork_pulse/ai/parent_update.dart';
import 'package:classwork_pulse/ai/progress_context.dart';
import 'package:classwork_pulse/models/daily_entry.dart';
import 'package:classwork_pulse/models/student_profile.dart';
import 'package:llamadart/llamadart.dart';

DailyEntry e(int day, int ability, int comp, String did, [String notes = '']) =>
    DailyEntry(
      date: DateTime(2026, 11, day),
      accomplishments: did,
      readingAbility: ReadingLevel.fromScore(ability),
      readingComprehension: ReadingLevel.fromScore(comp),
      notes: notes,
    );

final many = [
  e(
    2,
    1,
    2,
    'Read 5 pages of The Gruffalo aloud with help',
    'Guessed at long words instead of sounding them out',
  ),
  e(
    3,
    2,
    2,
    'Practised sight words; read a short poem',
    'Needed reminders to slow down',
  ),
  e(
    4,
    2,
    1,
    'Read a non-fiction page about volcanoes',
    'Could not explain what the page was about',
  ),
  e(5, 2, 2, 'Reread The Gruffalo, 10 pages', ''),
  e(
    6,
    2,
    2,
    'Read aloud to a partner for 10 minutes',
    'More confident, fewer stops',
  ),
  e(
    9,
    3,
    2,
    'Finished The Gruffalo and retold the ending',
    'Retelling missed the middle of the story',
  ),
  e(10, 3, 2, 'Started Fantastic Mr Fox, chapter 1', ''),
  e(
    11,
    3,
    3,
    'Chapter 2; answered who/what/where questions',
    'Answered 4 of 5 questions correctly',
  ),
  e(12, 3, 2, 'Chapter 3', 'Distracted, rushed the questions'),
  e(
    13,
    4,
    3,
    'Chapters 4 and 5 read independently',
    'Self-corrected mistakes without prompting',
  ),
];
final one = [e(15, 3, 2, '', '')];

const nikko = StudentProfile(
  studentName: 'Nikko',
  pronouns: Pronouns.she,
  teacherName: 'Coleen',
);
const maya = StudentProfile(
  studentName: 'Maya',
  pronouns: Pronouns.she,
  teacherName: 'Coleen',
);
const sam = StudentProfile(
  studentName: 'Sam',
  pronouns: Pronouns.he,
  parentTitle: 'Sir',
);

Future<void> main(List<String> args) async {
  final temp = double.parse(
    args
        .firstWhere((a) => a.startsWith('t='), orElse: () => 't=0.2')
        .substring(2),
  );
  final penalty = double.parse(
    args
        .firstWhere((a) => a.startsWith('p='), orElse: () => 'p=1.0')
        .substring(2),
  );
  final updateTemp = double.parse(
    args
        .firstWhere((a) => a.startsWith('ut='), orElse: () => 'ut=0.5')
        .substring(3),
  );
  stdout.writeln('temp=$temp penalty=$penalty updateTemp=$updateTemp');
  final engine = LlamaEngine(LlamaBackend());
  final sw = Stopwatch()..start();
  await engine.setModel(
    LlamaModel(
      ModelSource.path('assets/models/Llama-3.2-1B-Instruct-Q4_K_M.gguf'),
    ),
    params: const ModelParams(contextSize: 4096),
  );
  stdout.writeln(
    'loaded in ${sw.elapsedMilliseconds} ms on ${await engine.getBackendName()}',
  );
  try {
    if (!args.contains('--no-chat')) {
      for (final (label, profile, entries, questions) in [
        (
          'ONE ENTRY',
          nikko,
          one,
          ['Can nikko read?', ProgressContext.summaryRequest(nikko)],
        ),
        (
          'TEN ENTRIES',
          maya,
          many,
          [
            ProgressContext.summaryRequest(maya),
            'Based on the records, what should we focus on next to help Maya improve?',
            'What happened on November 4?',
            'How is Maya doing in math?',
          ],
        ),
        (
          'NO ENTRIES',
          sam,
          <DailyEntry>[],
          ["Summarize Sam's reading progress so far."],
        ),
      ]) {
        final prompt = await ProgressContext.fit(
          profile: profile,
          entries: entries,
          today: DateTime(2026, 11, 15),
          countTokens: engine.getTokenCount,
          tokenBudget: 1800,
        );
        stdout.writeln(
          '\n================ $label: system prompt = ${await engine.getTokenCount(prompt)} tokens',
        );
        if (args.contains('--show-prompt')) stdout.writeln(prompt);
        final session = ChatSession(engine, systemPrompt: prompt);
        for (final q in questions) {
          sw.reset();
          final reply = await session.send(
            ProgressContext.question(profile, q),
            params: GenerationParams(
              maxTokens: 512,
              temp: temp,
              penalty: penalty,
            ),
            enableThinking: false,
          );
          stdout.writeln('\n--- Q: $q');
          stdout.writeln(reply.text.trimRight());
          stdout.writeln(
            '    [${sw.elapsedMilliseconds} ms, usage: ${reply.usage?.promptTokens}/${reply.usage?.completionTokens}, finish: ${reply.finishReason}]',
          );
        }
      }
    }

    for (final (label, profile, entry) in [
      (
        'NIKKO SAMPLE',
        nikko,
        e(15, 3, 2, 'Can Read in one go\nCan write numbers\nCan Call numbers'),
      ),
      ('MAYA NOV 12', maya, many[8]),
      ('SAM RATINGS ONLY', sam, e(15, 1, 2, '')),
    ]) {
      stdout.writeln('\n================ PARENT UPDATE: $label');
      if (args.contains('--show-prompt')) {
        stdout.writeln(ParentUpdate.request(profile, entry));
      }
      sw.reset();
      final content = await engine.createStructuredJson(
        ParentUpdate.messages(profile, entry),
        output: LlamaStructuredOutput<ParentUpdateContent>.jsonSchema(
          schema: ParentUpdate.schema(entry),
          decoder: ParentUpdateContent.fromJson,
        ),
        params: GenerationParams(
          maxTokens: 700,
          temp: updateTemp,
          penalty: penalty,
        ),
        enableThinking: false,
      );
      stdout.writeln(ParentUpdate.compose(profile, entry, content));
      stdout.writeln('    [${sw.elapsedMilliseconds} ms]');
    }
  } finally {
    await engine.dispose();
  }
}
