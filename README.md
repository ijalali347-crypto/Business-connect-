# Business Connect

Responsive business discovery preview with grid and touch swipe browsing, relevant verified-first search, industry and meeting-country filters, local saved connections, and editable local profiles with optional email and WhatsApp visibility.

All example people and businesses are fictional. Profile creation is device-local, not registration. Messaging, identity review, verification applications and payments are explicitly unavailable.

## GitHub Pages
In Settings → Pages, select GitHub Actions as the build source. The included workflow deploys index.html on pushes to main. If the initial workflow fails before Pages is configured, rerun it after selecting GitHub Actions.

## Production work remaining
Connect secure authentication and a database with per-user access rules; implement shared profiles, conversations, blocking and reporting; add an admin verification queue and protected document storage; choose pricing and integrate a payment provider with validated webhooks. Only approved verification records may grant a badge. Preserve relevance when ordering verified results.

## Validation
JavaScript syntax checked with Node. Browser interaction and deployment have not been verified.
