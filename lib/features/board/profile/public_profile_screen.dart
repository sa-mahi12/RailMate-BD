/// Public author profile (P42).
///
/// Shows ONLY the safe public card fields (display name, @username, join date,
/// post count) plus that author's public posts. No email, phone, Telegram
/// identity, auth metadata or booking data is ever loaded — the data comes
/// from `public.public_profile_cards`, not from `public.profiles`.
library;

import 'package:flutter/material.dart';

import '../media/attachment_view.dart';
import '../post/post.dart';
import '../post/post_card.dart';
import 'public_profile.dart';

class PublicProfileScreen extends StatefulWidget {
  final String userId;
  final Future<PublicProfile?> Function(String userId) fetchProfile;
  final Future<List<Post>> Function(String userId) fetchPosts;

  /// Report this profile (opens the report dialog).
  final VoidCallback? onReportProfile;

  /// Open one of this author's posts in the single-post screen.
  final void Function(Post post)? onOpenPost;

  final ResolveAttachmentUrl? resolveAttachmentUrl;
  final OpenExternalUrl? openExternal;

  const PublicProfileScreen({
    super.key,
    required this.userId,
    required this.fetchProfile,
    required this.fetchPosts,
    this.onReportProfile,
    this.onOpenPost,
    this.resolveAttachmentUrl,
    this.openExternal,
  });

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  PublicProfile? _profile;
  List<Post> _posts = const <Post>[];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final PublicProfile? profile = await widget.fetchProfile(widget.userId);
      final List<Post> posts = profile == null
          ? const <Post>[]
          : await widget.fetchPosts(widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _posts = posts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't load this profile. Check your connection and retry.";
        _loading = false;
      });
    }
  }

  String _joined(DateTime? joinedAt) {
    if (joinedAt == null) return '';
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final DateTime local = joinedAt.toLocal();
    return 'Joined ${months[local.month - 1]} ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E5A66),
        foregroundColor: Colors.white,
        title: const Text('Profile'),
        actions: <Widget>[
          if (widget.onReportProfile != null)
            IconButton(
              tooltip: 'Report profile',
              onPressed: widget.onReportProfile,
              icon: const Icon(Icons.flag_outlined),
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final String? error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final PublicProfile? profile = _profile;
    if (profile == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This profile is not available.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFF0E5A66),
                child: Text(
                  profile.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      profile.displayName.isEmpty
                          ? profile.label
                          : profile.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (profile.handle != null)
                      Text(
                        profile.handle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF5B6B73),
                        ),
                      ),
                    Text(
                      <String>[
                        if (_joined(profile.joinedAt).isNotEmpty)
                          _joined(profile.joinedAt),
                        '${profile.postCount} '
                            '${profile.postCount == 1 ? 'post' : 'posts'}',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF5B6B73),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_posts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No public posts yet.', textAlign: TextAlign.center),
          ),
        for (final Post post in _posts)
          GestureDetector(
            onTap: widget.onOpenPost == null
                ? null
                : () => widget.onOpenPost!(post),
            child: BoardPostCard(
              post: post,
              resolveAttachmentUrl: widget.resolveAttachmentUrl,
              openExternal: widget.openExternal,
            ),
          ),
      ],
    );
  }
}
