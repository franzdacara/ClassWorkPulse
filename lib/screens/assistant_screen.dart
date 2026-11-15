import 'package:material_ui/material_ui.dart';

import '../ai/assistant_controller.dart';
import '../ai/progress_context.dart';
import '../data/app_database.dart';
import '../models/student_profile.dart';

/// Chat with the on-device model about the student's saved entries.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({
    super.key,
    required this.controller,
    required this.database,
    required this.profile,
    required this.studentId,
  });

  final AssistantController controller;
  final AppDatabase database;
  final StudentProfile profile;
  final int studentId;

  String get studentName => profile.studentName;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  bool _hasEntries = true;

  AssistantController get _assistant => widget.controller;

  String get _summaryPrompt => ProgressContext.summaryRequest(widget.profile);

  @override
  void initState() {
    super.initState();
    widget.database.addListener(_checkEntries);
    _checkEntries();
  }

  @override
  void dispose() {
    widget.database.removeListener(_checkEntries);
    _input.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AssistantScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentId != widget.studentId) _checkEntries();
  }

  Future<void> _checkEntries() async {
    final entries = await widget.database.entries(widget.studentId);
    if (!mounted) return;
    setState(() => _hasEntries = entries.isNotEmpty);
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty || _assistant.isBusy) return;
    _input.clear();
    _assistant.send(text);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _assistant,
      builder: (context, _) => switch (_assistant.status) {
        AssistantStatus.ready => _buildChat(context),
        AssistantStatus.idle ||
        AssistantStatus.preparingModel ||
        AssistantStatus.loadingModel => _buildLoading(context),
        AssistantStatus.modelMissing => const _Notice(
          icon: Icons.extension_off_outlined,
          title: 'AI model not included',
          message:
              'This build of the app does not contain the on-device model. '
              'Add a .gguf file to assets/models/ (run "dart run '
              'tool/fetch_model.dart") and rebuild the app.',
        ),
        AssistantStatus.unsupported => _Notice(
          icon: Icons.phonelink_off_outlined,
          title: 'Assistant unavailable',
          message:
              _assistant.errorMessage ??
              'The assistant is not available on this device.',
        ),
        AssistantStatus.failed => _Notice(
          icon: Icons.error_outline,
          title: 'The assistant could not start',
          message:
              '${_assistant.errorMessage ?? 'Unknown error.'}\n\nThe model '
              'needs about 1 GB of free storage and memory.',
          action: FilledButton.tonal(
            onPressed: _assistant.start,
            child: const Text('Try again'),
          ),
        ),
      },
    );
  }

  Widget _buildLoading(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _assistant.installProgress;
    final copying =
        _assistant.status == AssistantStatus.preparingModel && progress != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              copying ? 'Setting up the assistant' : 'Starting the assistant',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              copying
                  ? 'Unpacking the AI model. This only happens the first '
                        'time and can take a minute.'
                  : 'Loading the AI model on this device.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            LinearProgressIndicator(value: copying ? progress : null),
            if (copying) ...[
              const SizedBox(height: 8),
              Text(
                '${(progress * 100).round()}%',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChat(BuildContext context) {
    final name = widget.studentName;
    final messages = _assistant.messages;
    final busy = _assistant.isBusy;

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? _EmptyChat(
                  studentName: name,
                  hasEntries: _hasEntries,
                  onSummarize: () => _assistant.send(_summaryPrompt),
                )
              : SelectionArea(
                  child: ListView.builder(
                    // Reversed so the view stays pinned to the newest text
                    // while a reply streams in.
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) => _MessageBubble(
                      message: messages[messages.length - 1 - index],
                    ),
                  ),
                ),
        ),
        if (!busy && messages.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final (label, prompt) in [
                  ('Summarize progress', _summaryPrompt),
                  (
                    'What to focus on next',
                    'Based on the records, what should we focus on next to '
                        'help $name improve?',
                  ),
                  (
                    'Recent highlights',
                    "What are the highlights from $name's most recent "
                        'entries?',
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(label),
                      onPressed: () => _assistant.send(prompt),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: "Ask about $name's progress",
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              if (busy)
                IconButton.filledTonal(
                  tooltip: 'Stop',
                  icon: const Icon(Icons.stop),
                  onPressed: _assistant.stop,
                )
              else
                IconButton.filled(
                  tooltip: 'Send',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: _send,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({
    required this.studentName,
    required this.hasEntries,
    required this.onSummarize,
  });

  final String studentName;
  final bool hasEntries;
  final VoidCallback onSummarize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.auto_awesome,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              "Ask about $studentName's progress",
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'The assistant reads the entries saved on this device and '
              'answers without an internet connection. It can make mistakes, '
              'so check important details against the History tab.',
              textAlign: TextAlign.center,
              style: muted,
            ),
            const SizedBox(height: 24),
            if (hasEntries)
              FilledButton.icon(
                onPressed: onSummarize,
                icon: const Icon(Icons.summarize_outlined),
                label: const Text('Generate progress summary'),
              )
            else
              Text(
                'There are no entries yet. Save one in the Today tab so the '
                'assistant has something to work from.',
                textAlign: TextAlign.center,
                style: muted,
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fromUser = message.fromUser;
    final foreground = fromUser ? scheme.onPrimaryContainer : scheme.onSurface;
    final waiting = message.isStreaming && message.text.isEmpty;

    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: fromUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: waiting
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Reading the records...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            : Text(
                fromUser ? message.text : _plainText(message.text),
                style: theme.textTheme.bodyLarge?.copyWith(color: foreground),
              ),
      ),
    );
  }
}

/// Small models sometimes answer in Markdown despite being asked not to.
/// This removes the most common markers so replies read as plain text.
String _plainText(String text) => text
    .replaceAll(RegExp(r'\*\*|__'), '')
    .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
    .replaceAllMapped(
      RegExp(r'^(\s*)[*-]\s+', multiLine: true),
      (match) => '${match[1]}• ',
    );

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}
