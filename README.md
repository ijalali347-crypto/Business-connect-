# Business Connect

Business networking app connected to the Jalali Tech Supabase project. App-specific tables are named bc_profiles and live in bc_private; existing project tables are not modified.

## Features
- Email/password accounts with email confirmation.
- Public business profiles, search, country/industry filters, and touch swipe discovery.
- Optional contact visibility. Hidden email/phone values are stored separately from public profiles.
- Private message requests: at most three total messages from the initiator until the receiver accepts. A declined request cannot be reopened by the sender.
- Receiver-only accept/decline; accepted conversations allow both users to reply.
- Blue tick applications and founder-only approve/reject/remove controls.
- Red founder badge reserved for one server-assigned profile.
- Manual refresh controls for inbox and conversations. Saved connections remain device-local.

## Founder activation
No account is automatically promoted. After the owner creates and confirms their account, verify their account ID and assign it through trusted backend administration to bc_private.admins. Set founder=true on the matching public.bc_profiles row. Neither public forms nor profile-edit payloads can assign permissions or badges. Never use first-signup, matching a display name, or user-editable metadata for admin authorization.

## Authentication configuration
Email/password is enabled and email confirmation is required on the existing project. Confirmation emails and public signup availability depend on its SMTP configuration. Add the GitHub Pages URL to the allowed Auth redirect URLs, preserving existing URLs for other apps. This integration does not change the shared project's authentication settings. Users can confirm using the email link and return to sign in; the site also supports signup OTPs if the configured email template includes a code.

## Deployment
GitHub Pages workflow deploys index.html. The Supabase client is pinned to 2.57.4 with a Subresource Integrity hash. Only the publishable key is present in frontend source.

## Validation
Executed rollback SQL authorization tests for the fourth-message limit, receiver-only acceptance, replies after acceptance, decline enforcement, outsider privacy, hidden contacts, unauthorized badge changes, and admin approve/remove. API checks confirmed public profile reads and anonymous admin-call rejection. Security advisor returned no findings. JavaScript syntax checked; browser interaction and confirmation-email delivery are not verified.

## Remaining
Paid verification, protected identity-document uploads, and online presence are not implemented. Verification remains a manual founder decision, with an audit trail. Profile discovery currently fetches the newest 1000 profiles and conversation history the newest 200 messages.
