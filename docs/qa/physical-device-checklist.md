# Physical-device smoke test — RailMate BD (+27)

Status: **NOT PERFORMED.** All previous runtime evidence is emulator-based
(R-21). This document is the owner's checklist; no row may be marked PASS until
it is filled in on a real phone with the build below.

## Session header (fill before testing)

| Field | Value |
|---|---|
| Build number | `+27` (check Settings → About / release manifest) |
| APK file | `RailMate-BD-1.0.0-arm64-v8a.apk` (or universal) |
| APK SHA256 | `____________________________` (from `SHA256SUMS.txt`) |
| Device model | |
| Android version | |
| Test date | |
| Tester | |
| Network | Wi-Fi / mobile data / offline |

Legend: **PASS** = expected result observed; **FAIL** = observed different
result; **BLOCKED** = could not test (say why). "Works" without a screenshot is
not evidence.

## Checklist

| # | Area | Steps | Expected result | Actual result | Screenshot file | Status |
|---|---|---|---|---|---|---|
| 1 | Fresh install | Uninstall any previous build, install +27 APK | Installer completes; app opens on splash → onboarding (first run) | | `01-install.png` | |
| 2 | Registration | Onboarding → Register with a new email + username | Account created; verification screen shown; no fabricated "verified" state | | `02-register.png` | |
| 3 | Email verification | Enter the six-digit token from the inbox | Session verified; late/old token rejected honestly; resend cooldown visible | | `03-email-verify.png` | |
| 4 | Telegram phone verification | Profile → Verify with Telegram (bot must be configured — see `docs/owner/telegram-setup.md`) | Deep link opens Telegram; sharing own number shows *Phone verified — masked* in the app; typing a number is rejected | | `04-telegram.png` | BLOCKED until bot exists |
| 5 | Login | Sign out, sign in with the same account | Home loads with the account's data | | `05-login.png` | |
| 6 | Logout | Profile → Sign out | Returns to Welcome; no session data remains on Home | | `06-logout.png` | |
| 7 | Session restoration | Kill the app, reopen it | Session restored without re-login (splash → Home) | | `07-restore.png` | |
| 8 | Search | Home → From/To/date → Search | Real trip rows from the hosted backend; loading → results; no skeleton stuck forever | | `08-search.png` | |
| 9 | Datepicker | Change the date to today +5 | Results reload for that date; empty date shows empty state, not fabricated rows | | `09-date.png` | |
| 10 | Passenger selection | Choose 2 seats | Seat map shows demo-hold vs available honestly; total equals 2 | | `10-seats.png` | |
| 11 | Payment simulation | Continue to payment, use the simulated method | Clearly labelled simulation; **no real money**; cancel path works | | `11-payment.png` | |
| 12 | Booking | Confirm | Atomic booking succeeds once; seats become booked; duplicate taps cannot double-book | | `12-booking.png` | |
| 13 | Ticket generation | Open the ticket | QR + PDF artifact states **DEMONSTRATION ONLY / NOT VALID FOR TRAVEL** | | `13-ticket.png` | |
| 14 | Cancellation | Bookings → Cancel | Seat released; cancellation confirmed by the server; history updated | | `14-cancel.png` | |
| 15 | File upload | Journey Board → new post with an image | Upload completes; image renders in the feed | | `15-upload.png` | |
| 16 | Journey Board | Open Board | Realtime feed loads; pagination reaches older posts | | `16-board.png` | |
| 17 | Comments | Add a comment | Appears immediately for this client and for a second signed-in client | | `17-comments.png` | |
| 18 | Reactions | React to a post | Count/state update in realtime, survives reload | | `18-reactions.png` | |
| 19 | Ratings | Rate a trip 1–5 | Realtime insert verified (two clients); average/total update | | `19-ratings.png` | |
| 20 | Pagination | Scroll to the end of the board | Cursor pagination loads more, no duplicates, honest end state | | `20-pagination.png` | |
| 21 | Station guide | Home → station card | Guide page opens; station switching works; facilities/overview show demo data | | `21-guide.png` | |
| 22 | Video playback | Guide → Play video | Bundled clip plays (muted autoplay may need the button); pause reflects real state | | `22-video.png` | |
| 23 | Map rendering | Guide → Map | Interactive map with marker; switching stations keeps the map (no blank box); offline shows the honest note | | `23-map.png` | |
| 24 | AI rewrite | Board → Improve Wording (owner key required) | Consent gate; suggestion not auto-applied; failure leaves the draft intact | | `24-ai.png` | BLOCKED until key supplied |
| 25 | Network interruption | Airplane mode during search / board / map | Explicit offline errors, retry available; nothing cached is presented as live | | `25-offline.png` | |
| 26 | Error handling | Wrong password; expired verification token; invalid date | Humanised messages, no stack traces, no secret material, app stays usable | | `26-errors.png` | |

## Closing the test

1. Copy screenshots into the internal evidence folder with the same names.
2. Fill every Actual/Status cell; do not leave blanks.
3. Record the final decision: PASS only for rows actually observed.
4. Update `RailMate-BD-internal/governance/REQUIREMENTS_MATRIX.md` R-21 with the
   device model, date and screenshot references. Physical-device evidence is
   pending until this is done.
