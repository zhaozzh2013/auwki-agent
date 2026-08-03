import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../services/git_service.dart';
import '../../theme.dart';

/// 右侧面板：Git（提交 / 回退 / 状态 / 历史）。
class GitPanel extends StatefulWidget {
  const GitPanel({super.key, required this.accent});

  final Color accent;

  @override
  State<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends State<GitPanel> {
  GitStatus? _status;
  List<GitCommitInfo> _commits = const [];
  String? _error;
  bool _busy = false;
  bool _showLog = false;

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
      final status = await GitService.status();
      final commits = await GitService.log(count: 15);
      if (!mounted) return;
      setState(() {
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
      if (out.isNotEmpty) _snack(out);
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
      await _run(() => GitService.stage([f.path]), '');
      return;
    }
    if (f.staged) {
      await _run(() => GitService.unstage([f.path]), '');
    } else {
      await _run(() => GitService.stage([f.path]), '');
    }
  }

  Future<void> _stageAll() =>
      _run(() => GitService.stageAll(), I18n.t('git.staged_done'));

  Future<void> _commit() async {
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
          child: TextField(
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
    await _run(() => GitService.commit(message), I18n.t('git.commit.done'));
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
          ? GitService.removeUntracked([f.path])
          : GitService.discard([f.path]),
      '',
    );
  }

  Future<void> _discardAll() async {
    if (!await _confirm(I18n.t('git.discard_all.confirm'))) return;
    await _run(() => GitService.discardAll(), '');
  }

  Future<void> _revertCommit(GitCommitInfo c) async {
    if (!await _confirm(I18n.t('git.revert.confirm', {'hash': c.shortHash}))) {
      return;
    }
    await _run(
      () => GitService.revertCommit(c.hash),
      I18n.t('git.revert.done'),
    );
  }

  Future<void> _showDiffStat(GitFileStatus f) async {
    String text;
    try {
      text = await GitService.diffStat(f.path);
    } catch (e) {
      text = '$e';
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          '${I18n.t('git.diff_stat')}: ${f.path}',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            text,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontFamily: 'monospace',
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

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
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
                onPressed: _refresh,
                icon: Icon(Icons.refresh, size: 16, color: widget.accent),
                label: Text(
                  I18n.t('git.refresh'),
                  style: TextStyle(color: widget.accent, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final status = _status;
    if (status == null && !_busy) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final files = status?.files ?? const <GitFileStatus>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Row(
          children: [
            Icon(Icons.alt_route, size: 16, color: widget.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                status?.branch ?? 'git',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if ((status?.aheadBehind ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  status!.aheadBehind,
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10.5,
                  ),
                ),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: _busy ? null : _refresh,
              icon: Icon(Icons.refresh, size: 15, color: AppColors.textSecondary),
              tooltip: I18n.t('git.refresh'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _ActionChip(
              icon: Icons.add_to_queue_outlined,
              label: I18n.t('git.stage_all'),
              accent: widget.accent,
              onTap: _busy ? null : _stageAll,
            ),
            _ActionChip(
              icon: Icons.commit_outlined,
              label: I18n.t('git.commit'),
              accent: widget.accent,
              onTap: _busy ? null : _commit,
            ),
            _ActionChip(
              icon: Icons.undo,
              label: I18n.t('git.revert_menu'),
              accent: Colors.redAccent,
              onTap: _busy
                  ? null
                  : () => showMenu<String>(
                        context: context,
                        position: RelativeRect.fromLTRB(80, 70, 0, 0),
                        color: AppColors.surfaceAlt,
                        items: [
                          PopupMenuItem(
                            value: 'discard_all',
                            child: Text(
                              I18n.t('git.discard_all'),
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'revert_last',
                            child: Text(
                              I18n.t('git.revert_last'),
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ).then((v) {
                        if (v == 'discard_all') _discardAll();
                        if (v == 'revert_last' && _commits.isNotEmpty) {
                          _revertCommit(_commits.first);
                        }
                      }),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: files.isEmpty
              ? Center(
                  child: Text(
                    I18n.t('git.no_changes'),
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: files.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, i) =>
                      _FileRow(
                        file: files[i],
                        accent: widget.accent,
                        onToggle: _busy ? null : () => _toggleStage(files[i]),
                        onDiscard: _busy ? null : () => _discardFile(files[i]),
                        onStat: _busy ? null : () => _showDiffStat(files[i]),
                      ),
                ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => setState(() => _showLog = !_showLog),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(
                  _showLog
                      ? Icons.expand_less
                      : Icons.expand_more,
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
            child: ListView.separated(
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
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: onTap == null ? AppColors.textTertiary : accent),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: onTap == null
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
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

  @override
  Widget build(BuildContext context) {
    final staged = file.staged;
    final label = file.label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                staged
                    ? Icons.check_box
                    : file.untracked
                    ? Icons.check_box_outline_blank
                    : Icons.check_box_outline_blank,
                size: 16,
                color: staged ? accent : AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 30,
            child: Text(
              label.isEmpty ? '..' : label,
              style: TextStyle(
                color: file.untracked
                    ? Colors.orangeAccent
                    : file.deleted
                    ? Colors.redAccent
                    : accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              file.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onStat,
            icon: Icon(Icons.bar_chart, size: 14, color: AppColors.textSecondary),
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
