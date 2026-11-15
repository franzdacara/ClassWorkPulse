import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../ai/assistant_controller.dart';
import '../data/app_database.dart';
import '../models/daily_entry.dart';
import '../models/student_profile.dart';

/// Writes, shows and shares the parent update for one day's entry.
///
/// The text can be edited before sending; edits are saved with the entry.
class ParentUpdateScreen extends StatefulWidget {
  const ParentUpdateScreen({
    super.key,
    required this.assistant,
    required this.database,
    required this.studentId,
    required this.profile,
    required this.date,
  });

  final AssistantController assistant;
  final AppDatabase database;
  final int studentId;
  final StudentProfile profile;
  final DateTime date;

  @override
  State<ParentUpdateScreen> createState() => _ParentUpdateScreenState();
}

class _ParentUpdateScreenState extends State<ParentUpdateScreen> {
  final _text = TextEditingController();
  DailyEntry? _entry;
  bool _loaded = false;
  bool _writing = false;
  bool _edited = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (_writing) widget.assistant.stop();
    _saveEdits();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final entry = await widget.database.entryFor(widget.date, widget.studentId);
    if (!mounted) return;
    setState(() {
      _entry = entry;
      _loaded = true;
      _text.text = entry?.parentUpdate ?? '';
    });
    // Write one straight away the first time, so a single tap gets a message.
    if (entry != null && entry.parentUpdate == null) _write();
  }

  Future<void> _write() async {
    final entry = _entry;
    if (entry == null || _writing) return;
    setState(() {
      _writing = true;
      _error = null;
    });
    try {
      final text = await widget.assistant.writeParentUpdate(
        entry,
        studentId: widget.studentId,
      );
      if (!mounted) return;
      setState(() {
        _text.text = text;
        _edited = false;
      });
    } on ParentUpdateCancelled {
      // Stopped by the user; keep whatever was there before.
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _describe(error));
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  String _describe(Object error) => switch (error) {
    StateError(:final message) => message,
    _ => 'The update could not be written. Please try again.',
  };

  void _saveEdits() {
    if (_edited && _text.text.trim().isNotEmpty) {
      widget.database.saveParentUpdate(
        widget.date,
        _text.text.trim(),
        widget.studentId,
      );
      _edited = false;
    }
  }

  Future<void> _copy() async {
    _saveEdits();
    await Clipboard.setData(ClipboardData(text: _text.text.trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied. Paste it into your message.')),
    );
  }

  Future<void> _share() async {
    _saveEdits();
    await SharePlus.instance.share(
      ShareParams(
        text: _text.text.trim(),
        subject: "${widget.profile.studentName}'s classwork update",
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = _text.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent update'),
        actions: [
          if (hasText && !_writing)
            IconButton(
              tooltip: 'Write again',
              icon: const Icon(Icons.refresh),
              onPressed: _write,
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _entry == null
          ? const Center(child: Text('This entry no longer exists.'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    "${widget.profile.studentName}'s update for "
                    '${DateFormat.yMMMEd().format(widget.date)}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                Expanded(
                  child: _writing
                      ? _Writing(onStop: widget.assistant.stop)
                      : !hasText
                      ? Center(
                          child: FilledButton.icon(
                            onPressed: _write,
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('Write parent update'),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(16),
                          child: TextField(
                            controller: _text,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              helperText:
                                  'Check and edit before sending. Written on '
                                  'this device by AI from your notes.',
                              helperMaxLines: 2,
                            ),
                            onChanged: (_) => setState(() => _edited = true),
                          ),
                        ),
                ),
                if (hasText && !_writing)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _copy,
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _share,
                              icon: const Icon(Icons.send),
                              label: const Text('Send'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Writing extends StatelessWidget {
  const _Writing({required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('Writing the update...', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'This takes a few seconds on most phones, longer the first '
              'time while the AI model loads.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: onStop, child: const Text('Stop')),
          ],
        ),
      ),
    );
  }
}

/// Opens the parent update for the entry on [date].
void openParentUpdate(
  BuildContext context, {
  required AssistantController assistant,
  required AppDatabase database,
  required int studentId,
  required StudentProfile profile,
  required DateTime date,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ParentUpdateScreen(
        assistant: assistant,
        database: database,
        studentId: studentId,
        profile: profile,
        date: date,
      ),
    ),
  );
}
