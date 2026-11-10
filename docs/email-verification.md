# Email verification

Email/password registration and sign-in require a code sent by Supabase Auth. Configure the Supabase project before deploying:

1. Enable email confirmations in Authentication → Providers → Email. The server refuses to issue a session if sign-up returns an immediate session.
2. Configure a production SMTP provider and sender in Supabase Auth. The default email service is intended for limited testing.
3. Edit both the Confirm signup and Magic Link email templates to include `{{ .Token }}` as the verification code. Set an appropriate OTP expiry and review Supabase rate limits. The UI accepts numeric codes of 6–8 digits.
4. Test registration and sign-in with a mailbox you control, including incorrect and expired codes. Supabase may limit how frequently a message can be resent. To request another sign-in code, return to the credentials form and submit it again. For an unconfirmed registration, submit the registration form again with the same details.

No application session is issued until code verification and password authentication succeed. Google sign-in uses Google's identity verification. Previously confirmed accounts are asked for a code at their next email/password sign-in; existing application sessions continue until they expire or are revoked. The API's IP limiter is process-local: use shared rate limiting at the gateway for multiple instances. Provider-level OTP rate limits and expiry also apply.
