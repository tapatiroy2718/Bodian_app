# Bodiana – Bengali wedding planning app

Flutter Android app with a Supabase backend. One app has two separate experiences:

- **Customers:** onboarding, wedding countdown and budget, event planner with Done / Not done / Skip checklists, vendor marketplace with search and filters, vendor profiles, packages, venue details, wishlist and comparison, booking requests, cancellations, reviews and live notifications.
- **Vendors:** business profile, private verification documents, services and packages, venue details, photos, availability calendar, booking requests (accept / reject / cancel / complete), reviews and a dashboard.

The backend is a real database with Row Level Security. Customers and vendors can only see their own data. Only verified vendors appear in the marketplace, and vendors cannot verify themselves.

```
lib/
  auth/        welcome, login, register, Google sign-in, password reset, role routing
  customer/    home, explore, service detail, booking form, my wedding, wishlist, bookings, profile
  vendor/      onboarding, dashboard, requests, services + editor, calendar, verification, reviews
  shared/      notifications, account settings, account deletion
  core/        theme, widgets, data helpers, config
supabase/migrations/0001_bodiana_schema.sql   ← the whole database (run once)
.github/workflows/build-android.yml            ← builds the APK + Play Store bundle
.github/workflows/create-keystore.yml          ← creates your Play Store signing key (run once)
branding/                                       ← app icons, Play Store icon and feature graphic
```

---

## Step 1 – Create the Supabase backend (15 min)

1. Go to <https://supabase.com>, sign in, then **New project**. Pick the **Mumbai (ap-south-1)** region and save the database password somewhere safe.
2. Open **SQL Editor → New query**. Paste the whole of `supabase/migrations/0001_bodiana_schema.sql` and click **Run**. You should see "Success". It creates every table, security rule, storage bucket and booking function.
3. **Authentication → URL Configuration → Redirect URLs → Add URL:** `com.bodiana.app://login-callback`
4. **Authentication → Sign In / Providers → Email:** leave **Confirm email** on. New users get a link; tapping it on their phone opens the app.
5. **Project Settings → API** (or **API Keys**): copy the **Project URL** and the **anon / publishable key**.
   Never put the `service_role` / secret key in the app or on GitHub.

### Google sign-in (optional but recommended)

1. <https://console.cloud.google.com> → create a project → **APIs & Services → OAuth consent screen**. Choose External, then fill in the app name, support email and logo.
2. **Credentials → Create credentials → OAuth client ID → Web application.**
   Under **Authorized redirect URIs**, add `https://YOUR-PROJECT-REF.supabase.co/auth/v1/callback`.
3. Copy the Client ID and Client secret into **Supabase → Authentication → Providers → Google**, then enable it.

### Email sending

Supabase's built-in email is rate-limited (a few emails per hour) and is only meant for testing. Before launch, go to **Authentication → Emails → SMTP Settings** and connect a provider such as Resend, Brevo or Amazon SES.

---

## Step 2 – Build the APK on GitHub (no software needed on your PC)

1. Create a **new private repository** on GitHub, e.g. `bodiana-app`.
2. Upload **everything in this folder**, including the hidden `.github` folder. GitHub Desktop is the easiest way.
   Command line also works:
   ```bash
   git init && git add . && git commit -m "Bodiana app"
   git branch -M main
   git remote add origin https://github.com/YOUR-NAME/bodiana-app.git
   git push -u origin main
   ```
3. In the repo, go to **Settings → Secrets and variables → Actions → New repository secret** and add:
   | Name | Value |
   |---|---|
   | `SUPABASE_URL` | your Project URL, e.g. `https://abcd1234.supabase.co` |
   | `SUPABASE_ANON_KEY` | your anon / publishable key |
   | `PRIVACY_POLICY_URL` | (optional) link to your hosted privacy policy |
4. **Actions → Build Android app → Run workflow.** After about 10 minutes, open the finished run and download **bodiana-android-N** at the bottom of the page. It contains the APK.
5. Copy the APK to an Android phone and open it. Allow "install unknown apps" if asked.

