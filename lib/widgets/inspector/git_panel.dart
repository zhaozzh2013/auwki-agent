import 'dart:io';

import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../services/git_service.dart';
import '../../theme.dart';
import '../dialogs/git_dialogs.dart';

/// 右侧面板：Git（提交 / 回退 / 状态 / 历史），带使用引导。
class GitPanel extends StatefulWidget {
  const GitPanel({super.key, required this.accent, this.workspacePath});

  final Color accent;

  /// 本次 Git 操作的工作目录；为 null 时使用应用启动目录。
  final String? workspacePath;

  @override
  State<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends State<GitPanel> {
  GitStatus? _status;
  List<GitCommitInfo> _commits = const [];
  String? _error;
  bool _busy = false;
  bool _showLog = false;
  bool _showGuide = true;
  bool _isRepo = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final root = await GitService.repoRoot(path: widget.workspacePath);
      if (!mounted) return;
      if (root == null) {
        final hasGit = await GitService.gitAvailable();
        if (!mounted) return;
        if (!hasGit) {
          setState(() => _error = I18n.t('git.unavailable'));
          return;
        }
        setState(() {
          _isRepo = false;
          _status = null;
          _commits = const [];
        });
        return;
      }
      final status = await GitService.status(path: widget.workspacePath);
      final commits = await GitService.log(
        count: 15,
        path: widget.workspacePath,
      );
      if (!mounted) return;
      setState(() {
        _isRepo = true;
        _status = status;
        _commits = commits;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text, style: const TextStyle(fontSize: 13)),
          backgroundColor: error
              ? Colors.redAccent.shade700
              : AppColors.surfaceAlt,
        ),
      );
  }

  Future<void> _run(Future<String> Function() op, String okText) async {
    setState(() => _busy = true);
    try {
      final out = await op();
      if (out.isNotEmpty && !out.contains('nothing to commit')) _snack(out);
      await _refresh();
      if (okText.isNotEmpty) _snack(okText);
    } catch (e) {
      _snack('${I18n.t('git.error')}: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleStage(GitFileStatus f) async {
    if (f.untracked) {
      await _run(
        () => GitService.stage([f.path], path: widget.workspacePath),
        '',
      );
      return;
    }
    if (f.staged) {
      await _run(
        () => GitService.unstage([f.path], path: widget.workspacePath),
        '',
      );
    } else {
      await _run(
        () => GitService.stage([f.path], path: widget.workspacePath),
        '',
      );
    }
  }

  Future<void> _stageAll() => _run(
    () => GitService.stageAll(path: widget.workspacePath),
    I18n.t('git.staged_done'),
  );

  Future<void> _commit() async {
    final stagedCount =
        _status?.files.where((f) => f.staged || f.untracked).length ?? 0;
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('git.commit.title'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                I18n.t('git.commit.staged_hint', {'count': '$stagedCount'}),
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: I18n.t('git.commit.hint'),
                  hintStyle: TextStyle(color: AppColors.textTertiary),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
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
              I18n.t('git.cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(
              I18n.t('git.commit'),
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (message == null || message.isEmpty) return;
    await _run(
      () => GitService.commit(message, path: widget.workspacePath),
      I18n.t('git.commit.done'),
    );
  }

  Future<bool> _confirm(String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('git.confirm.title'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        content: Text(
          body,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              I18n.t('git.cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              I18n.t('git.confirm.ok'),
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _discardFile(GitFileStatus f) async {
    final body = f.untracked
        ? I18n.t('git.delete.confirm', {'path': f.path})
        : I18n.t('git.discard.confirm', {'path': f.path});
    if (!await _confirm(body)) return;
    await _run(
      () => f.untracked
          ? GitService.removeUntracked(
              [f.path],
              path: widget.workspacePath,
            )
          : GitService.discard([f.path], path: widget.workspacePath),
      '',
    );
  }

  Future<void> _discardAll() async {
    if (!await _confirm(I18n.t('git.discard_all.confirm'))) return;
    await _run(
      () => GitService.discardAll(path: widget.workspacePath),
      '',
    );
  }

  Future<void> _revertCommit(GitCommitInfo c) async {
    if (!await _confirm(I18n.t('git.revert.confirm', {'hash': c.shortHash}))) {
      return;
    }
    await _run(
      () => GitService.revertCommit(c.hash, path: widget.workspacePath),
      I18n.t('git.revert.done'),
    );
  }

  Future<void> _showDiffStat(GitFileStatus f) async {
    try {
      final text = await GitService.fileDiff(
        f.path,
        path: widget.workspacePath,
      );
      if (!mounted) return;
      await showDiffViewerDialog(
        context,
        title: '${I18n.t('git.diff_stat')}: ${f.path}',
        diff: text,
      );
    } catch (e) {
      _snack('${I18n.t('git.error')}: $e', error: true);
    }
  }

  Future<void> _branches() async {
    await showBranchesDialog(
      context,
      workspacePath: widget.workspacePath,
      onChanged: _refresh,
    );
  }

  Future<void> _graph() async {
    await showGraphDialog(context, workspacePath: widget.workspacePath);
  }

  Future<void> _stats() async {
    await showStatsDialog(context, workspacePath: widget.workspacePath);
  }

  Future<void> _conflicts() async {
    await showConflictDialog(
      context,
      workspacePath: widget.workspacePath,
      onChanged: _refresh,
    );
  }

  Future<void> _gitignore() async {
    await showGitignoreDialog(
      context,
      workspacePath: widget.workspacePath,
    );
  }

  Future<void> _sync(String op) async {
    await _run(
      () => switch (op) {
        'pull' => GitService.pull(path: widget.workspacePath),
        'push' => GitService.push(path: widget.workspacePath),
        _ => GitService.fetch(path: widget.workspacePath),
      },
      I18n.t('git.sync.done', {'op': op}),
    );
  }

  Future<void> _initRepo() async {
    final path = widget.workspacePath ?? Directory.current.path;
    setState(() => _busy = true);
    try {
      await GitService.initRepo(path);
      GitService.resetRepoRootCache();
      final root = await GitService.repoRoot(path: path);
      if (root == null) {
        _snack(
          '${I18n.t('git.error')}: ${I18n.t('git.init.failed')}',
          error: true,
        );
        return;
      }
      _snack(I18n.t('git.init.done'));
      await _refresh();
    } catch (e) {
      _snack('${I18n.t('git.error')}: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _ErrorState(onRetry: _refresh);
    }

    if (!_isRepo && !_busy) {
      return _NoRepoState(
        path: widget.workspacePath ?? Directory.current.path,
        onInit: _initRepo,
        onRefresh: _refresh,
      );
    }

    final status = _status;
    if (status == null && !_busy) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final files = status?.files ?? const <GitFileStatus>[];
    final stagedCount = files.where((f) => f.staged || f.untracked).length;
    final trackedCount = files.where((f) => !f.untracked).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        _HeaderRow(
          branch: status?.branch ?? 'git',
          aheadBehind: status?.aheadBehind ?? '',
          accent: widget.accent,
          onRefresh: _busy ? null : _refresh,
        ),
        if (_showGuide) ...[
          const SizedBox(height: 8),
          _GuideCard(
            onClose: () => setState(() => _showGuide = false),
          ),
        ],
        const SizedBox(height: 8),
        _SummaryRow(
          changes: files.length,
          staged: stagedCount,
          accent: widget.accent,
        ),
        const SizedBox(height: 6),
        const _LegendRow(),
        const SizedBox(height: 8),
        Expanded(
          child: files.isEmpty
              ? _EmptyState()
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: files.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, i) => _FileRow(
                    file: files[i],
                    accent: widget.accent,
                    onToggle: _busy ? null : () => _toggleStage(files[i]),
                    onDiscard: _busy ? null : () => _discardFile(files[i]),
                    onStat: _busy ? null : () => _showDiffStat(files[i]),
                  ),
                ),
        ),
        const SizedBox(height: 8),
        _ActionBar(
          stagedCount: stagedCount,
          trackedCount: trackedCount,
          accent: widget.accent,
          busy: _busy,
          onStageAll: _stageAll,
          onCommit: _commit,
          onRevertMenu: () => _showRevertMenu(),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _MiniButton(
              icon: Icons.account_tree_outlined,
              label: I18n.t('git.branches'),
              color: widget.accent,
              onTap: _busy ? null : _branches,
            ),
            _MiniButton(
              icon: Icons.merge_type,
              label: I18n.t('git.graph'),
              color: widget.accent,
              onTap: _busy ? null : _graph,
            ),
            _MiniButton(
              icon: Icons.bar_chart,
              label: I18n.t('git.stats'),
              color: widget.accent,
              onTap: _busy ? null : _stats,
            ),
            _MiniButton(
              icon: Icons.error_outline,
              label: I18n.t('git.conflict.title'),
              color: Colors.redAccent,
              onTap: _busy ? null : _conflicts,
            ),
            _MiniButton(
              icon: Icons.note_add_outlined,
              label: '.gitignore',
              color: widget.accent,
              onTap: _busy ? null : _gitignore,
            ),
            _MiniButton(
              icon: Icons.download,
              label: I18n.t('git.pull'),
              color: widget.accent,
              onTap: _busy ? null : () => _sync('pull'),
            ),
            _MiniButton(
              icon: Icons.upload,
              label: I18n.t('git.push'),
              color: widget.accent,
              onTap: _busy ? null : () => _sync('push'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => setState(() => _showLog = !_showLog),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Icon(
                  _showLog ? Icons.expand_less : Icons.expand_more,
                  size: 15,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  I18n.t('git.log'),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showLog)
          Flexible(
            flex: 2,
            child: _commits.isEmpty
                ? Center(
                    child: Text(
                      I18n.t('git.no_changes'),
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11.5,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _commits.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _CommitRow(
                      commit: _commits[i],
                      accent: widget.accent,
                      onRevert: _busy ? null : () => _revertCommit(_commits[i]),
                    ),
                  ),
          ),
      ],
    );
  }

  Future<void> _showRevertMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.restore,
                color: Colors.redAccent,
              ),
              title: Text(
                I18n.t('git.discard_all'),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
              subtitle: Text(
                I18n.t('git.discard_all.desc'),
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'discard_all'),
            ),
            ListTile(
              leading: Icon(Icons.undo, color: Colors.redAccent),
              title: Text(
                I18n.t('git.revert_last'),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
              subtitle: Text(
                I18n.t('git.revert_last.desc'),
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'revert_last'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'discard_all') {
      await _discardAll();
    } else if (action == 'revert_last' && _commits.isNotEmpty) {
      await _revertCommit(_commits.first);
    }
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.branch,
    required this.aheadBehind,
    required this.accent,
    required this.onRefresh,
  });

  final String branch;
  final String aheadBehind;
  final Color accent;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.alt_route, size: 13, color: accent),
              const SizedBox(width: 4),
              Text(
                branch,
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (aheadBehind.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              aheadBehind,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 10.5,
              ),
            ),
          ),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: onRefresh,
          icon: Icon(Icons.refresh, size: 15, color: AppColors.textSecondary),
          tooltip: I18n.t('git.refresh'),
        ),
      ],
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.help_outline,
            size: 15,
            color: AppColors.primary,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  I18n.t('git.guide.title'),
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  I18n.t('git.guide.body'),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
            icon: Icon(
              Icons.close,
              size: 14,
              color: AppColors.textTertiary,
            ),
            tooltip: I18n.t('git.guide.close'),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.changes,
    required this.staged,
    required this.accent,
  });

  final int changes;
  final int staged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          I18n.t('git.summary', {
            'changes': '$changes',
            'staged': '$staged',
          }),
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow();

  @override
  Widget build(BuildContext context) {
    final items = [
      (I18n.t('git.legend.modified'), const Color(0xFF42A5F5)),
      (I18n.t('git.legend.added'), const Color(0xFF66BB6A)),
      (I18n.t('git.legend.deleted'), Colors.redAccent),
      (I18n.t('git.legend.untracked'), Colors.orangeAccent),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 3,
      children: [
        for (final (label, color) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.task_alt,
            size: 26,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 8),
          Text(
            I18n.t('git.no_changes'),
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            I18n.t('git.empty_hint'),
            style: TextStyle(color: AppColors.textTertiary, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.stagedCount,
    required this.trackedCount,
    required this.accent,
    required this.busy,
    required this.onStageAll,
    required this.onCommit,
    required this.onRevertMenu,
  });

  final int stagedCount;
  final int trackedCount;
  final Color accent;
  final bool busy;
  final VoidCallback onStageAll;
  final VoidCallback onCommit;
  final VoidCallback onRevertMenu;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MiniButton(
            icon: Icons.add_to_queue_outlined,
            label: I18n.t('git.stage_all'),
            color: accent,
            onTap: busy ? null : onStageAll,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _MiniButton(
            icon: Icons.commit_outlined,
            label: I18n.t('git.commit.with_count', {'count': '$stagedCount'}),
            color: accent,
            filled: true,
            onTap: busy ? null : onCommit,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _MiniButton(
            icon: Icons.undo,
            label: I18n.t('git.revert_menu'),
            color: Colors.redAccent,
            onTap: busy ? null : onRevertMenu,
          ),
        ),
      ],
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: filled
          ? (enabled ? color : AppColors.surfaceAlt)
          : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: filled
                  ? (enabled ? color : AppColors.border)
                  : color.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: enabled
                    ? (filled ? Colors.white : color)
                    : AppColors.textTertiary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled
                        ? (filled ? Colors.white : AppColors.textPrimary)
                        : AppColors.textTertiary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.accent,
    required this.onToggle,
    required this.onDiscard,
    required this.onStat,
  });

  final GitFileStatus file;
  final Color accent;
  final VoidCallback? onToggle;
  final VoidCallback? onDiscard;
  final VoidCallback? onStat;

  ({String label, Color color}) get _badge {
    final s = file.label;
    if (s.contains('A')) return (label: I18n.t('git.legend.added'), color: const Color(0xFF66BB6A));
    if (s.contains('D')) return (label: I18n.t('git.legend.deleted'), color: Colors.redAccent);
    if (s.contains('R')) return (label: 'R', color: const Color(0xFFAB47BC));
    if (s.contains('U')) return (label: 'U', color: Colors.redAccent);
    if (file.untracked) return (label: I18n.t('git.legend.untracked'), color: Colors.orangeAccent);
    return (label: I18n.t('git.legend.modified'), color: const Color(0xFF42A5F5));
  }

  @override
  Widget build(BuildContext context) {
    final staged = file.staged;
    final badge = _badge;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
      decoration: BoxDecoration(
        color: staged ? accent.withValues(alpha: 0.08) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                staged ? Icons.check_box : Icons.check_box_outline_blank,
                size: 16,
                color: staged ? accent : AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: badge.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              badge.label,
              style: TextStyle(
                color: badge.color,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              file.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onStat,
            icon: Icon(
              Icons.bar_chart,
              size: 14,
              color: AppColors.textSecondary,
            ),
            tooltip: I18n.t('git.diff_stat'),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDiscard,
            icon: Icon(Icons.restore, size: 14, color: Colors.redAccent),
            tooltip: file.untracked
                ? I18n.t('git.delete_file')
                : I18n.t('git.discard_file'),
          ),
        ],
      ),
    );
  }
}

class _CommitRow extends StatelessWidget {
  const _CommitRow({
    required this.commit,
    required this.accent,
    required this.onRevert,
  });

  final GitCommitInfo commit;
  final Color accent;
  final VoidCallback? onRevert;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(Icons.circle, size: 7, color: accent),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  commit.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${commit.shortHash} · ${commit.date} · ${commit.author}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onRevert,
            icon: Icon(Icons.undo, size: 14, color: accent),
            tooltip: I18n.t('git.revert_commit'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 28),
            const SizedBox(height: 10),
            Text(
              I18n.t('git.no_repo'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(
                I18n.t('git.refresh'),
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoRepoState extends StatelessWidget {
  const _NoRepoState({
    required this.path,
    required this.onInit,
    required this.onRefresh,
  });

  final String path;
  final VoidCallback onInit;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined, color: AppColors.textSecondary, size: 30),
            const SizedBox(height: 10),
            Text(
              I18n.t('git.init.title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              I18n.t('git.init.body'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                path,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onInit,
              icon: const Icon(Icons.create_new_folder_outlined, size: 16),
              label: Text(
                I18n.t('git.init.action'),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 15),
              label: Text(
                I18n.t('git.refresh'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
