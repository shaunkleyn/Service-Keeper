import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _useAppColors = false;
  int _defaultInterval = 15;

  static const _intervalPresets = [
    (label: '5 minutes', minutes: 5),
    (label: '10 minutes', minutes: 10),
    (label: '15 minutes', minutes: 15),
    (label: '30 minutes', minutes: 30),
    (label: '1 hour', minutes: 60),
    (label: '2 hours', minutes: 120),
    (label: '4 hours', minutes: 240),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useAppColors = prefs.getBool('use_app_colors') ?? false;
      _defaultInterval = prefs.getInt('default_check_interval') ?? 15;
    });
  }

  Future<void> _setAppColors(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('use_app_colors', value);
    setState(() => _useAppColors = value);
  }

  Future<void> _setDefaultInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('default_check_interval', minutes);
    setState(() => _defaultInterval = minutes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _sectionHeader(context, 'Appearance'),
          SwitchListTile(
            title: const Text('Colorful app cards'),
            subtitle: const Text(
              'Tints each app card and its toggle switch with colors extracted from the app\'s icon.',
            ),
            value: _useAppColors,
            onChanged: _setAppColors,
          ),
          const Divider(height: 1),
          _sectionHeader(context, 'Default check interval'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Sets the check interval pre-selected when you add a new service. '
              'Services already added are not affected.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          ..._intervalPresets.map((p) => RadioListTile<int>(
                title: Text(p.label),
                subtitle: p.minutes < 15
                    ? Text(
                        'Uses alarm-based scheduling — more aggressive but may drain battery faster',
                        style: theme.textTheme.bodySmall,
                      )
                    : null,
                value: p.minutes,
                groupValue: _defaultInterval,
                onChanged: (v) => _setDefaultInterval(v!),
              )),
          if (_defaultInterval < 15)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: theme.colorScheme.onTertiaryContainer, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Intervals under 15 minutes use self-scheduling one-time workers. '
                        'Android Doze mode may still delay checks during deep sleep.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onTertiaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}