Every push to `main` builds a new version automatically, and the version code goes up each time.

### Testing tips

- Register one **customer** and one **vendor** account with two different emails.
- As the vendor, create the business profile, add a service with photos and a package, and upload a document.
- Verify the vendor (Step 4 below). Their service now appears in the customer's Explore tab.
- As the customer, send a booking request. The vendor gets a notification and can accept it. After it's marked completed, the customer can leave a review.

---

## Step 3 – Publish on Google Play

1. **Create your signing key once:** go to **Actions → Create upload keystore (run once) → Run workflow**. Download the artifact and keep `upload.jks` and `SECRETS-README.txt` somewhere safe and offline. Add the four `ANDROID_KEY…` secrets listed in that file, then delete that workflow run.
   **Don't lose this key.** Every future update must be signed with it.
2. Run **Build Android app** again. The download now has `bodiana-N-playstore.aab`, signed with your key.
3. <https://play.google.com/console>: pay the one-time US$25 developer fee and create the app.
   - **Store listing:** use `branding/play_store_icon_512.png`, `branding/play_store_feature_graphic.png` and at least 2 phone screenshots.
   - **Privacy policy:** host `PRIVACY_POLICY.md` (after filling it in) on a public page, such as GitHub Pages or Google Sites, and paste the link.
   - **Data safety:** the app collects name, email, phone number, photos (vendor uploads), and user content (bookings, reviews). Data is encrypted in transit, and users can delete their account in the app (Profile → Delete account).
   - **Account deletion URL:** Play also needs a web link where people can ask for deletion. A page with your support email is enough.
   - **Content rating** questionnaire, **target audience** 18+, **ads:** none.
4. Upload the `.aab` to **Testing → Internal testing** first. New personal developer accounts must run a **closed test with at least 12 testers for 14 days** before Production is unlocked.
5. Enable **Play App Signing** when asked. Google keeps the final key, and your `upload.jks` stays your upload key.

---

## Step 4 – Verifying vendors (operator)

There is no admin screen in this release. Verification is done in the Supabase dashboard:

```sql
-- 1. Vendors waiting for review (with their document count)
select * from admin_pending_vendors;
```

2. Check their documents in **Storage → vendor-documents → <vendor id> → documents**. Only operators and the vendor can open these; customers never can.
3. Approve or reject:

```sql
select admin_review_vendor('VENDOR-UUID', 'verified', null, 'your-name');
select admin_review_vendor('VENDOR-UUID', 'rejected', 'Trade licence photo is unreadable', 'your-name');
```

The vendor gets a notification immediately. Approved vendors' active services show up in the marketplace. Rejected vendors can upload new documents and tap **Request review again**.

---

## Building on your own computer (optional)

Install Flutter (stable) and Android Studio, then:

```bash
flutter create --org com.bodiana --project-name bodiana --platforms android .
python3 scripts/patch_android.py
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=your-key
```

The `android/` folder is generated, not stored in git, so it always matches your Flutter version. `scripts/patch_android.py` sets the app ID (`com.bodiana.app`), name, icon, internet permission and the sign-in deep link.

## Security summary

- RLS is on every table. Bookings, reviews, role choice and verification changes only go through database functions that check who is calling.
- Vendors cannot change their own verification status or ratings; a trigger silently ignores such changes.
- Each service and date can have only one confirmed booking, enforced by a unique index.
- Verification documents sit in a private bucket. Each user can only reach files in their own folder.
- A customer account can never become a vendor, and a vendor can never become a customer.
- Account deletion removes the user and all their data. Deletion is blocked while they have upcoming confirmed bookings.

The database was tested with 76 automated checks covering role changes, cross-account access, double booking, the booking lifecycle, reviews, private documents and account deletion.

## Not in this release (by design)

Online payments, subscriptions, phone OTP, an in-app admin dashboard, and AI features (budget suggestions, recommendations). The database and app structure leave room to add them later. Bengali language support is also planned.
