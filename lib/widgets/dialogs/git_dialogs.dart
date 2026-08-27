import 'dart:io';

import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/strings.dart';
import '../../services/ai_providers.dart';
import '../../services/git_service.dart';
import '../../theme.dart';

String _fmtGitError(Object e) => '$e';

/// D01：分支管理。
Future<void> showBranchesDialog(
  BuildContext context, {
  required String? workspacePath,
  required VoidCallback onChanged,
}) async {
  final path = workspacePath;
  final current = await GitService.status(path: path);
  final branches = await GitService.branches(path: path);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final name = TextEditingController();
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            I18n.t('git.branches'),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
          content: SizedBox(
            width: 380,
            height: 320,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: name,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: I18n.t('git.branch.new'),
                          hintStyle: TextStyle(color: AppColors.textTertiary),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.add, color: AppColors.primary),
                      onPressed: () async {
                        final n = name.text.trim();
                        if (n.isEmpty) return;
                        try {
                          await GitService.createBranch(n, path: path);
                          setLocal(() {});
                          onChanged();
                          name.clear();
                        } catch (e) {
                          if (!ctx.mounted) return;
                          _snack(ctx, _fmtGitError(e), error: true);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: branches.length,
                    itemBuilder: (context, i) {
                      final b = branches[i];
                      final active = b == current.branch;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          active ? Icons.alt_route : Icons.call_split,
                          size: 16,
                          color: active
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        title: Text(
                          b,
                          style: TextStyle(
                            color: active
                                ? AppColors.primary
                                : AppColors.textPrimary,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                        trailing: active
                            ? null
                            : IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () async {
                                  try {
                                    await GitService.deleteBranch(b, path: path);
                                    setLocal(() {});
                                    onChanged();
                                  } catch (e) {
                                    if (!ctx.mounted) return;
                                    _snack(ctx, _fmtGitError(e), error: true);
                                  }
                                },
                              ),
                        onTap: active
                            ? null
                            : () async {
                                try {
                                  await GitService.switchBranch(b, path: path);
                                  onChanged();
                                  if (!ctx.mounted) return;
                                  Navigator.pop(ctx);
                                } catch (e) {
                                  if (!ctx.mounted) return;
                                  _snack(ctx, _fmtGitError(e), error: true);
                                }
                              },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                I18n.t('dialog.cancel'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// D02：行级 diff 查看器。
Future<void> showDiffViewerDialog(
  BuildContext context, {
  required String title,
  required String diff,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        title,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
      ),
      content: SizedBox(
        width: 640,
        height: 420,
        child: diff.trim().isEmpty
            ? Center(
                child: Text(
                  I18n.t('git.no_changes'),
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12.5,
                  ),
                ),
              )
            : SingleChildScrollView(
                child: SelectableText(
                  diff,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            I18n.t('git.close'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    ),
  );
}

/// D03：冲突解决助手（AI 分析 + 应用建议）。
Future<void> showConflictDialog(
  BuildContext context, {
  required String? workspacePath,
  required VoidCallback onChanged,
}) async {
  final path = workspacePath;
  final conflicts = await GitService.conflictedFiles(path: path);
  if (!context.mounted) return;
  if (conflicts.isEmpty) {
    _snack(context, I18n.t('git.conflict.none'));
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        I18n.t('git.conflict.title'),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 520,
        height: 360,
        child: ListView.builder(
          itemCount: conflicts.length,
          itemBuilder: (context, i) => ListTile(
            dense: true,
            leading: Icon(Icons.error_outline, color: Colors.redAccent),
            title: Text(
              conflicts[i],
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontFamily: 'monospace',
              ),
            ),
            trailing: IconButton(
              icon: Icon(Icons.auto_fix_high, color: AppColors.primary),
              tooltip: I18n.t('git.conflict.analyze'),
              onPressed: () async {
                Navigator.pop(ctx);
                await _analyzeConflict(context, path!, conflicts[i], onChanged);
              },
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            I18n.t('git.close'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    ),
  );
}

Future<void> _analyzeConflict(
  BuildContext context,
  String workspacePath,
  String file,
  VoidCallback onChanged,
) async {
  final settings = AppState.settingsOf(context);
  final full = file.startsWith('/') || file.contains(':')
      ? file
      : '$workspacePath/${file.replaceAll('\\', '/')}';
  final f = File(full);
  if (!await f.exists()) {
    if (!context.mounted) return;
    _snack(context, I18n.t('git.conflict.read_failed'), error: true);
    return;
  }
  final content = await f.readAsString();
  String? resolved;
  final future = () async {
    final client = settings.client;
    final buf = StringBuffer();
    await for (final chunk in client.chatStream(
      ChatRequest(
        system:
            'You are a merge conflict resolver. Read the conflict markers '
            '(<<<<<<<, =======, >>>>>>>) and return ONLY the resolved file '
            'content without markers and without commentary.',
        messages: [
          {'role': 'user', 'content': content},
        ],
        model: settings.model,
        maxTokens: 8000,
      ),
    )) {
      buf.write(chunk);
    }
    return buf.toString();
  }();
  if (!context.mounted) return;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        I18n.t('git.conflict.analyzing'),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
      ),
      content: SizedBox(
        width: 600,
        height: 420,
        child: FutureBuilder<String>(
          future: future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            if (snap.hasError) {
              return Center(
                child: Text(
                  '${snap.error}',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              );
            }
            resolved = snap.data ?? '';
            return SingleChildScrollView(
              child: SelectableText(
                snap.data ?? '',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            I18n.t('dialog.cancel'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, resolved ?? ''),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: Text(I18n.t('git.conflict.apply')),
        ),
      ],
    ),
  );
  if (result == null || result.trim().isEmpty) return;
  if (!context.mounted) return;
  // 防数据丢失：输出仍含冲突标记或为空时拒绝覆盖原文件。
  if (result.contains('<<<<<<<') ||
      result.contains('>>>>>>>')) {
    _snack(context, I18n.t('git.conflict.incomplete'), error: true);
    return;
  }
  await f.writeAsString(result);
  onChanged();
}

/// D04：提交历史图。
Future<void> showGraphDialog(
  BuildContext context, {
  required String? workspacePath,
}) async {
  final graph = await GitService.graph(path: workspacePath);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        I18n.t('git.graph'),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 640,
        height: 420,
        child: SingleChildScrollView(
          child: SelectableText(
            graph,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.4,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            I18n.t('git.close'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    ),
  );
}

/// D05：提交统计。
Future<void> showStatsDialog(
  BuildContext context, {
  required String? workspacePath,
}) async {
  final authors = await GitService.authorStats(path: workspacePath);
  final daily = await GitService.dailyStats(path: workspacePath);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        I18n.t('git.stats'),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              I18n.t('git.stats.by_author'),
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                itemCount: authors.length,
                itemBuilder: (context, i) {
                  final e = authors.entries.elementAt(i);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${e.value}\t${e.key}',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                },
              ),
            ),
            Divider(color: AppColors.border),
            Text(
              I18n.t('git.stats.by_day'),
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                itemCount: daily.length,
                itemBuilder: (context, i) {
                  final e = daily.entries.elementAt(i);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${e.key}\t${e.value}',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            I18n.t('git.close'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    ),
  );
}

/// D08：单文件历史与版本 diff。
Future<void> showFileHistoryDialog(
  BuildContext context, {
  required String? workspacePath,
  required String file,
}) async {
  final log = await GitService.fileLog(file, path: workspacePath);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        '$file · ${I18n.t('git.file_history')}',
        style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
      ),
      content: SizedBox(
        width: 560,
        height: 360,
        child: log.trim().isEmpty
            ? Center(
                child: Text(
                  I18n.t('git.no_changes'),
                  style: TextStyle(color: AppColors.textTertiary),
                ),
              )
            : ListView.builder(
                itemCount: log.split('\n').length,
                itemBuilder: (context, i) {
                  final line = log.split('\n')[i];
                  final hash = line.split(' ').first;
                  return ListTile(
                    dense: true,
                    title: Text(
                      line,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    trailing: hash.length >= 7
                        ? IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.difference,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            onPressed: () async {
                              try {
                                final diff = await GitService.fileDiffBetween(
                                  file,
                                  '$hash^',
                                  hash,
                                  path: workspacePath,
                                );
                                if (!context.mounted) return;
                                await showDiffViewerDialog(
                                  context,
                                  title: '$file @ $hash',
                                  diff: diff,
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                _snack(context, _fmtGitError(e), error: true);
                              }
                            },
                          )
                        : null,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            I18n.t('git.close'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    ),
  );
}

/// D09：.gitignore 编辑器（含模板）。
Future<void> showGitignoreDialog(
  BuildContext context, {
  required String? workspacePath,
}) async {
  final initial = await GitService.readGitignore(path: workspacePath);
  if (!context.mounted) return;
  final controller = TextEditingController(text: initial);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        '.gitignore',
        style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 520,
        height: 360,
        child: Column(
          children: [
            Wrap(
              spacing: 6,
              children: [
                for (final t in const ['Flutter', 'Dart', 'Node', 'Python'])
                  ActionChip(
                    label: Text(t),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      controller.text =
                          '${controller.text.trimRight()}\n${_template(t)}\n';
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            I18n.t('dialog.cancel'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        FilledButton(
          onPressed: () async {
            try {
              await GitService.writeGitignore(
                controller.text,
                path: workspacePath,
              );
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              if (!ctx.mounted) return;
              _snack(ctx, _fmtGitError(e), error: true);
            }
          },
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: Text(I18n.t('dialog.save')),
        ),
      ],
    ),
  );
}

String _template(String name) => switch (name) {
  'Flutter' => '# Flutter\n.dart_tool/\nbuild/\n.flutter-plugins\n.pub-cache/',
  'Dart' => '# Dart\n.dart_tool/\n.packages\npubspec.lock',
  'Node' => '# Node\nnode_modules/\ndist/\n*.log',
  'Python' => '# Python\n__pycache__/\n*.pyc\n.venv/\nvenv/',
  _ => '',
};

void _snack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(fontSize: 12)),
        backgroundColor: error
            ? Colors.redAccent.shade700
            : AppColors.surfaceAlt,
      ),
    );
}
