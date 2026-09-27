import 'package:flutter/material.dart';

import '../features/ai/key/byok_vault.dart';
import '../features/ai/rewrite/rewrite_launcher.dart';
import '../features/board/post/compose_screen.dart';
import '../features/board/post/post_compose_state.dart';
import 'routes.dart';

/// Board compose flow host (I01, R-23).
///
/// Owns a [PostComposeState] + draft [TextEditingController] and is the ONLY
/// place in the app that wires B11's `launchRewrite` seam: the
/// 'Improve Wording' button opens the rewrite sheet, and `onAccepted`
/// inserts the accepted suggestion into this host's draft (sheet never
/// writes anywhere itself). 'Continue' carries the draft into
/// [BoardComposeScreen] for submit.
///
/// The vault is built with [SecureStorageBackend] + null accountId at shell
/// level. TODO(AUTH-UID): pass the signed-in uid as `accountId` so two
/// accounts on one device never share key material.
class BoardComposeHost extends StatefulWidget {
  /// Current author uid. Null shows the setup note: draft + AI Improve
  /// Wording stay usable, only the submit step is gated.
  final String? userId;

  const BoardComposeHost({super.key, this.userId});

  @override
  State<BoardComposeHost> createState() => _BoardComposeHostState();
}

class _BoardComposeHostState extends State<BoardComposeHost> {
  static const Color _teal = Color(0xFF0E5A66);

  late final PostComposeState _compose = PostComposeState();
  late final TextEditingController _draft = TextEditingController(
    text: _compose.body,
  );
  late final ByokVault _vault = ByokVault(backend: SecureStorageBackend());

  @override
  void dispose() {
    _draft.dispose();
    _compose.dispose();
    super.dispose();
  }

  /// B11 seam: suggestion flows back ONLY through `onAccepted`, which inserts
  /// it into this host's draft. Reject leaves the draft untouched.
  Future<void> _improveWording() async {
    await launchRewrite(
      context,
      vault: _vault,
      initialDraft: _draft.text,
      onAccepted: (String suggestion) {
        _draft.text = suggestion;
        _compose.setBody(suggestion);
      },
    );
  }

  void _continue() {
    final String? userId = widget.userId;
    if (userId == null || userId.trim().isEmpty) return;
    _compose.setBody(_draft.text);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BoardComposeScreen(
          compose: _compose,
          userId: userId,
          newUuid: () => DateTime.now().microsecondsSinceEpoch.toString(),
          // TODO(SUPABASE-BOARD): replace these with the hosted Supabase
          // row insert / post-media bucket upload / orphan cleanup. They
          // throw explicitly until then — never fake a published post.
          createPost: ({required String userId, required String body}) =>
              throw UnimplementedError(
                'Board submit needs hosted Supabase wiring (see TODO in board_compose_host.dart).',
              ),
          uploadBytes: (String path, List<int> bytes) =>
              throw UnimplementedError(
                'Board image upload needs hosted Supabase wiring (see TODO in board_compose_host.dart).',
              ),
          deletePost: (String postId) => throw UnimplementedError(
            'Board cleanup needs hosted Supabase wiring (see TODO in board_compose_host.dart).',
          ),
          // Null picker hides the attach button until platform wiring lands.
          pickImageBytes: null,
          onDone: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _openKeySetup() {
    Navigator.of(context).pushNamed(AppRoutes.keySetup);
  }

  @override
  Widget build(BuildContext context) {
    final bool canSubmit =
        widget.userId != null && widget.userId!.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('New post'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!canSubmit)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Sign-in required to publish. You can still draft text and use Improve Wording below.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _draft,
                    maxLines: 6,
                    maxLength: 2000,
                    onChanged: _compose.setBody,
                    decoration: InputDecoration(
                      hintText: 'Share a station tip…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _improveWording,
                    icon: const Icon(Icons.auto_fix_high_outlined),
                    label: const Text('Improve Wording'),
                  ),
                  TextButton(
                    onPressed: _openKeySetup,
                    child: const Text('AI Settings (add or remove key)'),
                  ),
                  const SizedBox(height: 4),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _teal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: canSubmit ? _continue : null,
                    child: const Text(
                      'Continue',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
