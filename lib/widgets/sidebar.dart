import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/strings.dart';
import '../models/models.dart';
import '../pages/profile_page.dart';
import '../services/export_service.dart';
import '../state/chat_store.dart';
import '../theme.dart';
import 'dialogs/additional_workspaces_dialog.dart';
import 'dialogs/conv_menu.dart';
import 'dialogs/main_menu.dart';

/// 侧边栏（2026-08-27 重写）。
///
/// 设计要点：
/// - 整个列表包在 `AnimatedBuilder(store)` 里，激活高亮每次 build 都从
///   `store.activeId` 计算，不做任何本地状态缓存（修复“激活状态不对”）。
/// - 主区按对话活跃时间分组（今天/昨天/7天/30天/更早），组内与跨组
///   均可拖拽排序；视觉索引与数据索引通过 [_VisualItem] 统一映射。
/// - 置顶与文件夹区独立在上方，功能与旧版一致。
class Sidebar extends StatefulWidget {
  const Sidebar({
    super.key,
    this.accent,
    this.showInspectorButton = false,
    this.onToggleInspector,
  });

  final Color? accent;

  /// 窄屏下显示“打开右侧面板”的开关按钮。
  final bool showInspectorButton;
  final VoidCallback? onToggleInspector;

  @override
  State<Sidebar> createState() => _SidebarState();
}

/// 主区时间分组。
enum _ConvGroup { today, yesterday, week, month, older }

extension on _ConvGroup {
  String get label => switch (this) {
        _ConvGroup.today => I18n.t('sidebar.section.today'),
        _ConvGroup.yesterday => I18n.t('sidebar.section.yesterday'),
        _ConvGroup.week => I18n.t('sidebar.section.7d'),
        _ConvGroup.month => I18n.t('sidebar.section.30d'),
        _ConvGroup.older => I18n.t('sidebar.section.older'),
      };
}

/// 主区视觉条目：节头或对话行；对话行携带其在 `topLevel` 中的索引。
class _VisualItem {
  const _VisualItem.header(this.group)
      : conv = null,
        topIndex = null;
  const _VisualItem.conv(this.conv, this.topIndex) : group = null;

  final _ConvGroup? group;
  final Conversation? conv;
  final int? topIndex;

  bool get isHeader => conv == null;
}

class _SidebarState extends State<Sidebar> {
  Color get _accent => widget.accent ?? AppColors.primary;

  bool _itemRightClickClaimed = false;

  void _claimItemRightClick() {
    _itemRightClickClaimed = true;
  }

