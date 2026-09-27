#!/usr/bin/env bash
set -Eeuo pipefail
bash scripts/check_governance.sh
command -v gh >/dev/null || { echo 'gh CLI missing'; exit 2; }
login="$(gh api user --jq .login)"
id="$(gh api user --jq .id)"
name="$(git config user.name)"
email="$(git config user.email)"
expected="${id}+${login}@users.noreply.github.com"
if [ "$email" != "$expected" ]; then
  echo "Git email does not match account noreply. If intentionally using verified email, validate with gh api user/emails before overriding." >&2
  exit 3
fi
[ "$name" = "$login" ] || { echo "Git name must be authenticated login ($login) under default policy" >&2; exit 4; }
if git diff --cached --name-only | grep -E '(^|/)(\.env|app\.env\.json|.*\.jks|.*\.keystore|.*\.pem|.*\.p12|.*\.pfx)$' ; then
  echo 'SECRET-LIKE FILE STAGED; STOP' >&2; exit 5
fi
if git diff --cached --no-ext-diff | grep -Ei '(SUPABASE_SERVICE_ROLE_KEY[[:space:]]*[:=][[:space:]]*[A-Za-z0-9]{12}|sk-or-v1-[A-Za-z0-9]{10}|AGENTROUTER_API_KEY[[:space:]]*[:=][[:space:]]*[A-Za-z0-9]{12})' ; then
  echo 'SUSPECTED SECRET/ROLE STAGED; INSPECT' >&2; exit 6
fi
printf 'PRE-COMMIT GUARD passed for login %s. This scan is a minimum, not a guarantee.\n' "$login"
