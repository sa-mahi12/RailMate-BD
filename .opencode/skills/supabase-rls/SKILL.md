---
name: supabase-rls
description: Hosted Supabase RLS/auth/storage discipline
---

# Hosted Supabase RLS/auth/storage discipline

Do not run local DB. SQL changes are draft until coordinator approval; explicit RLS+grants on every new exposed table; no service-role in app or Git. Test two accounts, anon and cross-owner access. Security invoker functions are preferred; booking RPC is callable only by service_role from verified Edge Function. Never auto-run db reset or migrations.
