// Example public runtime config for the RailMate BD website.
//
// The deploy workflow writes the real `assets/config.js` from the repository
// variables SUPABASE_URL and SUPABASE_ANON_KEY (Settings → Secrets and
// variables → Actions → Variables). `config.js` is gitignored so no key is
// committed; the anon key is public by design and RLS protects every row.
//
// For a local preview: copy this file to `assets/config.js` and fill both
// values from the Supabase dashboard (Project Settings → API).
window.RAILMATE_CONFIG = {
  SUPABASE_URL: 'https://YOUR-PROJECT.supabase.co',
  SUPABASE_ANON_KEY: 'YOUR-ANON-KEY',
  SITE_BASE: 'https://sa-mahi12.github.io/RailMate-BD',
};
