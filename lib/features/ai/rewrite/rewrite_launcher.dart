import 'package:flutter/material.dart';

import '../key/byok_vault.dart';
import '../key/openrouter_client.dart';
import 'rewrite_bar.dart';

/// Integration seam for the I01 navigation worker (packet B11 / R-23).
///
/// Shows the [RewriteBar] in a modal bottom sheet. The host supplies the
/// user's current draft and an [onAccepted] callback; the sheet NEVER
/// applies text itself — on Accept the suggestion is handed to [onAccepted]
/// and the sheet closes, on Reject the draft is untouched.
///
/// Exact signature (documented for I01):
///
/// ```dart
/// Future<void> launchRewrite(
///   BuildContext context, {
///   required ByokVault vault,
///   required String initialDraft,
///   required ValueChanged<String> onAccepted,
///   OpenRouterClient? client,
/// })
/// ```
///
/// A null [client] constructs the real F14 [OpenRouterClient] on demand
/// (tests inject `OpenRouterClient(httpClient: fake)`).
///
/// Example host call (I01):
///
/// ```dart
/// await launchRewrite(
///   context,
///   vault: ByokVault(backend: SecureStorageBackend(), accountId: uid),
///   initialDraft: _bodyController.text,
///   onAccepted: (suggestion) {
///     _bodyController.text = suggestion; // host applies; slice never does
///   },
/// );
/// ```
Future<void> launchRewrite(
  BuildContext context, {
  required ByokVault vault,
  required String initialDraft,
  required ValueChanged<String> onAccepted,
  OpenRouterClient? client,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: RewriteBar(
          vault: vault,
          client: client,
          initialDraft: initialDraft,
          callbacks: RewriteHostCallbacks(
            onAccepted: (suggestion) {
              onAccepted(suggestion);
              Navigator.of(sheetContext).maybePop();
            },
          ),
        ),
      ),
    ),
  );
}
