/// Telegram phone-verification section (RailMate BD, P41).
///
/// The only place the app offers phone verification through Telegram. It never
/// shows "Phone verified" until [TelegramVerificationState.isVerified] is true,
/// which requires the server row to be `verified`. Booking never depends on
/// this section: an error simply leaves the account unverified.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../auth/auth_theme.dart';
import 'telegram_verification_state.dart';

class TelegramVerifySection extends StatefulWidget {
  final TelegramVerificationState state;

  const TelegramVerifySection({super.key, required this.state});

  @override
  State<TelegramVerifySection> createState() => _TelegramVerifySectionState();
}

class _TelegramVerifySectionState extends State<TelegramVerifySection> {
  TelegramVerificationState get state => widget.state;

  @override
  void initState() {
    super.initState();
    // One hydration attempt so an existing verification survives app restarts.
    unawaited(widget.state.restore());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (BuildContext context, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kAuthTeal.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Row(
                children: <Widget>[
                  Icon(Icons.phone_iphone, color: kAuthTeal, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Phone verification',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kAuthTeal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Telegram contact sharing — no SMS is sent.',
                style: TextStyle(fontSize: 12, color: kAuthHint),
              ),
              const SizedBox(height: 12),
              _body(context),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    switch (state.status) {
      case TelegramStatus.verified:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.verified, color: kAuthGreen, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Phone verified — ${state.maskedPhone}',
                    style: const TextStyle(
                      color: kAuthGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Verified with Telegram contact sharing. The full number stays '
              'hidden; this is not an SMS confirmation.',
              style: TextStyle(fontSize: 12, color: kAuthHint),
            ),
          ],
        );
      case TelegramStatus.creating:
        return Row(
          children: <Widget>[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Starting verification…',
              style: TextStyle(color: kAuthHint, fontSize: 13),
            ),
          ],
        );
      case TelegramStatus.waiting:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Waiting for Telegram — share your number in the bot chat, then '
              'come back here.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => state.cancel(),
              icon: const Icon(Icons.close, size: 18, color: kAuthHint),
              label: const Text('Cancel', style: TextStyle(color: kAuthHint)),
            ),
          ],
        );
      case TelegramStatus.expired:
        return _retry(
          message:
              'That link expired before the number was shared. Start again to '
              'get a fresh one.',
        );
      case TelegramStatus.cancelled:
        return _retry(
          message: 'Verification was cancelled. You can start again anytime.',
        );
      case TelegramStatus.error:
        return _retry(message: state.errorMessage);
      case TelegramStatus.idle:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Not verified yet. Telegram shares only your own number, and it '
              'is stored masked.',
              style: TextStyle(fontSize: 13, color: kAuthHint, height: 1.4),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () => state.start(),
                icon: const Icon(Icons.send, size: 18, color: kAuthTeal),
                label: const Text(
                  'Verify with Telegram',
                  style: TextStyle(
                    color: kAuthTeal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kAuthTeal),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }

  Widget _retry({required String message}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          message,
          style: const TextStyle(fontSize: 13, color: kAuthDanger, height: 1.4),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            onPressed: () => state.start(),
            icon: const Icon(Icons.refresh, size: 18, color: kAuthTeal),
            label: const Text(
              'Try again',
              style: TextStyle(color: kAuthTeal, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kAuthTeal),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
