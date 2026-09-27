---
name: atomic-booking
description: Multi-seat atomic booking and cancellation
---

# Multi-seat atomic booking and cancellation

Use one server transaction, lock sorted seat rows, 1–4 unique seats and one passenger per seat, idempotency UUID, no external call inside SQL transaction. On conflict entire booking fails. Payment is simulated only. Tickets read confirmed snapshot. Cancellation returns seats only if they refer to cancelling booking. Show concurrency tests.
