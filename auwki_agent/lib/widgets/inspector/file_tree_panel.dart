import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../i18n/strings.dart';
import '../../theme.dart';

/// 右侧面板：工作空间文件树（浏览 / 刷新 / 查看文件内容）。
class FileTreePanel extends StatefulWidget {
  const FileTreePanel({
    super.key,
    required this.workspaceDir,
    required this.accent,
  });

  final String? workspaceDir;
  final Color accent;

  @override
  State<FileTreePanel> createState() => _FileTreePanelState();
}

class _FileNode {
  _FileNode(this.name, this.path, this.isDir, [this.children = const []]);

  final String name;
  final String path;
  final bool isDir;
  final List<_FileNode> children;
}

class _FileTreePanelState extends State<FileTreePanel> {
  List<_FileNode> _roots = const [];
  bool _busy = false;
  String? _error;
  int _total = 0;

  static const Set<String> _skipDirs = {
    '.git',
    '.dart_tool',
    'build',
    'node_modules',
    '.idea',
    '.vscode',
    '.venv',
    'venv',
    'dist',
    'out',
    '__pycache__',
    '.codex',
    '.agents',
    '.vs',
    '.plugin_symlinks',
    'ephemeral',
    'CMakeFiles',
  };
  static const int _maxEntries = 600;
  static const int _maxDepth = 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _roots = const [];
      _total = 0;
    });
    final dir = widget.workspaceDir;
    if (dir == null || dir.trim().isEmpty) {
      setState(() {
        _busy = false;
        _error = I18n.t('filetree.empty');
      });
      return;
    }
    try {
      final roots = await _scan(Directory(dir), 0);
      if (!mounted) return;
      setState(() {
        _roots = roots;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = I18n.t('filetree.error', {'error': '$e'});
      });
    }
  }

  Future<List<_FileNode>> _scan(Directory dir, int depth) async {
    if (depth > _maxDepth || _total >= _maxEntries) return const [];
    final out = <_FileNode>[];
    try {
      await for (final e in dir.list(followLinks: false)) {
        if (_total >= _maxEntries) break;
        final name = e.path.split(Platform.pathSeparator).last;
        if (e is Directory) {
          if (_skipDirs.contains(name)) continue;
          _total++;
          final children = await _scan(e, depth + 1);
          out.add(_FileNode(name, e.path, true, children));
        } else if (e is File) {
          _total++;
          out.add(_FileNode(name, e.path, false));
        }
      }
    } catch (_) {
      // 单个目录失败不影响整体。
    }
    out.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  Future<void> _openFile(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return;
      final stat = await f.stat();
      final ext = path.split('.').last.toLowerCase();
      final isImage = const {
        'png',
        'jpg',
        'jpeg',
        'gif',
        'webp',
        'bmp',
      }.contains(ext);
      final maxBytes = isImage ? 4 * 1024 * 1024 : 1024 * 1024;
      if (stat.size > maxBytes) {
        _snack(I18n.t('filetree.too_large'));
        return;
      }
      if (isImage) {
        final bytes = await f.readAsBytes();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(
              path.split(Platform.pathSeparator).last,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720, maxHeight: 560),
              child: Image.memory(bytes, fit: BoxFit.contain),
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
        return;
      }
      var text = await f.readAsString();
      if (text.length > 500000) {
        text = '${text.substring(0, 500000)}\n…[截断]';
      }
      if (!mounted) return;
      final isMarkdown = const {'md', 'markdown', 'mdown'}.contains(ext);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            path.split(Platform.pathSeparator).last,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: isMarkdown
                  ? MarkdownBody(
                      data: text,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          height: 1.45,
                        ),
                        h1: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                        h2: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                        h3: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        code: TextStyle(
                          color: AppColors.textPrimary,
                          backgroundColor: AppColors.surfaceAlt,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        horizontalRuleDecoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: AppColors.border,
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    )
                  : SelectableText(
                      text,
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
    } catch (_) {
      _snack(I18n.t('filetree.read_failed'));
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text, style: const TextStyle(fontSize: 12)),
          backgroundColor: AppColors.surfaceAlt,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final dir = widget.workspaceDir;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.folder_outlined, size: 15, color: widget.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                dir ?? I18n.t('filetree.no_workspace'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: _busy ? null : _load,
              icon: Icon(
                Icons.refresh,
                size: 14,
                color: AppColors.textSecondary,
              ),
              tooltip: I18n.t('filetree.refresh'),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 6),
        Expanded(
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                )
              : _roots.isEmpty
              ? Center(
                  child: Text(
                    I18n.t('filetree.empty'),
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11.5,
                    ),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final n in _roots) _NodeTile(node: n, onOpen: _openFile),
                    if (_total >= _maxEntries)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          I18n.t('filetree.limit', {'n': '$_maxEntries'}),
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({required this.node, required this.onOpen});

  final _FileNode node;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    if (!node.isDir) {
      return InkWell(
        onTap: () => onOpen(node.path),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: [
              Icon(Icons.insert_drive_file_outlined, size: 13, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ExpansionTile(
      dense: true,
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      childrenPadding: const EdgeInsets.only(left: 14),
      leading: Icon(Icons.folder, size: 14, color: AppColors.planAccent),
      title: Text(
        node.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 11.5),
      ),
      children: [
        for (final c in node.children) _NodeTile(node: c, onOpen: onOpen),
      ],
    );
  }
}
