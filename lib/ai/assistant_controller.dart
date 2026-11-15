import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:llamadart/llamadart.dart';

import '../data/app_database.dart';
import '../models/daily_entry.dart';
import '../models/student_profile.dart';
import 'model_installer.dart';
import 'parent_update.dart';
import 'progress_context.dart';

enum AssistantStatus {
  idle,

  /// Copying the bundled model into app storage (first use only).
  preparingModel,
  loadingModel,
  ready,

  /// The app was built without a model in `assets/models/`.
  modelMissing,
  unsupported,
  failed,
}

/// Thrown by [AssistantController.writeParentUpdate] when it was stopped.
class ParentUpdateCancelled implements Exception {
  const ParentUpdateCancelled();
}

class ChatMessage {
  ChatMessage.user(this.text) : fromUser = true, isStreaming = false;
  ChatMessage.assistant() : fromUser = false, text = '', isStreaming = true;

  final bool fromUser;
  String text;

  /// True while the model is still writing this message.
  bool isStreaming;
}

/// Owns the on-device model and the conversation with it.
///
/// Every question is answered from a system prompt rebuilt from the local
/// database, so answers always reflect the latest saved entries.
class AssistantController extends ChangeNotifier {
  AssistantController(this._db, this.studentId);

  /// Context window in tokens. Memory use grows with it.
  static const int _contextSize = 4096;
  static const int _maxReplyTokens = 512;

  /// Share of the context given to the system prompt (rules, overview and
  /// records). The rest is left for the conversation and the reply. Kept
  /// moderate because phones read a long prompt slowly.
  static const int _systemPromptTokenBudget = 1800;

  final AppDatabase _db;
  int studentId;
  final List<ChatMessage> messages = [];

  AssistantStatus status = AssistantStatus.idle;

  /// Fraction of the model copied so far, while [status] is preparingModel.
  double? installProgress;
  String? errorMessage;

  bool get isBusy => _busy;

  LlamaEngine? _engine;
  ChatSession? _session;
  StreamSubscription<LlamaCompletionChunk>? _generation;
  ChatMessage? _activeReply;
  final StringBuffer _pending = StringBuffer();
  Timer? _flushTimer;
  Future<void>? _starting;
  bool _busy = false;
  bool _stopRequested = false;
  bool _disposed = false;

  /// Installs (first use) and loads the model. Safe to call repeatedly:
  /// concurrent calls share one load, and a call after a failure retries.
  Future<void> start() {
    if (status == AssistantStatus.ready) return Future.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    errorMessage = null;
    installProgress = null;
    _setStatus(AssistantStatus.preparingModel);
    try {
      final modelPath = await ModelInstaller.ensureInstalled(
        onProgress: (fraction) {
          installProgress = fraction;
          _notify();
        },
      );
      if (_disposed) return;

      _setStatus(AssistantStatus.loadingModel);
      final engine = LlamaEngine(LlamaBackend());
      _engine = engine;
      await engine.setModel(
        LlamaModel(ModelSource.path(modelPath)),
        params: const ModelParams(contextSize: _contextSize),
      );
      if (_disposed) return;

      _session = ChatSession(engine);
      _setStatus(AssistantStatus.ready);
    } on ModelNotBundledException {
      _setStatus(AssistantStatus.modelMissing);
    } on UnsupportedError catch (error) {
      errorMessage = error.message;
      _setStatus(AssistantStatus.unsupported);
    } catch (error) {
      await _discardEngine();
      errorMessage = switch (error) {
        LlamaException() => error.message,
        PlatformException() => error.message ?? error.code,
        _ => error.toString(),
      };
      _setStatus(AssistantStatus.failed);
    }
  }

