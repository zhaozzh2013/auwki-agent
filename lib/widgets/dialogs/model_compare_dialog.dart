import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/strings.dart';
import '../../services/ai_providers.dart';
import '../../theme.dart';

/// G08：同一问题让多个模型分别回答，并排对比。
class ModelCompareDialog extends StatefulWidget {
  const ModelCompareDialog({super.key, this.initialPrompt = ''});

  final String initialPrompt;

  @override
  State<ModelCompareDialog> createState() => _ModelCompareDialogState();
}

class _ModelCompareDialogState extends State<ModelCompareDialog> {
  late final TextEditingController _prompt;
  final Set<String> _selected = {};
  bool _running = false;
  final Map<String, String> _results = {};

  @override
  void initState() {
    super.initState();
    _prompt = TextEditingController(text: widget.initialPrompt);
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final settings = AppState.settingsOf(context);
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty || _selected.isEmpty || _running) return;
    setState(() {
      _running = true;
      _results.clear();
    });
    final client = settings.client;
    for (final modelId in _selected) {
      if (!mounted) return;
      setState(() => _results[modelId] = '');
      try {
        final buf = StringBuffer();
        await for (final chunk in client.chatStream(
          ChatRequest(
            system: I18n.t('compare.system'),
            messages: [
              {'role': 'user', 'content': prompt},
            ],
            model: modelId,
            maxTokens: 1200,
            temperature: 0.7,
          ),
        )) {
          if (!mounted) return;
          buf.write(chunk);
          setState(() => _results[modelId] = buf.toString());
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _results[modelId] = '${I18n.t('compare.error')} $e');
      }
    }
    if (!mounted) return;
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppState.settingsOf(context);
    final models = settings.provider.models;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      title: Text(
        I18n.t('compare.title'),
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SizedBox(
        width: 640,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _prompt,
              maxLines: 2,
              minLines: 1,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: I18n.t('compare.prompt_hint'),
                hintStyle: TextStyle(color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final m in models)
                  FilterChip(
                    label: Text(
                      m.label,
                      style: TextStyle(
                        color: _selected.contains(m.id)
                            ? Colors.white
                            : AppColors.textPrimary,
                        fontSize: 11.5,
                      ),
                    ),
                    selected: _selected.contains(m.id),
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceAlt,
                    side: BorderSide(color: AppColors.border),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _selected.add(m.id);
                      } else {
                        _selected.remove(m.id);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _results.isEmpty && !_running
                  ? Center(
                      child: Text(
                        I18n.t('compare.empty'),
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final m in models)
                          if (_results.containsKey(m.id)) ...[
                            _resultCard(m, _results[m.id] ?? ''),
                            const SizedBox(height: 8),
                          ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            I18n.t('git.close'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        FilledButton(
          onPressed: _running || _selected.isEmpty ? null : _run,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: Text(
            _running ? I18n.t('compare.running') : I18n.t('compare.run'),
          ),
        ),
      ],
    );
  }

  Widget _resultCard(ModelOption m, String text) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m.label,
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            text,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
