import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/monitored_service.dart';
import '../services/service_manager.dart';
import '../services/app_info_service.dart';

class _Section {
  final String appName;
  final String packageName;
  final List<RunningService> services;
  final bool isMonitoredGroup;

  _Section({
    required this.appName,
    required this.packageName,
    required this.services,
    this.isMonitoredGroup = false,
  });

  int get runningCount => services.where((s) => s.isRunning).length;
}

class ServicePickerScreen extends StatefulWidget {
  final List<MonitoredService> alreadyMonitored;
  final ServiceManager manager;

  const ServicePickerScreen({
    super.key,
    required this.alreadyMonitored,
    required this.manager,
  });

  @override
  State<ServicePickerScreen> createState() => _ServicePickerScreenState();
}

class _ServicePickerScreenState extends State<ServicePickerScreen> {
  final _appInfo = AppInfoService();

  List<RunningService> _allServices = [];
  List<_Section> _sections = [];
  Map<String, Uint8List?> _iconCache = {};

  bool _loading = true;
  String? _error;
  String _query = '';
  bool _filterRunning = false;
  bool _filterAppOwned = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await widget.manager.listAllServices();
      setState(() {
        _allServices = list;
        _buildSections();
        _loading = false;
      });
      _fetchIcons(list);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _fetchIcons(List<RunningService> services) async {
    final prefs = await SharedPreferences.getInstance();
    final packages = services.map((s) => s.packageName).toSet();

    // Load persisted icons first — instant display
    final cached = <String, Uint8List?>{};
    for (final pkg in packages) {
      final b64 = prefs.getString('app_icon_v1_$pkg');
      if (b64 != null) cached[pkg] = base64Decode(b64);
    }
    if (mounted && cached.isNotEmpty) {
      setState(() => _iconCache = {..._iconCache, ...cached});
    }

    // Fetch only what's missing from native, then persist
    final missing = packages.where((p) => !cached.containsKey(p)).toSet();
    if (missing.isEmpty) return;

    final fetched = await Future.wait(
      missing.map((pkg) async => MapEntry(pkg, await _appInfo.getAppIcon(pkg))),
    );
    for (final e in fetched) {
      if (e.value != null) {
        await prefs.setString('app_icon_v1_${e.key}', base64Encode(e.value!));
      }
    }
    if (mounted) {
      setState(() => _iconCache = {..._iconCache, ...Map.fromEntries(fetched)});
    }
  }

  void _buildSections() {
    final q = _query.toLowerCase();

    final visible = _allServices.where((s) {
      if (_filterRunning && !s.isRunning) return false;
      if (_filterAppOwned && !s.isAppOwned) return false;
      if (q.isNotEmpty) {
        return s.packageName.toLowerCase().contains(q) ||
            s.serviceClass.toLowerCase().contains(q) ||
            (s.appName?.toLowerCase().contains(q) ?? false);
      }
      return true;
    }).toList();

    final monitored = visible.where(_isMonitored).toList();
    final unmonitored = visible.where((s) => !_isMonitored(s)).toList();

    final groups = <String, List<RunningService>>{};
    for (final s in unmonitored) {
      groups.putIfAbsent(s.packageName, () => []).add(s);
    }
    final sortedPkgs = groups.keys.toList()
      ..sort((a, b) {
        final aName = groups[a]!.first.appName ?? a;
        final bName = groups[b]!.first.appName ?? b;
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });

    final sections = <_Section>[];

    // Monitored services: one section per app (grouped), shown first
    if (monitored.isNotEmpty) {
      final monByPkg = <String, List<RunningService>>{};
      for (final s in monitored) {
        monByPkg.putIfAbsent(s.packageName, () => []).add(s);
      }
      final sortedMon = monByPkg.keys.toList()
        ..sort((a, b) {
          final aName = monByPkg[a]!.first.appName ?? a;
          final bName = monByPkg[b]!.first.appName ?? b;
          return aName.toLowerCase().compareTo(bName.toLowerCase());
        });
      for (final pkg in sortedMon) {
        final svcs = monByPkg[pkg]!;
        sections.add(_Section(
          appName: svcs.first.appName ?? pkg,
          packageName: pkg,
          services: svcs,
          isMonitoredGroup: true,
        ));
      }
    }

    for (final pkg in sortedPkgs) {
      final svcs = groups[pkg]!
        ..sort((a, b) {
          final owned = (a.isAppOwned ? 0 : 1) - (b.isAppOwned ? 0 : 1);
          return owned != 0 ? owned : a.serviceClass.compareTo(b.serviceClass);
        });
      sections.add(_Section(
        appName: svcs.first.appName ?? pkg,
        packageName: pkg,
        services: svcs,
      ));
    }

    _sections = sections;
  }

  bool _isMonitored(RunningService s) => widget.alreadyMonitored.any(
        (m) => m.packageName == s.packageName && m.serviceClass == s.serviceClass,
      );

