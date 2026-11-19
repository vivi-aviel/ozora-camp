# Ozora Camp

- `index.html` – the customer website (Hebrew / English): photos, prices, live availability, booking requests.
- `admin/` – the private management app (login required): bookings, requests, occupancy, Katalin settlement, profit dashboard.
- `supabase/setup.sql` – database tables, security rules and starting data. Run once in Supabase → SQL Editor.
- `.github/workflows/keepalive.yml` – pings the database every 3 days so the free Supabase project is not paused.

Customer data lives only in Supabase, never in this repository. The key in the code is the public
"publishable" key; all business data is protected by row-level security and is readable only by the admin login.
