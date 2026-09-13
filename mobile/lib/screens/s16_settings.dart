import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../services/scope_api.dart';

/// Connection settings.
///
/// NOT one of the fifteen screens in SCOPE-System-Flow-Revised.md. This is a
/// demonstration and development affordance, deliberately numbered outside the
/// S01–S15 set so it is not mistaken for specified scope.
///
/// It exists because the backend runs on a laptop reached over a phone
/// hotspot, and DHCP does not hand out the same address twice. Without a way
/// to correct the address on the device, every change of address would mean
/// rebuilding and re-installing the APK.
///
/// It is reached only through S15 About — never from the reporting flow — so a
/// member of the public following the reporting task cannot wander into it.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// Outcome of the last reachability check.
enum _Probe { untested, testing, reachable, unreachable }

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: AppSettings.instance.baseUrl);

  _Probe _probe = _Probe.untested;
  String? _probedUrl;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Checks the address currently in the field, not the saved one.
  ///
  /// Testing before saving is the point: it separates "I typed the IP wrongly"
  /// from "the backend is not running" from "the firewall is blocking it"
  /// while there is still time to do something about it.
  Future<void> _test() async {
    final target = AppSettings.normaliseBaseUrl(_controller.text);
    setState(() {
      _probe = _Probe.testing;
      _probedUrl = target;
    });

    final ok = await context.read<ScopeApi>().ping(baseUrl: target);
    if (!mounted) return;

    setState(() => _probe = ok ? _Probe.reachable : _Probe.unreachable);
  }

  Future<void> _save() async {
    final saved = await AppSettings.instance.setBaseUrl(_controller.text);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Backend address set to $saved')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    await AppSettings.instance.reset();
    if (!mounted) return;

    setState(() {
      _controller.text = AppSettings.instance.baseUrl;
      _probe = _Probe.untested;
      _probedUrl = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connection settings')),
      body: ListView(
        padding: const EdgeInsets.all(Gap.md),
        children: [
          const Text(
            'The address of the SCOPE backend on the development machine. '
            'Change this when the laptop joins a different network and is '
            'given a different address.',
            style: TextStyle(color: ScopeTheme.inkMuted, height: 1.5),
          ),
          const SizedBox(height: Gap.lg),

          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Backend address',
              hintText: '172.20.10.2',
              helperText: 'Port 8000 and http:// are added if you omit them.',
              helperMaxLines: 2,
            ),
            // Retyping the address invalidates whatever the last test proved.
            onChanged: (_) {
              if (_probe != _Probe.untested) {
                setState(() => _probe = _Probe.untested);
              }
            },
          ),
          const SizedBox(height: Gap.md),

          OutlinedButton.icon(
            onPressed: _probe == _Probe.testing ? null : _test,
            icon: _probe == _Probe.testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_check),
            label: Text(
              _probe == _Probe.testing ? 'Testing…' : 'Test connection',
            ),
          ),

          if (_probe == _Probe.reachable || _probe == _Probe.unreachable) ...[
            const SizedBox(height: Gap.md),
            _ProbeResult(probe: _probe, url: _probedUrl ?? ''),
          ],

          const SizedBox(height: Gap.lg),
          FilledButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(height: Gap.sm),
          TextButton(
            onPressed: AppSettings.instance.isDefault ? null : _reset,
            child: const Text('Reset to default'),
          ),

          const SizedBox(height: Gap.xl),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Built-in default',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    AppConfig.defaultApiBaseUrl,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: ScopeTheme.inkMuted,
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  const Text(
                    'Used until an address is saved here. Find the laptop\'s '
                    'address on macOS with:  ipconfig getifaddr en0',
                    style: TextStyle(
                      fontSize: 13,
                      color: ScopeTheme.inkMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Gap.lg),
        ],
      ),
    );
  }
}

class _ProbeResult extends StatelessWidget {
  const _ProbeResult({required this.probe, required this.url});

  final _Probe probe;
  final String url;

  @override
  Widget build(BuildContext context) {
    final reachable = probe == _Probe.reachable;
    final colour = reachable ? ScopeTheme.success : ScopeTheme.danger;

    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            reachable ? Icons.check_circle : Icons.error,
            color: colour,
            size: 20,
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reachable ? 'Backend reachable' : 'No response',
                  style: TextStyle(fontWeight: FontWeight.w700, color: colour),
                ),
                const SizedBox(height: Gap.xs),
                Text(
                  reachable
                      ? '$url answered the health check.'
                      : '$url did not answer. Check that both devices are on '
                          'the same hotspot, that the backend is running, and '
                          'that the address matches ipconfig getifaddr en0.',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: ScopeTheme.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
