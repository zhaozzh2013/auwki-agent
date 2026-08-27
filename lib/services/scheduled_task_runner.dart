import 'package:flutter/foundation.dart';

import '../i18n/strings.dart';
import '../models/models.dart';
import '../state/chat_store.dart';
import '../widgets/thinking_slider.dart';
import '../work_mode.dart';
import 'ai_providers.dart';
import 'prompts.dart';
import 'scheduled_task_service.dart';
import 'settings_store.dart';

/// A13：到点执行定时任务的头部运行器（无 UI，直接走 AI 流式对话）。
class ScheduledTaskRunner {
  ScheduledTaskRunner._();

  static Future<void> run(
    ScheduledTask task,
    ChatStore store,
    SettingsStore settings,
  ) async {
    if (settings.apiKey.isEmpty) return;
    var conv = store.conversations
        .where((c) => c.id == task.conversationId)
        .toList();
    if (conv.isEmpty) {
      final id = store.newConversation();
      store.rename(id, '⏰ ${task.prompt}');
      store.activate(id);
      conv = store.conversations.where((c) => c.id == id).toList();
    }
    if (conv.isEmpty) return;
    final c = conv.first;

    final userMsg = Message(
      id: 'm_${DateTime.now().microsecondsSinceEpoch}_sched',
      sender: Sender.user,
      text: '⏰ ${task.prompt}',
    );
    store.addMessage(c.id, userMsg);
    final placeholderId =
        'm_${DateTime.now().microsecondsSinceEpoch}_sched_a';
    store.addMessage(
      c.id,
      Message(
        id: placeholderId,
        sender: Sender.assistant,
        text: I18n.t('chat.connecting'),
      ),
    );

    final history = <Map<String, dynamic>>[];
    for (final m in c.messages) {
      if (m.id == placeholderId) continue;
      if (m.sender == Sender.system || m.sender == Sender.tool) continue;
      history.add({
        'role': m.sender == Sender.user ? 'user' : 'assistant',
        'content': m.text,
      });
    }

    final system = Prompts.build(
      mode: WorkMode.work,
      thinking: ThinkingLevel.thinking,
      costMode: settings.costMode,
      preset: settings.preset,
      workspaceDir: c.workspaceDir,
    );
    try {
      final client = settings.client;
      final buf = StringBuffer();
      await for (final chunk in client.chatStream(
        ChatRequest(
          system: system,
          messages: history,
          model: settings.model,
          maxTokens: 1200,
          temperature: settings.temperatureFor(settings.model) ??
              settings.presetTemperature,
        ),
      )) {
        buf.write(chunk);
        store.updateMessage(c.id, placeholderId, buf.toString());
      }
    } catch (e) {
      debugPrint('scheduled task error: $e');
      store.updateMessage(c.id, placeholderId, '${I18n.t('chat.error')} $e');
    }
  }
}
