import 'package:flutter/material.dart';

import '../../../design/design.dart';
import 'byok_vault.dart';
import 'openrouter_client.dart';
import '../rewrite/rewrite_state.dart' show mapRewriteError;

/// AI Settings / BYOK key setup screen (packet B10 / R-23, ref-10 AI Settings).
///
/// Visual tokens per UI_VISUAL_SPEC: page bg #F4F7F9, primary deep teal
/// #0E5A66, accent green #1E9E6A, danger #E5484D, white cards radius 16,
/// primary button teal radius 12, inputs radius 10.
///
/// Privacy rules:
/// - Save/Remove operate on [ByokVault] (secure storage + cache).
/// - Test Connection reads the key from the vault ONLY inside the explicit
///   button handler AND requires the per-request consent checkbox
///   ('Send my key with this request only') before passing the key to
///   [OpenRouterClient.sendWithKey]. No auto-attach anywhere.
class KeySetupScreen extends StatefulWidget {
  final ByokVault vault;

  /// Real OpenRouter client. Null constructs one on demand; tests inject
  /// `OpenRouterClient(httpClient: fake)`.
  final OpenRouterClient? client;

  const KeySetupScreen({super.key, required this.vault, this.client});

  @override
  State<KeySetupScreen> createState() => _KeySetupScreenState();
}

class _KeySetupScreenState extends State<KeySetupScreen> {
  static const _primary = Color(0xFF0E5A66);
  static const _success = Color(0xFF1E9E6A);
  static const _danger = Color(0xFFE5484D);
  static const _pageBg = Color(0xFFF4F7F9);

  final TextEditingController _keyController = TextEditingController();
  bool _consent = false;
  bool _busy = false;
  bool? _hasKey;
  String? _notice;
  bool _noticeIsError = false;

  OpenRouterClient get _client => widget.client ?? _ownedClient;
  late final OpenRouterClient _ownedClient = OpenRouterClient();

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final has = await widget.vault.hasKey();
    if (!mounted) return;
    setState(() => _hasKey = has);
  }

  void _setNotice(String message, {bool isError = false}) {
    setState(() {
      _notice = message;
      _noticeIsError = isError;
    });
  }

  Future<void> _onSave() async {
    setState(() => _busy = true);
    try {
      await widget.vault.saveKey(_keyController.text);
      _keyController.clear();
      await _refreshStatus();
      _setNotice('Connected successfully.');
    } on ArgumentError catch (e) {
      _setNotice(
        e.message?.toString() ?? 'Key must not be empty.',
        isError: true,
      );
    } catch (e) {
      _setNotice('Save failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onRemove() async {
    setState(() => _busy = true);
    try {
      await widget.vault.removeKey();
      await _refreshStatus();
      _setNotice('Key removed from this device.');
    } catch (e) {
      _setNotice('Remove failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Explicit user action only: requires the per-request consent checkbox,
  /// then reads the vault key and passes it explicitly to the stub.
  Future<void> _onTestConnection() async {
    if (!_consent) {
      _setNotice(
        'Tick “Send my key with this request only” to allow this one call.',
        isError: true,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final key = await widget.vault.readKey();
      if (key == null || key.isEmpty) {
        _setNotice('No key saved.', isError: true);
        return;
      }
      final reply = await _client.sendWithKey(
        key: key,
        messages: const [
          {'role': 'user', 'content': 'Connection test.'},
        ],
      );
      _setNotice(reply);
    } on ArgumentError catch (e) {
      _setNotice(e.message?.toString() ?? 'Test failed.', isError: true);
    } catch (e) {
      // Honest cause mapping (401 → invalid key, 402/429 → quota,
      // network → connection failed). The mapped text never contains key
      // material — only the failure class.
      _setNotice(mapRewriteError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          // Consent is single-use: reset after each explicit request.
          _consent = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final has = _hasKey;
    return Scaffold(
      backgroundColor: _pageBg,
      body: Column(
        children: [
          FadeSlideIn(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
              decoration: const BoxDecoration(
                color: _primary,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  PressScale(
                    onTap: () => Navigator.of(context).maybePop(),
                    semanticsLabel: 'Back',
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white24,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.chevron_left,
                          color: Colors.white,
                        ),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'AI Settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your OpenRouter key stays on this device in secure storage. '
                        'It is never synced and is sent only when you explicitly allow one request.',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      if (has == true)
                        // Keyed by the connected state so the banner
                        // cross-fades in rather than popping.
                        AnimatedSwap(
                          child: Container(
                            key: const ValueKey<String>('has_key'),
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'Connected successfully.',
                              style: TextStyle(
                                color: _success,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      if (has == true) const SizedBox(height: 12),
                      TextField(
                        controller: _keyController,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'OpenRouter key',
                          hintText: 'Paste your key',
                          prefixIcon: const Icon(Icons.key),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _busy ? null : _onSave,
                          child: AnimatedSwap(
                            child: Text(
                              _busy ? 'Saving…' : 'Save',
                              key: ValueKey<bool>(_busy),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _danger,
                            side: const BorderSide(color: _danger),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _busy ? null : _onRemove,
                          child: AnimatedSwap(
                            child: Text(
                              _busy ? 'Removing…' : 'Remove',
                              key: ValueKey<bool>(_busy),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Test connection (one explicit request)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      // Material wrapper: the consent tile needs a Material
                      // ancestor for ink splashes (the card Container would
                      // otherwise hide them; debug-asserted in tests).
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text(
                            'Send my key with this request only',
                            style: TextStyle(fontSize: 13),
                          ),
                          value: _consent,
                          activeColor: _primary,
                          onChanged: (v) =>
                              setState(() => _consent = v ?? false),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _busy ? null : _onTestConnection,
                          child: AnimatedSwap(
                            child: Text(
                              _busy ? 'Testing…' : 'Test Connection',
                              key: ValueKey<bool>(_busy),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Booking works with no AI key. AI rewrite always asks first.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (_notice != null) ...[
                  const SizedBox(height: 12),
                  // Keyed by message + severity: each new result
                  // cross-fades in, and an error never reuses the style of
                  // a previous success.
                  AnimatedSwap(
                    child: Container(
                      key: ValueKey<String>('${_noticeIsError}_$_notice'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _noticeIsError
                            ? _danger.withValues(alpha: 0.1)
                            : _success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _notice!,
                        style: TextStyle(
                          color: _noticeIsError ? _danger : _success,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
