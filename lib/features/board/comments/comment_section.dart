import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../design/state/state.dart';
import '../post/relative_time.dart';
import 'comment.dart';
import 'comment_thread.dart';

/// Per-post comments section for one Journey Board feed card.
///
/// Owns one [CommentThread] for [postId] (created in [initState], disposed
/// with this widget), so threads on one card can never leak into another.
/// Nothing here calls Supabase directly — every side effect arrives through
/// the injected seams (coordinator-wired production closures, fakes in
/// tests).
///
/// Consumer contract:
/// * Collapsed, the section is a single "Comments" row. The count is shown
///   only after a load (it is never guessed), so the first render reads
///   "Comments" with no number.
/// * Expanding loads the thread: skeleton while loading, Retry on error,
///   an honest empty state, newest-first rows with relative time.
/// * Authors are never identified by id: the reader's own rows read "You",
///   everyone else's read "Traveller". Raw user ids stay out of the UI.
/// * Signed-out readers see the rows read-only with a sign-in hint; the
///   composer appears only for a signed-in [currentUserId].
/// * Backend failures surface as one plain sentence with Retry. Raw
///   exception text (`mutationError`) is never printed.
/// * Deleting your own comment asks for confirmation first.
class CommentSection extends StatefulWidget {
  /// Parent post id. All rows belong to this post.
  final String postId;

  /// Current author uid. Null/empty means signed out (read-only).
  final String? currentUserId;

  /// Injected comment seams (production: coordinator-wired closures).
  final FetchComments fetchComments;
  final AddCommentRow addComment;
  final DeleteCommentRow deleteComment;

  const CommentSection({
    super.key,
    required this.postId,
    required this.currentUserId,
    required this.fetchComments,
    required this.addComment,
    required this.deleteComment,
  });

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  late final CommentThread _thread = CommentThread(
    postId: widget.postId,
    fetchComments: widget.fetchComments,
  );
  final TextEditingController _composer = TextEditingController();
  bool _expanded = false;

  bool get _signedIn =>
      widget.currentUserId != null && widget.currentUserId!.isNotEmpty;

  @override
  void dispose() {
    _thread.dispose();
    _composer.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _thread.status == CommentThreadStatus.idle) {
      _thread.load();
    }
  }

  Future<void> _send() async {
    final uid = widget.currentUserId;
    if (uid == null || uid.isEmpty || _thread.adding) return;
    final ok = await _thread.add(
      userId: uid,
      body: _composer.text,
      addRow: widget.addComment,
    );
    if (ok && mounted) _composer.clear();
  }

  Future<void> _confirmDelete(Comment comment) async {
    final id = comment.id;
    if (id == null || id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete comment?'),
        content: const Text(
          'This removes your comment for everyone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE5484D),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _thread.remove(id, widget.deleteComment);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _thread,
      builder: (context, _) {
        final int count = _thread.comments.length;
        final bool loaded = _thread.status == CommentThreadStatus.loaded;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            PressScale(
              onTap: _toggle,
              semanticsLabel: _expanded ? 'Hide comments' : 'Show comments',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    size: 16,
                    color: Color(0xFF0E5A66),
                  ),
                  const SizedBox(width: 6),
                  // The count appears only after a load; before that the
                  // row reads "Comments" with no invented number.
                  AnimatedSwap(
                    child: Text(
                      loaded
                          ? (count == 0 ? 'Comment' : 'Comments ($count)')
                          : 'Comments',
                      key: ValueKey<String>(loaded ? 'c$count' : 'c?'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0E5A66),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.expand_more,
                      size: 18,
                      color: Color(0xFF0E5A66),
                    ),
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              FadeSlideIn(child: _expandedBody(context)),
            ],
          ],
        );
      },
    );
  }

  Widget _expandedBody(BuildContext context) {
    if (_thread.isLoading && _thread.comments.isEmpty) {
      return const Column(
        children: [
          SkeletonBlock(height: 44, borderRadius: 10),
          SizedBox(height: 6),
          SkeletonBlock(height: 44, borderRadius: 10),
        ],
      );
    }
    if (_thread.status == CommentThreadStatus.error &&
        _thread.comments.isEmpty) {
      return ErrorState(
        message: "Couldn't load the comments.",
        retryLabel: 'Retry',
        onRetry: _thread.load,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_thread.isEmpty)
          const EmptyState(
            icon: Icons.chat_bubble_outline,
            title: 'No comments yet',
            message: 'Start the conversation below.',
          )
        else
          StaggeredColumn(
            children: [
              for (final Comment comment in _thread.comments)
                _CommentRow(
                  comment: comment,
                  mine: _signedIn && comment.userId == widget.currentUserId,
                  deleting: _thread.deletingIds.contains(comment.id),
                  onDelete: () => _confirmDelete(comment),
                ),
            ],
          ),
        const SizedBox(height: 8),
        if (_signedIn)
          _Composer(
            controller: _composer,
            busy: _thread.adding,
            mutationFailed: _thread.mutationError != null,
            onSend: _send,
          )
        else
          const Text(
            'Sign in to join the conversation.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
      ],
    );
  }
}

class _CommentRow extends StatelessWidget {
  final Comment comment;
  final bool mine;
  final bool deleting;
  final VoidCallback onDelete;

  const _CommentRow({
    required this.comment,
    required this.mine,
    required this.deleting,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFF0E5A66).withValues(alpha: 0.12),
            child: Text(
              mine ? 'Y' : 'T',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0E5A66),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      mine ? 'You' : 'Traveller',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formatRelativeTime(comment.createdAt),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.body, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          if (mine)
            deleting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: 'Delete comment',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Colors.grey,
                    ),
                    onPressed: onDelete,
                  ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final bool mutationFailed;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.busy,
    required this.mutationFailed,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !busy,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Write a comment…',
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwap(
              child: IconButton.filled(
                key: ValueKey<bool>(busy),
                tooltip: 'Post comment',
                onPressed: busy ? null : onSend,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_outlined, size: 18),
              ),
            ),
          ],
        ),
        if (mutationFailed)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            // Raw backend text is never printed; one plain sentence plus
            // the composer's own retry (the send button above).
            child: Text(
              "Couldn't save that — please try again.",
              style: TextStyle(fontSize: 12, color: Color(0xFFE5484D)),
            ),
          ),
      ],
    );
  }
}
