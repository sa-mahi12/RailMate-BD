import 'package:flutter/material.dart';

import '../key/byok_vault.dart';
import '../key/openrouter_client_stub.dart';
import 'rewrite_state.dart';

/// Host callbacks for the rewrite slice (packet B11 / R-23).
///
/// The slice NEVER applies text itself: on Accept, [RewriteBar] calls
/// [onAccepted] with the suggestion and the host (e.g. the post composer
/// owned by the I01 navigation worker) decides what to do with it.
/// On Reject nothing is called and the draft is unchanged.
class RewriteHostCallbacks {
  final ValueChanged<String> onAccepted;

  const RewriteHostCallbacks({required this.onAccepted});
}

/// Compact rewrite entry + suggestion card (packet B11 / R-23,
/// ref-8 AI Improve).
///
/// - Explicit 'Improve Wording' button; sends the draft ONLY on tap, ONLY
///   when the per-request consent checkbox
///   ('Send my key with this request only', B10 screen pattern) is ticked,
///   and ONLY with the key read from [vault] passed explicitly to
///   [OpenRouterClientStub.sendWithKey] at call time.
/// - Core works WITHOUT a key: when no key is stored, the button is
///   disabled and a setup prompt ('Add one in AI Settings') is shown.
/// - Suggestion card shows the returned text with Accept/Reject. Accept
///   invokes [callbacks.onAccepted] and never writes anywhere itself;
///   Reject discards. No auto-commit, no auto-publish.
/// - Errors render as plain text via [RewriteState.errorMessage]
///   (401 → key invalid, 429 → quota exceeded, network → connection failed).
class RewriteBar extends StatefulWidget {
  final ByokVault vault;
  final RewriteHostCallbacks callbacks;
  final String initialDraft;
  final OpenRouterClientStub client;

  const RewriteBar({
    super.key,
    required this.vault,
    required this.callbacks,
    required this.initialDraft,
    this.client = const OpenRouterClientStub(),
  });

  @override
  State<RewriteBar> createState() => _RewriteBarState();
}

class _RewriteBarState extends State<RewriteBar> {
  static const _primary = Color(0xFF0E5A66);
  static const _success = Color(0xFF1E9E6A);
  static const _danger = Color(0xFFE5484D);

  late final RewriteState _state;
  bool? _hasKey;

  @override
  void initState() {
    super.initState();
    _state = RewriteState(draft: widget.initialDraft);
    _state.addListener(_onStateChanged);
    _refreshKeyStatus();
  }

  @override
  void didUpdateWidget(covariant RewriteBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDraft != widget.initialDraft) {
      _state.updateDraft(widget.initialDraft);
    }
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChanged);
    _state.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshKeyStatus() async {
    final has = await widget.vault.hasKey();
    if (!mounted) return;
    setState(() => _hasKey = has);
  }

  /// Explicit user action only: single 'Improve Wording' tap → one
  /// consent-gated request. The vault key is read here and passed
  /// explicitly to the B10 stub; nothing auto-attaches it.
  Future<void> _onImprove() {
    return _state.improve(
      readKey: widget.vault.readKey,
      send: ({required String key, required String draft}) =>
          widget.client.sendWithKey(
            key: key,
            messages: [
              const {
                'role': 'system',
                'content':
                    'Rewrite the user draft for a railway board post. '
                    'Return only the rewritten text.',
              },
              {'role': 'user', 'content': draft},
            ],
          ),
    );
  }

  void _onAccept() {
    final text = _state.accept();
    if (text != null && text.isNotEmpty) {
      widget.callbacks.onAccepted(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = _hasKey;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'AI Improve',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_state.draft, style: const TextStyle(fontSize: 13)),
          ),
          if (hasKey == false) ...[
            const SizedBox(height: 12),
            const Text(
              'AI rewrite needs a key. Add one in AI Settings.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
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
                onPressed: null,
                child: const Text('Improve Wording'),
              ),
            ),
          ] else ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Send my key with this request only',
                style: TextStyle(fontSize: 13),
              ),
              value: _state.consent,
              activeColor: _primary,
              onChanged: _state.isLoading
                  ? null
                  : (v) => _state.setConsent(v ?? false),
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
                onPressed: _state.isLoading ? null : _onImprove,
                child: const Text('Improve Wording'),
              ),
            ),
          ],
          if (_state.isLoading) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_state.status == RewriteStatus.error &&
              _state.errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _state.errorMessage!,
                style: const TextStyle(color: _danger, fontSize: 13),
              ),
            ),
          ],
          if (_state.hasSuggestion) ...[
            const SizedBox(height: 12),
            const Icon(Icons.arrow_downward, color: _primary),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _state.suggestion!,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _onAccept,
                    child: const Text('Accept'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primary,
                      side: const BorderSide(color: _primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _state.reject,
                    child: const Text('Reject'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Nothing is replaced until you tap Accept.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}
