/// P42 — minimal moderation: report a post or a public profile.
///
/// Reasons mirror the database check constraints in
/// `20261124000001_p42_social_web.sql`. One report per reporter per target
/// (the client upserts). Reporting is NOT rating: no stars, no public score,
/// and no effect on personal reputation.
library;

import 'package:flutter/material.dart';

/// What is being reported.
enum ReportTarget { post, user }

/// Allowed reasons (kept in sync with the SQL check constraints).
enum ReportReason {
  spam('spam', 'Spam or advertising'),
  harassment('harassment', 'Harassment or hate'),
  misinformation('misinformation', 'Misleading travel information'),
  unsafeMedia('unsafe_media', 'Unsafe or private media'),
  impersonation('impersonation', 'Impersonation'),
  other('other', 'Something else');

  const ReportReason(this.dbValue, this.label);

  final String dbValue;
  final String label;
}

/// Reasons offered for [target]; post reports cannot claim impersonation and
/// user reports cannot claim "unsafe media".
List<ReportReason> reportReasonsFor(ReportTarget target) {
  switch (target) {
    case ReportTarget.post:
      return const <ReportReason>[
        ReportReason.spam,
        ReportReason.harassment,
        ReportReason.misinformation,
        ReportReason.unsafeMedia,
        ReportReason.other,
      ];
    case ReportTarget.user:
      return const <ReportReason>[
        ReportReason.spam,
        ReportReason.harassment,
        ReportReason.impersonation,
        ReportReason.other,
      ];
  }
}

/// The submitted report (reason + optional note).
class ReportDraft {
  final ReportReason reason;
  final String? details;

  const ReportDraft({required this.reason, this.details});
}

/// Shows the report sheet. Returns null when the reader cancels.
Future<ReportDraft?> showBoardReportDialog(
  BuildContext context, {
  required ReportTarget target,
  required String targetLabel,
}) {
  return showDialog<ReportDraft>(
    context: context,
    builder: (BuildContext ctx) =>
        _ReportDialog(target: target, targetLabel: targetLabel),
  );
}

class _ReportDialog extends StatefulWidget {
  final ReportTarget target;
  final String targetLabel;

  const _ReportDialog({required this.target, required this.targetLabel});

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  ReportReason _reason = ReportReason.spam;
  final TextEditingController _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<ReportReason> reasons = reportReasonsFor(widget.target);
    return AlertDialog(
      title: Text(
        widget.target == ReportTarget.post ? 'Report post' : 'Report profile',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.targetLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF5B6B73)),
            ),
            const SizedBox(height: 12),
            for (final ReportReason reason in reasons)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                onTap: () => setState(() => _reason = reason),
                leading: Icon(
                  _reason == reason
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: const Color(0xFF0E5A66),
                ),
                title: Text(reason.label, style: const TextStyle(fontSize: 13)),
              ),
            TextField(
              controller: _details,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            ReportDraft(
              reason: _reason,
              details: _details.text.trim().isEmpty
                  ? null
                  : _details.text.trim(),
            ),
          ),
          child: const Text('Send report'),
        ),
      ],
    );
  }
}