  void _pick(RunningService s) {
    Navigator.pop(context, MonitoredService(
      packageName: s.packageName,
      serviceClass: s.serviceClass,
      displayLabel: _labelFor(s),
      appName: s.appName,
      wasRunning: s.isRunning,
      lastChecked: DateTime.now(),
    ));
  }

  String _labelFor(RunningService s) {
    if (s.packageName.contains('life360')) return 'Life360';
    return s.serviceClass.split('.').last;
  }

  Widget _buildAvatar(String packageName, {double radius = 18}) {
    final bytes = _iconCache[packageName];
    if (bytes != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: MemoryImage(bytes),
        backgroundColor: Colors.transparent,
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(
        packageName.isNotEmpty ? packageName.split('.').last[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: radius * 0.75,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _badge(String label, Color bg, Color fg) => Container(
        margin: const EdgeInsets.only(left: 5),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Service'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search app, package or service...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() { _query = v; _buildSections(); }),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Text(_error!),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ]),
                )
              : Column(
                  children: [
                    // Filter chips — showCheckmark:false prevents icon+check overlay
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(children: [
                        FilterChip(
                          label: const Text('Running only'),
                          selected: _filterRunning,
                          showCheckmark: false,
                          avatar: Icon(
                            Icons.play_circle_outline,
                            size: 16,
                            color: _filterRunning ? cs.onSecondaryContainer : cs.onSurfaceVariant,
                          ),
                          onSelected: (v) => setState(() { _filterRunning = v; _buildSections(); }),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('App Services only'),
                          selected: _filterAppOwned,
                          showCheckmark: false,
                          avatar: Icon(
                            Icons.star_outline,
                            size: 16,
                            color: _filterAppOwned ? cs.onSecondaryContainer : cs.onSurfaceVariant,
                          ),
                          onSelected: (v) => setState(() { _filterAppOwned = v; _buildSections(); }),
                        ),
                      ]),
                    ),
                    // Info hint
                    Container(
                      width: double.infinity,
                      color: cs.primaryContainer.withValues(alpha: 0.4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Row(children: [
                        Icon(Icons.info_outline, size: 13, color: cs.onPrimaryContainer),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'App Service = app\'s own code. Pick the service related to location, tracking, or sync.',
                            style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer),
                          ),
                        ),
                      ]),
                    ),
                    Expanded(
                      child: _sections.isEmpty
                          ? Center(child: Text(_allServices.isEmpty
                              ? 'No services detected.'
                              : 'No matching services.'))
                          : ListView.builder(
                              itemCount: _sections.length,
                              itemBuilder: (ctx, i) => _buildSectionTile(_sections[i]),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSectionTile(_Section section) {
    final cs = Theme.of(context).colorScheme;
    // Key includes filter state so initiallyExpanded re-evaluates when filters change
    final key = ValueKey('${section.packageName}_${_query}_${_filterRunning}_$_filterAppOwned');
    final autoExpand = section.isMonitoredGroup || _query.isNotEmpty || _filterRunning;

    if (section.isMonitoredGroup) {
      return ExpansionTile(
        key: key,
        initiallyExpanded: autoExpand,
        leading: _buildAvatar(section.packageName),
        title: Row(children: [
          Expanded(
            child: Text(section.appName,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          _badge('Monitoring', Colors.green.shade100, Colors.green.shade800),
        ]),
        children: section.services.map(_buildServiceTile).toList(),
      );
    }

    return ExpansionTile(
      key: key,
      initiallyExpanded: autoExpand,
      leading: _buildAvatar(section.packageName),
      title: Row(children: [
        Expanded(
          child: Text(section.appName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ),
        if (section.runningCount > 0)
          _badge('${section.runningCount} running', Colors.green.shade100, Colors.green.shade800),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text('${section.services.length}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
      ]),
      children: section.services.map(_buildServiceTile).toList(),
    );
  }

  Widget _buildServiceTile(RunningService s) {
    final cs = Theme.of(context).colorScheme;
    final monitored = _isMonitored(s);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 24, right: 16),
      title: Row(children: [
        Expanded(
          child: Text(
            s.displayServiceClass,
            style: TextStyle(
              fontWeight: s.isAppOwned ? FontWeight.w600 : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
        if (s.isRunning)
          _badge('Running', Colors.green.shade100, Colors.green.shade800),
        if (s.isAppOwned)
          _badge('App Service', cs.primaryContainer, cs.onPrimaryContainer),
      ]),
      subtitle: Text(s.packageName, style: const TextStyle(fontSize: 11)),
      trailing: monitored
          ? const Icon(Icons.check_circle, color: Colors.green)
          : const Icon(Icons.add_circle_outline),
      enabled: !monitored,
      onTap: monitored ? null : () => _pick(s),
    );
  }
}
