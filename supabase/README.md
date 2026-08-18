# Para Supabase setup

The Flutter app uses this mobile callback URL:

`para://auth-callback/`

Before testing email confirmation or password recovery, add that exact URL in
Supabase Dashboard under **Authentication > URL Configuration > Redirect URLs**.

Deploy the authenticated account-deletion function with JWT verification:

```sh
supabase functions deploy delete-account
```

The Flutter client stores cloud profile data in the signed-in user's
`user_metadata.profile` field. No profile table or database migration is
required. In-app account deletion becomes available after the `delete-account`
function is deployed.

For production email confirmation and recovery, configure a production SMTP
provider in Supabase Authentication settings.
