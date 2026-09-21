import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core.dart';

class WearSitesPage extends StatefulWidget {
  const WearSitesPage({super.key});

  @override
  State<WearSitesPage> createState() => _WearSitesPageState();
}

class _WearSitesPageState extends State<WearSitesPage> {
  static const _blue = Color(0xFF0095FF);
  final _search = TextEditingController();
  String? _selected;
  bool _selectionInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = WearScope.of(context);
    if (!_selectionInitialized) {
      _selected = session.siteId;
      _selectionInitialized = true;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _enter(WearSession session, String id) async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await session.selectSite(id);
      if (mounted) context.go('/workbench');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _logout(WearSession session) async {
    try {
      await session.logout();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = WearScope.of(context);
    final sites = session.sites;
    final selected = sites.where((site) => idOf(site['id']) == _selected);
    final selectedSite = selected.isEmpty ? null : selected.first;
    final query = _search.text.trim().toLowerCase();
    final visible = sites
        .where(
          (site) =>
              textOf(site['name']).toLowerCase().contains(query) ||
              textOf(site['siteCode'], '').toLowerCase().contains(query),
        )
        .toList();
    return Scaffold(
      backgroundColor: WearColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey('sites-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  left: session.siteId == null ? 16 : 0,
                  right: 16,
                ),
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      if (session.siteId != null)
                        IconButton(
                          tooltip: '返回工作台',
                          onPressed: session.busy
                              ? null
                              : () => context.go('/workbench'),
                          icon: const Icon(Icons.arrow_back_ios_new, size: 22),
                        ),
                      const WearRollingWordmark(height: 22),
                    ],
                  ),
                ),
              ),
              _hero(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const ValueKey('sites-search'),
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '搜索已授权厂站',
                        hintStyle: const TextStyle(
                          color: WearColors.muted,
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: WearColors.muted,
                        ),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清空搜索',
                                onPressed: () => setState(_search.clear),
                                icon: const Icon(Icons.close, size: 20),
                              ),
                        filled: true,
                        fillColor: const Color(0xFFF7FAFF),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 14,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFD8E6F8),
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (session.error != null) ...[
                      Text(
                        session.error!,
                        style: const TextStyle(color: WearColors.danger),
                      ),
                      const SizedBox(height: 12),
                    ],
                    WearCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (sites.isEmpty)
                            const WearEmpty(
                              title: '暂无可访问的厂站',
                              detail: '请联系管理员为此账号分配有效厂站。',
                            )
                          else if (visible.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Text(
                                '未找到匹配厂站，请尝试其他名称或编码。',
                                style: TextStyle(color: WearColors.muted),
                              ),
                            ),
                          for (final site in visible) ...[
                            _siteRow(site, session.busy),
                            const Divider(height: 1, color: Color(0xFFE5EDF7)),
                          ],
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDF7FF),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFD6EAFE),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.verified_user_outlined,
                                  color: Color(0xFF5988B5),
                                  size: 22,
                                ),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '只展示当前账号有权访问的厂站。',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.4,
                                      color: Color(0xFF5988B5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey('sites-enter'),
                      onPressed: session.busy || selectedSite == null
                          ? null
                          : () => _enter(session, idOf(selectedSite['id'])),
                      style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        minimumSize: const Size.fromHeight(48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: session.busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              selectedSite == null
                                  ? '请选择工作厂站'
                                  : '进入${textOf(selectedSite['name'])}',
                              textAlign: TextAlign.center,
                            ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      key: const ValueKey('sites-logout'),
                      onPressed: session.busy ? null : () => _logout(session),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _blue,
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: Color(0xFF9FD0FF)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('退出当前账号'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero() => SizedBox(
    height: WearHeaderLayout.height(context),
    child: Stack(
      fit: StackFit.expand,
      children: [
        const WearAssetImage(
          'assets/field-brand/preview/work_reference_header.png',
          fit: BoxFit.cover,
          alignment: Alignment.bottomRight,
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '账号与访问',
                  style: TextStyle(fontSize: 10, color: WearColors.brand),
                ),
                const SizedBox(height: 6),
                const Text(
                  '选择工作厂站',
                  style: TextStyle(
                    fontSize: WearHeaderLayout.titleSize,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: WearColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '选定厂站后，查看对应现场与设备',
                  style: TextStyle(
                    fontSize: WearHeaderLayout.subtitleSize,
                    height: 1.35,
                    color: WearColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _siteRow(JsonMap site, bool busy) {
    final id = idOf(site['id']);
    final checked = id == _selected;
    final code = textOf(site['siteCode'], '');
    return Semantics(
      selected: checked,
      button: true,
      child: InkWell(
        key: ValueKey('site-$id'),
        onTap: busy ? null : () => setState(() => _selected = id),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.business_outlined,
                  size: 24,
                  color: _blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      textOf(site['name']),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: WearColors.ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${code.isEmpty ? '' : '$code · '}当前可访问',
                      style: const TextStyle(
                        fontSize: 12,
                        color: WearColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (checked)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5F8F2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '已选择',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF00A88A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.radio_button_unchecked,
                  size: 18,
                  color: WearColors.muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
