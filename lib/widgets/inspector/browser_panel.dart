import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../services/browser_service.dart';
import '../../theme.dart';

/// 右侧面板：内置浏览器。
class BrowserPanel extends StatefulWidget {
  const BrowserPanel({super.key, required this.accent});

  final Color accent;

  @override
  State<BrowserPanel> createState() => _BrowserPanelState();
}

class _BrowserPanelState extends State<BrowserPanel> {
  final BrowserService _service = BrowserService.instance;
  BrowserSession? _active;
  BrowserSession? _fullscreen;
  @override
  void initState() {
    super.initState();
    _service.addListener(_onService);
    _init();
  }

  @override
  void dispose() {
    _service.removeListener(_onService);
    super.dispose();
  }

  void _onService() {
    if (!mounted) return;
    setState(() {
      if (_active != null && !_service.sessions.contains(_active)) {
        _active = _service.sessions.isEmpty ? null : _service.sessions.last;
      }
    });
  }

  Future<void> _init() async {
    if (_service.sessions.isEmpty) {
      final s = await _service.createSession();
      if (mounted && s != null) setState(() => _active = s);
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

  Future<void> _newSession() async {
    final s = await _service.createSession();
    if (!mounted) return;
    if (s == null) {
      _snack(I18n.t('browser.create_failed'), error: true);
      return;
    }
    setState(() => _active = s);
  }

  Future<void> _openFullscreen(BrowserSession s) async {
    setState(() => _fullscreen = s);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _FullscreenBrowserPage(
          service: _service,
          session: s,
          accent: widget.accent,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _fullscreen = null);
  }

  Future<void> _importCookies() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'json'],
      dialogTitle: I18n.t('browser.import_cookies'),
    );
    if (res == null || res.files.isEmpty) return;
    final path = res.files.first.path;
    if (path == null) return;
    String content;
    try {
      content = await File(path).readAsString();
    } catch (_) {
      _snack(I18n.t('browser.import_read_failed'), error: true);
      return;
    }
    final cookies = BrowserService.parseCookieFile(content);
    if (cookies.isEmpty) {
      _snack(I18n.t('browser.import_empty'), error: true);
      return;
    }
    final n = _service.importCookies(cookies);
    _snack(I18n.t('browser.import_done', {'count': '$n'}));
  }

  Future<void> _privacyMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cookie_outlined),
              title: Text(
                I18n.t('browser.clear_cookies'),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
              onTap: () => Navigator.pop(ctx, 'cookies'),
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: Text(
                I18n.t('browser.clear_cache'),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
              onTap: () => Navigator.pop(ctx, 'cache'),
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: Text(
                I18n.t('browser.dev_tools'),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
              onTap: () => Navigator.pop(ctx, 'devtools'),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: Text(
                I18n.t('browser.user_agent'),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
              onTap: () => Navigator.pop(ctx, 'useragent'),
            ),
            ListTile(
              leading: const Icon(Icons.zoom_in),
              title: Text(
                I18n.t('browser.zoom'),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
              onTap: () => Navigator.pop(ctx, 'zoom'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final s = _active;
    switch (action) {
      case 'cookies':
        await _service.clearCookies();
        _snack(I18n.t('browser.cookies_cleared'));
      case 'cache':
        await _service.clearCache();
        _snack(I18n.t('browser.cache_cleared'));
      case 'devtools':
        if (s != null) await _service.openDevTools(s);
      case 'useragent':
        await _changeUserAgent(s);
      case 'zoom':
        await _changeZoom(s);
    }
  }

  Future<void> _changeUserAgent(BrowserSession? s) async {
    final controller = TextEditingController();
    final ua = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('browser.user_agent'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        ),
        content: SizedBox(
          width: 320,
          child: TextField(
            controller: controller,
            maxLines: 2,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
            decoration: InputDecoration(
              hintText: I18n.t('browser.user_agent.hint'),
              hintStyle: TextStyle(color: AppColors.textTertiary),
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
              I18n.t('dialog.confirm'),
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (ua == null || ua.isEmpty || s == null) return;
    await _service.setUserAgent(s, ua);
  }

  Future<void> _changeZoom(BrowserSession? s) async {
    if (s == null) return;
    final factor = await showDialog<double>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('browser.zoom'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        ),
        children: [
          for (final (label, value) in [
            ('90%', 0.9),
            ('100%', 1.0),
            ('125%', 1.25),
            ('150%', 1.5),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, value),
              child: Text(
                label,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
            ),
        ],
      ),
    );
    if (factor != null) await _service.setZoom(s, factor);
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _service.sessions;
    if (sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public, size: 30, color: AppColors.textTertiary),
            const SizedBox(height: 10),
            Text(
              I18n.t('browser.empty'),
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            _ActionButton(
              icon: Icons.add,
              label: I18n.t('browser.new_window'),
              accent: widget.accent,
              onTap: _newSession,
            ),
          ],
        ),
      );
    }

    final active = _active ?? sessions.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 30,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final s in sessions)
                _TabChip(
                  session: s,
                  active: s == active,
                  accent: widget.accent,
                  onTap: () => setState(() => _active = s),
                  onClose: () async {
                    await _service.closeSession(s);
                    if (mounted) setState(() {});
                  },
                ),
              InkWell(
                onTap: _newSession,
                child: Container(
                  width: 30,
                  alignment: Alignment.center,
                  child: Icon(Icons.add, size: 15, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _NavButton(
              icon: Icons.arrow_back,
              enabled: active.canGoBack,
              onTap: () => _service.goBack(active),
            ),
            _NavButton(
              icon: Icons.arrow_forward,
              enabled: active.canGoForward,
              onTap: () => _service.goForward(active),
            ),
            _NavButton(
              icon: active.loading ? Icons.close : Icons.refresh,
              enabled: true,
              onTap: () => active.loading
                  ? _service.stop(active)
                  : _service.refresh(active),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _UrlBar(
                key: ValueKey(active.id),
                session: active,
                service: _service,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _ActionButton(
              icon: Icons.open_in_full,
              label: I18n.t('browser.new_window'),
              accent: widget.accent,
              onTap: () => _openFullscreen(active),
            ),
            const SizedBox(width: 6),
            _ActionButton(
              icon: Icons.file_upload_outlined,
              label: I18n.t('browser.import_cookies'),
              accent: widget.accent,
              onTap: _importCookies,
            ),
            const SizedBox(width: 6),
            _ActionButton(
              icon: Icons.privacy_tip_outlined,
              label: I18n.t('browser.privacy'),
              accent: widget.accent,
              onTap: _privacyMenu,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _fullscreen == active
                  ? Center(
                      child: Text(
                        I18n.t('browser.opened_fullscreen'),
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : _WebViewBody(session: active),
            ),
          ),
        ),
        if (active.loadError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              I18n.t('browser.load_error', {'error': active.loadError!}),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.redAccent, fontSize: 10.5),
            ),
          ),
      ],
    );
  }
}

class _WebViewBody extends StatelessWidget {
  const _WebViewBody({required this.session});

  final BrowserSession session;

  @override
  Widget build(BuildContext context) {
    // 全平台统一外部浏览器模式。
    return _ExternalBrowserView(session: session);
  }
}

/// 外部浏览器模式视图：说明 + 在系统浏览器打开。
class _ExternalBrowserView extends StatelessWidget {
  const _ExternalBrowserView({required this.session});

  final BrowserSession session;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_in_browser,
                size: 32, color: AppColors.textSecondary),
            const SizedBox(height: 10),
            Text(
              I18n.t('browser.external_mode'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: session.openExternal,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(
                I18n.t('browser.open_system'),
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UrlBar extends StatefulWidget {
  const _UrlBar({super.key, required this.session, required this.service});

  final BrowserSession session;
  final BrowserService service;

  @override
  State<_UrlBar> createState() => _UrlBarState();
}

class _UrlBarState extends State<_UrlBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.session.url;
    widget.session.addListener(_sync);
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.session.removeListener(_sync);
    _focus.removeListener(_onFocus);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    }
  }

  void _sync() {
    if (!mounted || _focus.hasFocus) return;
    if (_controller.text != widget.session.url) {
      _controller.text = widget.session.url;
    }
  }

  void _go(String raw) {
    _focus.unfocus();
    widget.service.navigate(widget.session, raw);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
      onSubmitted: _go,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        hintText: I18n.t('browser.url_hint'),
        hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 12),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.primary),
        ),
        suffixIcon: IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.arrow_forward, size: 14, color: AppColors.primary),
          onPressed: () => _go(_controller.text),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? onTap : null,
      icon: Icon(
        icon,
        size: 16,
        color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: accent),
                const SizedBox(width: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.session,
    required this.active,
    required this.accent,
    required this.onTap,
    required this.onClose,
  });

  final BrowserSession session;
  final bool active;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final label = session.title.isNotEmpty ? session.title : session.url;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 110,
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.only(left: 8, right: 2),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.14) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? accent.withValues(alpha: 0.6) : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              session.loading
                  ? Icons.hourglass_top
                  : Icons.public,
              size: 12,
              color: active ? accent : AppColors.textTertiary,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label.isEmpty ? I18n.t('browser.new_window') : label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 10.5,
                ),
              ),
            ),
            InkWell(
              onTap: onClose,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 独立全屏浏览器窗口。
class _FullscreenBrowserPage extends StatefulWidget {
  const _FullscreenBrowserPage({
    required this.service,
    required this.session,
    required this.accent,
  });

  final BrowserService service;
  final BrowserSession session;
  final Color accent;

  @override
  State<_FullscreenBrowserPage> createState() =>
      _FullscreenBrowserPageState();
}

class _FullscreenBrowserPageState extends State<_FullscreenBrowserPage> {
  Future<void> _importCookies() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'json'],
      dialogTitle: I18n.t('browser.import_cookies'),
    );
    if (res == null || res.files.isEmpty) return;
    final path = res.files.first.path;
    if (path == null) return;
    String content;
    try {
      content = await File(path).readAsString();
    } catch (_) {
      _fullscreenSnack(I18n.t('browser.import_read_failed'), error: true);
      return;
    }
    final cookies = BrowserService.parseCookieFile(content);
    if (cookies.isEmpty) {
      _fullscreenSnack(I18n.t('browser.import_empty'), error: true);
      return;
    }
    final n = widget.service.importCookies(cookies);
    _fullscreenSnack(I18n.t('browser.import_done', {'count': '$n'}));
  }

  void _fullscreenSnack(String text, {bool error = false}) {
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

  Future<void> _privacy() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cookie_outlined),
              title: Text(
                I18n.t('browser.clear_cookies'),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
              onTap: () => Navigator.pop(ctx, 'cookies'),
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: Text(
                I18n.t('browser.clear_cache'),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
              onTap: () => Navigator.pop(ctx, 'cache'),
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: Text(
                I18n.t('browser.dev_tools'),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
              onTap: () => Navigator.pop(ctx, 'devtools'),
            ),
            ListTile(
              leading: const Icon(Icons.zoom_in),
              title: Text(
                I18n.t('browser.zoom'),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              ),
              onTap: () => Navigator.pop(ctx, 'zoom'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final s = widget.session;
    switch (action) {
      case 'cookies':
        await widget.service.clearCookies();
        _fullscreenSnack(I18n.t('browser.cookies_cleared'));
      case 'cache':
        await widget.service.clearCache();
        _fullscreenSnack(I18n.t('browser.cache_cleared'));
      case 'devtools':
        await widget.service.openDevTools(s);
      case 'zoom':
        final factor = await showDialog<double>(
          context: context,
          builder: (ctx) => SimpleDialog(
            backgroundColor: AppColors.surface,
            title: Text(
              I18n.t('browser.zoom'),
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
            ),
            children: [
              for (final (label, value) in [
                ('90%', 0.9),
                ('100%', 1.0),
                ('125%', 1.25),
                ('150%', 1.5),
              ])
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, value),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        );
        if (factor != null) await widget.service.setZoom(s, factor);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => widget.service.goBack(widget.session),
                    icon: Icon(Icons.arrow_back,
                        color: AppColors.textPrimary, size: 18),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => widget.service.goForward(widget.session),
                    icon: Icon(Icons.arrow_forward,
                        color: AppColors.textPrimary, size: 18),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => widget.service.refresh(widget.session),
                    icon: Icon(Icons.refresh,
                        color: AppColors.textPrimary, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _UrlBar(
                      session: widget.session,
                      service: widget.service,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: _importCookies,
                    icon: Icon(Icons.file_upload_outlined,
                        color: AppColors.textPrimary, size: 18),
                    tooltip: I18n.t('browser.import_cookies'),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: _privacy,
                    icon: Icon(Icons.privacy_tip_outlined,
                        color: AppColors.textPrimary, size: 18),
                    tooltip: I18n.t('browser.privacy'),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close,
                        color: AppColors.textPrimary, size: 18),
                    tooltip: I18n.t('browser.close_window'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: _WebViewBody(session: widget.session),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