  /// Asks the model [text]; the reply streams into [messages].
  Future<void> send(String text) async {
    final session = _session;
    final engine = _engine;
    final question = text.trim();
    if (session == null || engine == null || _busy || question.isEmpty) return;

    final reply = ChatMessage.assistant();
    messages
      ..add(ChatMessage.user(question))
      ..add(reply);
    _activeReply = reply;
    _busy = true;
    _stopRequested = false;
    _notify();

    final StudentProfile profile;
    try {
      profile =
          await _db.profile(studentId) ??
          const StudentProfile(
            studentName: 'the student',
            pronouns: Pronouns.they,
          );
      session.systemPrompt = await ProgressContext.fit(
        profile: profile,
        entries: await _db.entries(studentId),
        today: DateTime.now(),
        countTokens: engine.getTokenCount,
        tokenBudget: _systemPromptTokenBudget,
      );
    } catch (error) {
      _finish(error: error);
      return;
    }
    if (_disposed) return;
    if (_stopRequested) {
      _finish();
      return;
    }

    _generation = session
        .create(
          [LlamaTextContent(ProgressContext.question(profile, question))],
          // A low temperature keeps answers close to the records.
          params: const GenerationParams(
            maxTokens: _maxReplyTokens,
            temp: 0.2,
            penalty: 1.0,
          ),
          enableThinking: false,
        )
        .listen(
          (chunk) {
            if (chunk.text.isEmpty) return;
            _pending.write(chunk.text);
            // Batch tokens so the UI rebuilds a few times a second, not per
            // token.
            _flushTimer ??= Timer(const Duration(milliseconds: 50), _flush);
          },
          onError: (Object error) => _finish(error: error),
          onDone: _finish,
          cancelOnError: true,
        );
  }

  /// Stops the reply in progress, keeping what was written so far.
  void stop() {
    if (!_busy) return;
    _stopRequested = true;
    _engine?.cancelGeneration();
  }

  /// Writes the parent update for [entry], saves it with the entry, and
  /// returns it. Loads the model first if needed.
  ///
  /// Throws [StateError] if the model is not available or is busy, and
  /// [ParentUpdateCancelled] if [stop] was called meanwhile.
  Future<String> writeParentUpdate(
    DailyEntry entry, {
    required int studentId,
  }) async {
    await start();
    final engine = _engine;
    if (status != AssistantStatus.ready || engine == null) {
      throw StateError(errorMessage ?? 'The AI model is not available.');
    }
    if (_busy) throw StateError('The assistant is busy. Try again shortly.');

    _busy = true;
    _stopRequested = false;
    _notify();
    try {
      final profile =
          await _db.profile(studentId) ??
          const StudentProfile(
            studentName: 'the student',
            pronouns: Pronouns.they,
          );
      final content = await engine.createStructuredJson(
        ParentUpdate.messages(profile, entry),
        output: LlamaStructuredOutput<ParentUpdateContent>.jsonSchema(
          schema: ParentUpdate.schema(entry),
          decoder: ParentUpdateContent.fromJson,
        ),
        params: const GenerationParams(maxTokens: 700, temp: 0.5, penalty: 1.0),
        enableThinking: false,
      );
      if (_stopRequested) throw const ParentUpdateCancelled();
      final text = ParentUpdate.compose(profile, entry, content);
      await _db.saveParentUpdate(entry.date, text, studentId);
      return text;
    } on LlamaException {
      if (_stopRequested) throw const ParentUpdateCancelled();
      rethrow;
    } finally {
      _busy = false;
      _stopRequested = false;
      _notify();
    }
  }

  /// Clears the conversation.
  void newChat() {
    if (_busy) return;
    messages.clear();
    _session?.reset();
    _notify();
  }

  void switchStudent(int value) {
    if (studentId == value) return;
    if (_busy) stop();
    studentId = value;
    messages.clear();
    _session?.reset();
    _notify();
  }

  void _flush() {
    _flushTimer = null;
    if (_disposed || _pending.isEmpty) return;
    _activeReply?.text += _pending.toString();
    _pending.clear();
    _notify();
  }

  void _finish({Object? error}) {
    _flushTimer?.cancel();
    _flushTimer = null;
    _generation = null;

    final reply = _activeReply;
    _activeReply = null;
    if (reply != null) {
      reply
        ..text = (reply.text + _pending.toString()).trimRight()
        ..isStreaming = false;
      if (reply.text.isEmpty) {
        // Stopping before the first word surfaces as an error from the
        // session; that is expected, not a failure.
        reply.text = _stopRequested
            ? 'Stopped.'
            : 'Sorry, I could not produce an answer. Please try again.';
      }
    }
    _pending.clear();
    if (error != null && !_stopRequested) {
      debugPrint('Assistant reply failed: $error');
    }
    _busy = false;
    _stopRequested = false;
    _notify();
  }

  Future<void> _discardEngine() async {
    final engine = _engine;
    _engine = null;
    _session = null;
    try {
      await engine?.dispose();
    } catch (_) {
      // The load already failed; nothing more to clean up.
    }
  }

  void _setStatus(AssistantStatus value) {
    status = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    final engine = _engine;
    if (engine != null) {
      engine.cancelGeneration();
      unawaited(_generation?.cancel());
      unawaited(engine.dispose());
    }
    super.dispose();
  }
}