  @override
  Widget build(BuildContext context) {
    final store = AppState.chatOf(context);
    return Container(
      width: 236,
      color: AppColors.sidebar,
      child: SafeArea(
        right: false,
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons != kSecondaryButton) return;

            _itemRightClickClaimed = false;

            // 等待子项的 PointerDown / SecondaryTapDown 先声明右键归属，
            // 避免空白区域菜单和条目菜单同时弹出。
            Future.delayed(const Duration(milliseconds: 80), () {
              if (mounted && !_itemRightClickClaimed) {
                _showAreaMenu(context, event.position, store);
              }
            });
          },
          child: AnimatedBuilder(
            animation: store,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                const SizedBox(height: 10),
                _buildNewChatButton(store),
                const SizedBox(height: 12),
                Expanded(child: _buildList(store)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- 头部

  Widget _buildHeader(BuildContext context) {
    final settings = AppState.settingsOf(context);
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Material(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: BorderSide(color: AppColors.border),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfilePage(),
                      ),
                    ),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              settings.userInitial,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              settings.userName,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _SquareIconButton(
              icon: Icons.search,
              tooltip: I18n.t('search.title'),
              onTap: () => _showSearchDialog(context, AppState.chatOf(context)),
            ),
            const SizedBox(width: 4),
            if (widget.showInspectorButton) ...[
              _SquareIconButton(
                icon: Icons.dashboard_customize_outlined,
                tooltip: 'Inspector',
                onTap: widget.onToggleInspector ?? () {},
              ),
              const SizedBox(width: 4),
            ],
            Builder(
              builder: (buttonContext) => _SquareIconButton(
                icon: Icons.menu,
                tooltip: I18n.t('sidebar.menu'),
                onTap: () => showMainMenu(buttonContext, Offset.zero),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewChatButton(ChatStore store) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          store.activate(null);
        },
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 18, color: _accent),
              const SizedBox(width: 7),
              Text(
                I18n.t('sidebar.new_chat'),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- 列表

  static _ConvGroup _groupOf(Conversation c, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(
      c.updatedAt.year,
      c.updatedAt.month,
      c.updatedAt.day,
    );
    final diff = today.difference(day).inDays;
    if (diff <= 0) return _ConvGroup.today;
    if (diff == 1) return _ConvGroup.yesterday;
    if (diff <= 7) return _ConvGroup.week;
    if (diff <= 30) return _ConvGroup.month;
    return _ConvGroup.older;
  }

  Widget _buildList(ChatStore store) {
    final pinned = store.pinned;
    final folders = store.folders;
    final topLevel = store.topLevel;

    // 主区：按活跃时间分组，生成视觉条目（节头 + 对话行）。
    final byGroup = <_ConvGroup, List<Conversation>>{};
    final topIndexById = <String, int>{};
    final now = DateTime.now();
    for (var i = 0; i < topLevel.length; i++) {
      topIndexById[topLevel[i].id] = i;
      byGroup.putIfAbsent(_groupOf(topLevel[i], now), () => []).add(topLevel[i]);
    }
    final visual = <_VisualItem>[];
    for (final g in _ConvGroup.values) {
      final list = byGroup[g];
      if (list == null || list.isEmpty) continue;
      visual.add(_VisualItem.header(g));
      for (final c in list) {
        visual.add(_VisualItem.conv(c, topIndexById[c.id]));
      }
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          sliver: SliverMainAxisGroup(slivers: [
            // ---- 置顶区 ----
            if (pinned.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: _SectionHeader(labelKey: 'sidebar.section.pinned'),
              ),
              for (final c in pinned)
                SliverToBoxAdapter(
                  child: _ConvRow(
                    key: ValueKey('pin_${c.id}'),
                    conv: c,
                    accent: _accent,
                    isActive: store.activeId == c.id,
                    onTap: () => store.activate(c.id),
                    onMenu: (offset) => _showConvMenu(context, c, offset),
                    onClaimRightClick: _claimItemRightClick,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
            ],
            // ---- 文件夹区 ----
            for (final f in folders) ...[
              SliverToBoxAdapter(
                child: _FolderHeader(
                  folder: f,
                  accent: _accent,
                  onTap: () => store.toggleFolder(f.id),
                  onMenu: (offset) => _showFolderMenu(context, f, offset),
                  onClaimRightClick: _claimItemRightClick,
                ),
              ),
              if (f.expanded)
                for (final c in store.inFolder(f.id))
                  SliverToBoxAdapter(
                    child: _ConvRow(
                      key: ValueKey('fld_${c.id}'),
                      conv: c,
                      accent: _accent,
                      isActive: store.activeId == c.id,
                      onTap: () => store.activate(c.id),
                      onMenu: (offset) => _showConvMenu(context, c, offset),
                      onClaimRightClick: _claimItemRightClick,
                      indent: true,
                    ),
                  ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
            ],
          ]),
        ),
        // ---- 主区（时间分组 + 拖拽排序）----
        if (visual.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverReorderableList(
              itemCount: visual.length,
              onReorder: (oldV, newV) =>
                  _onReorder(store, visual, oldV, newV),
              itemBuilder: (context, vi) {
                final item = visual[vi];
                if (item.isHeader) {
                  return _SectionHeader(
                    key: ValueKey('sec_${item.group!.name}'),
                    labelKey: _sectionKey(item.group!),
                  );
                }
                final c = item.conv!;
                return _ConvRow(
                  key: ValueKey('top_${c.id}'),
                  conv: c,
                  accent: _accent,
                  isActive: store.activeId == c.id,
                  onTap: () => store.activate(c.id),
                  onMenu: (offset) => _showConvMenu(context, c, offset),
                  onClaimRightClick: _claimItemRightClick,
                  reorderIndex: vi,
                );
              },
            ),
          ),
        if (topLevel.isEmpty && pinned.isEmpty && folders.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  '还没有对话，点击上方「+ 新建对话」开始',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static String _sectionKey(_ConvGroup g) => switch (g) {
        _ConvGroup.today => 'sidebar.section.today',
        _ConvGroup.yesterday => 'sidebar.section.yesterday',
        _ConvGroup.week => 'sidebar.section.7d',
        _ConvGroup.month => 'sidebar.section.30d',
        _ConvGroup.older => 'sidebar.section.older',
      };

  /// 视觉索引 → topLevel 数据索引 → 全局重排。
  /// 节头不可拖；落到节头上时归入该节第一个对话（插入其前）。
  void _onReorder(
    ChatStore store,
    List<_VisualItem> visual,
    int oldV,
    int newV,
  ) {
    if (oldV < 0 || oldV >= visual.length) return;
    final oldItem = visual[oldV];
    if (oldItem.conv == null) return; // 节头不可拖
    final oldTop = oldItem.topIndex!;

    var target = newV;
    if (target > oldV) target -= 1; // ReorderableList 的插入语义
    target = target.clamp(0, visual.length - 1);

    final newItem = visual[target];
    int newTop;
    if (newItem.conv != null) {
      newTop = newItem.topIndex!;
    } else {
      // 目标是节头：落到该节第一个对话前；若该节为空则保持原位。
      newTop = oldTop;
      for (final v in visual.skip(target + 1)) {
        if (v.isHeader) break;
        newTop = v.topIndex!;
        break;
      }
    }
    if (oldTop == newTop) return;
    store.reorderTopLevel(oldTop, newTop);
  }

  // ------------------------------------------------------------ 菜单/对话框

  Future<void> _showAreaMenu(
    BuildContext context,
    Offset position,
    ChatStore store,
  ) async {
    final result = await showMenu<int>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
      items: [
        PopupMenuItem(
          value: 1,
          child: _MenuRow(
            icon: Icons.add,
            label: I18n.t('sidebar.new_chat'),
          ),
        ),
        PopupMenuItem(
          value: 2,
          child: _MenuRow(
            icon: Icons.create_new_folder_outlined,
            label: I18n.t('sidebar.folder.new'),
          ),
        ),
      ],
    );

    if (!mounted) return;

    if (result == 1) {
      // 等 PopupMenu 路由彻底关闭后再修改状态
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;

      store.activate(null);
    } else if (result == 2) {
      // 不要在 PopupMenu 刚 pop 的同一帧里 showDialog
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!mounted) return;

      await _newFolderDialog(context, store);
    }
  }

  Future<void> _newFolderDialog(BuildContext context, ChatStore store) async {
    final controller = TextEditingController();

    try {
      final name = await showDialog<String>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            I18n.t('sidebar.folder.new'),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            cursorColor: _accent,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: I18n.t('sidebar.folder.name'),
              hintStyle: TextStyle(color: AppColors.textTertiary),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _accent),
              ),
            ),
            onSubmitted: (value) {
              Navigator.of(ctx, rootNavigator: true).pop(value.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx, rootNavigator: true).pop();
              },
              child: Text(
                I18n.t('dialog.cancel'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(
                  ctx,
                  rootNavigator: true,
                ).pop(controller.text.trim());
              },
              child: Text(
                I18n.t('dialog.create'),
                style: TextStyle(color: _accent),
              ),
            ),
          ],
        ),
      );

      if (!mounted) return;

      final folderName = name?.trim();
      if (folderName == null || folderName.isEmpty) return;

      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!mounted) return;

      store.addFolder(folderName);
    } finally {
      controller.dispose();
    }
  }

  void _showConvMenu(BuildContext context, Conversation c, Offset offset) {
    final store = AppState.chatOf(context);
    showConvMenu(
      context: context,
      position: offset,
      conv: c,
      folders: store.folders,
      onMoveToFolder: (folderId) => store.moveToFolder(c.id, folderId),
      onRename: () => _renameDialog(context, c),
      onTogglePin: () => store.togglePin(c.id),
      onToggleUnread: () => store.toggleUnread(c.id),
      onDelete: () => _deleteDialog(context, c),
      onExport: () => _exportConversation(context, c),
      onExportJsonl: () => ExportService.exportConversationJsonl(context, c),
      onExportHtml: () => ExportService.exportConversationHtml(context, c),
      onTags: () => _editTagsDialog(context, c),
      onAdditionalWorkspaces: () =>
          showAdditionalWorkspacesDialog(context, store, c.id),
    );
  }

  /// B12：编辑对话标签（逗号分隔）。
  Future<void> _editTagsDialog(BuildContext context, Conversation c) async {
    final store = AppState.chatOf(context);
    final controller = TextEditingController(text: c.tags.join(', '));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('conv.tags'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: I18n.t('conv.tags_hint'),
            hintStyle: TextStyle(color: AppColors.textTertiary),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary),
            ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(
              I18n.t('dialog.save'),
              style: TextStyle(color: _accent),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    store.setTags(
      c.id,
      result
          .split(RegExp(r'[,，]'))
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
    );
  }

  Future<void> _exportConversation(
    BuildContext context,
    Conversation c,
  ) async {
    await ExportService.exportConversation(context, c);
  }

  Future<void> _showSearchDialog(
    BuildContext context,
    ChatStore store,
  ) async {
    final controller = TextEditingController();
    // B07：过滤状态（日期 + 标签）。
    var range = 0; // 0=全部 1=今天 2=7天 3=30天
    String? tagFilter;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final since = switch (range) {
            1 => DateTime.now().subtract(const Duration(days: 1)),
            2 => DateTime.now().subtract(const Duration(days: 7)),
            3 => DateTime.now().subtract(const Duration(days: 30)),
            _ => null,
          };
          final results = store.searchMessages(
            controller.text,
            since: since,
            tag: tagFilter,
          );
          final allTags = store.allTags;
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: I18n.t('search.hint'),
                hintStyle: TextStyle(color: AppColors.textTertiary),
                prefixIcon: Icon(
                  Icons.search,
                  color: AppColors.textSecondary,
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primary),
                ),
              ),
              onChanged: (_) => setLocal(() {}),
              onSubmitted: (_) {
                if (results.isNotEmpty) {
                  store.activate(results.first.$1.id);
                  Navigator.pop(ctx);
                }
              },
            ),
            content: SizedBox(
              width: 440,
              height: 380,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // B07：日期范围过滤。
                  Wrap(
                    spacing: 5,
                    children: [
                      for (final (v, label) in [
                        (0, I18n.t('search.range.all')),
                        (1, I18n.t('search.range.today')),
                        (2, I18n.t('search.range.7d')),
                        (3, I18n.t('search.range.30d')),
                      ])
                        ChoiceChip(
                          label: Text(
                            label,
                            style: TextStyle(
                              color: range == v
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontSize: 10.5,
                            ),
                          ),
                          selected: range == v,
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.surfaceAlt,
                          visualDensity: VisualDensity.compact,
                          side: BorderSide(color: AppColors.border),
                          onSelected: (_) => setLocal(() => range = v),
                        ),
                      if (allTags.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: tagFilter,
                            isDense: true,
                            dropdownColor: AppColors.surfaceAlt,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                            ),
                            hint: Text(
                              I18n.t('search.tag_all'),
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 11,
                              ),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('全部标签'),
                              ),
                              for (final t in allTags)
                                DropdownMenuItem<String?>(
                                  value: t,
                                  child: Text(t),
                                ),
                            ],
                            onChanged: (v) => setLocal(() => tagFilter = v),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: results.isEmpty
                        ? Center(
                            child: Text(
                              controller.text.trim().isEmpty
                                  ? I18n.t('search.empty')
                                  : I18n.t('search.no_result'),
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: results.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              color: AppColors.border,
                            ),
                            itemBuilder: (ctx, i) {
                              final (c, m) = results[i];
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.chat_bubble_outline,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                                title: Text(
                                  c.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: _HighlightText(
                                  text: m.text.trim(),
                                  query: controller.text.trim(),
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                onTap: () {
                                  store.activate(c.id);
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showFolderMenu(
    BuildContext context,
    Folder f,
    Offset position,
  ) async {
    final result = await showMenu<int>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
      items: [
        PopupMenuItem(
          value: 1,
          child: _MenuRow(
            icon: Icons.edit_outlined,
            label: I18n.t('sidebar.menu.rename'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 2,
          child: _MenuRow(
            icon: Icons.delete_outline,
            label: I18n.t('sidebar.folder.delete'),
            danger: true,
          ),
        ),
      ],
    );

    if (!mounted) return;

    if (result == 1) {
      _renameFolderDialog(context, f);
    } else if (result == 2) {
      _deleteFolderDialog(context, f);
    }
  }

  Future<void> _renameFolderDialog(BuildContext context, Folder f) async {
    final store = AppState.chatOf(context);
    final controller = TextEditingController(text: f.name);

    try {
      final newName = await showDialog<String>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            I18n.t('sidebar.folder.rename'),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            cursorColor: _accent,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _accent),
              ),
            ),
            onSubmitted: (value) {
              Navigator.of(ctx, rootNavigator: true).pop(value.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx, rootNavigator: true).pop();
              },
              child: Text(
                I18n.t('dialog.cancel'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(
                  ctx,
                  rootNavigator: true,
                ).pop(controller.text.trim());
              },
              child: Text(
                I18n.t('dialog.save'),
                style: TextStyle(color: _accent),
              ),
            ),
          ],
        ),
      );

      if (!mounted) return;

      final name = newName?.trim();
      if (name == null || name.isEmpty) return;

      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;

      store.renameFolder(f.id, name);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deleteFolderDialog(BuildContext context, Folder f) async {
    final store = AppState.chatOf(context);
    final inFolder = store.conversations
        .where((c) => c.folderId == f.id)
        .length;

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('sidebar.folder.delete'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        content: Text(
          I18n.t('sidebar.folder.delete_body', {
            'name': f.name,
            'count': '$inFolder',
          }),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx, rootNavigator: true).pop(false);
            },
            child: Text(
              I18n.t('dialog.cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx, rootNavigator: true).pop(true);
            },
            child: Text(
              I18n.t('sidebar.menu.delete'),
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (ok == true) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;

      store.deleteFolder(f.id);
    }
  }

  Future<void> _renameDialog(BuildContext context, Conversation c) async {
    final controller = TextEditingController(text: c.title);
    try {
      final newName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            I18n.t('dialog.rename.title'),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            cursorColor: _accent,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: I18n.t('dialog.rename.hint'),
              hintStyle: TextStyle(color: AppColors.textTertiary),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _accent),
              ),
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
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(
                I18n.t('dialog.confirm'),
                style: TextStyle(color: _accent),
              ),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (newName != null && newName.trim().isNotEmpty) {
        AppState.chatOf(context).rename(c.id, newName);
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deleteDialog(BuildContext context, Conversation c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('dialog.delete.title'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        content: Text(
          I18n.t('dialog.delete.body', {'name': c.title}),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              I18n.t('dialog.cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              I18n.t('sidebar.menu.delete'),
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (ok == true) {
      AppState.chatOf(context).delete(c.id);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({super.key, required this.labelKey});

  final String labelKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Text(
        I18n.t(labelKey),
        style: TextStyle(
          color: AppColors.textTertiary,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ConvRow extends StatefulWidget {
  const _ConvRow({
    super.key,
    required this.conv,
    required this.accent,
    required this.isActive,
    required this.onTap,
    required this.onMenu,
    required this.onClaimRightClick,
    this.indent = false,
    this.reorderIndex,
  });

  final Conversation conv;
  final Color accent;
  final bool isActive;
  final VoidCallback onTap;
  final void Function(Offset globalPosition) onMenu;
  final VoidCallback onClaimRightClick;
  final bool indent;
  final int? reorderIndex;

  @override
  State<_ConvRow> createState() => _ConvRowState();
}

class _ConvRowState extends State<_ConvRow> {
  bool _hovered = false;

  // 延迟到下一帧再 setState：鼠标事件处理中同步重建 MouseRegion
  // 会触发 Flutter debug 断言（MouseTracker._debugDuringDeviceUpdate）。
  void _setHovered(bool value) {
    if (_hovered == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hovered == value) return;
      setState(() => _hovered = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final conv = widget.conv;
    final accent = widget.accent;
    final isActive = widget.isActive;
    final hovered = _hovered;

    Widget content = Padding(
      padding: EdgeInsets.only(
        bottom: 1,
        left: widget.indent ? 14 : 0,
      ),
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryButton) {
            widget.onClaimRightClick();
          }
        },
        child: MouseRegion(
          onEnter: (_) => _setHovered(true),
          onExit: (_) => _setHovered(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onSecondaryTapDown: (details) {
              widget.onClaimRightClick();
              widget.onMenu(details.globalPosition);
            },
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                gradient: isActive
                    ? LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          accent.withValues(alpha: 0.26),
                          accent.withValues(alpha: 0.07),
                        ],
                      )
                    : null,
                color: isActive
                    ? null
                    : (hovered ? AppColors.hover : Colors.transparent),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (conv.unread)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      conv.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: conv.unread
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (conv.pinned)
                    Icon(Icons.push_pin, size: 14, color: accent)
                  else if (hovered)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        final box =
                            context.findRenderObject() as RenderBox?;
                        if (box != null) {
                          final pos =
                              box.localToGlobal(Offset.zero) +
                              const Offset(208, 26);
                          widget.onMenu(pos);
                        }
                      },
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.more_horiz,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.reorderIndex != null) {
      // 立即拖拽，桌面端不需要长按。
      content = ReorderableDragStartListener(
        index: widget.reorderIndex!,
        child: content,
      );
    }

    return content;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _FolderHeader extends StatelessWidget {
  const _FolderHeader({
    super.key,
    required this.folder,
    required this.accent,
    required this.onTap,
    required this.onMenu,
    required this.onClaimRightClick,
  });

  final Folder folder;
  final Color accent;
  final VoidCallback onTap;
  final void Function(Offset globalPosition) onMenu;
  final VoidCallback onClaimRightClick;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == kSecondaryButton) {
          onClaimRightClick();
        }
      },
      child: MouseRegion(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onSecondaryTapDown: (details) {
            onClaimRightClick();
            onMenu(details.globalPosition);
          },
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  folder.expanded
                      ? Icons.arrow_drop_down
                      : Icons.arrow_right,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.folder_outlined,
                  size: 14,
                  color: accent.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.redAccent : AppColors.textPrimary;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 13),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// B07：搜索结果预览——匹配关键词高亮。
class _HighlightText extends StatelessWidget {
  const _HighlightText({
    required this.text,
    required this.query,
    required this.style,
  });

  final String text;
  final String query;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty) {
      return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: style);
    }
    final lower = text.toLowerCase();
    final ql = q.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final idx = lower.indexOf(ql, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + q.length),
          style: TextStyle(
            backgroundColor: AppColors.primary.withValues(alpha: 0.25),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      start = idx + q.length;
    }
    return Text.rich(
      TextSpan(children: spans, style: style),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          child: Icon(icon, size: 17, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}