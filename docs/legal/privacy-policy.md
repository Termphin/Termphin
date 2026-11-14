# Privacy Policy

**Last updated: 14 November 2026**

## Summary

Termphin is an SSH client. It is built so that there is as little as possible
for us to collect, and what it does need is described here. This policy covers
the app and the website at termphin.dev.

- **Your sessions never pass through us.** SSH and SFTP connections go straight
  from your device to your server. We cannot see terminal output, commands,
  files or anything else you do on your servers.
- **Everything works without an account.** An account is only needed for
  Termphin Pro. If you never create one, the app stores your data on your
  device and nowhere else.
- **Sync is end-to-end encrypted.** If you turn it on, your machines, keys and
  snippets are encrypted on your device with a passphrase only you know. We
  store the result and cannot read it.
- **Push notifications pass through, they are not kept.** The text a server
  sends to your phone goes through our relay to Google or Apple for delivery
  and is not stored.
- **Analytics and crash reports are off until you turn them on**, and are never
  tied to your account.
- **No ads, no advertising identifiers, no data sold or shared for marketing.**

The rest of this document is the detail behind those points.

## 1. Who is responsible for your data

The controller of the personal data described here is:

**Mikołaj Badyl**
Email: contact@termphin.dev

For anything in this policy, including requests about your rights, write to
that address. We have not appointed a Data Protection Officer, as we are not
required to.

## 2. What stays on your device

Unless you turn on sync (section 5), the following never leaves your device
unless you export or share it yourself:

| Data | Where it is kept |
| --- | --- |
| Machines (host, port, username, name, group, colour) | App storage on the device |
| Passwords, private keys and key passphrases | App storage, encrypted (see below) |
| Snippets, snippet run history and their output | App storage on the device |
| Known host keys | App storage on the device |
| Terminal settings, themes, toolbar and dock layout | App storage on the device |
| App lock PIN state and biometric preference | App storage and the platform keystore |
| Files you download over SFTP | A folder on the device you pick |

Credentials are never stored in plain text. Every secret is sealed with
authenticated encryption under a random 256-bit key held by the platform's
keystore (the Android Keystore or the iOS Keychain), backed by the device's
secure hardware where it has one. On Android the system's cloud backup is
disabled for the app. On iOS a device backup may include the app's storage,
but the key that unseals your credentials is kept on this device only and is
never part of a backup, so a backup holds nothing anyone could read them
from.

## 3. What we never receive

Termphin does not run any server your sessions pass through. We do not
receive, and could not produce:

- the hostnames, IP addresses, ports or usernames you connect with
- your passwords, private keys or passphrases
- anything typed into or printed by a terminal session
- the names, paths or contents of files you browse or transfer
- your snippets or their output

With sync on, your machines, keys and snippets reach us only as encrypted
data we cannot decrypt (section 5). With push on, the two things that do
reach us in readable form are the name you gave a machine and the text of a
notification on its way to your phone (section 6).

## 4. Your account (only for Termphin Pro)

You need an account only to buy and use Termphin Pro. You can sign in with
Google, with Apple, or with an email address and a password. Accounts are
run on **Firebase Authentication** by Google.

What an account holds:

- your email address, and whether you have confirmed it
- how you sign in (Google, Apple or email)
- the name and profile picture your Google or Apple account provides, if any
- a random account identifier
- when the account was created and last signed in
- whether it has Pro, and until when

Your password, if you use one, is held by Firebase Authentication as a salted
hash; we never see it.

**Deleting your account** is in the app under Settings, Account. It deletes
the account itself and, at once, everything stored for it: sync data, device
registrations, server relay keys and your customer record at RevenueCat
(section 7). It does not cancel a subscription, which the store bills -
cancel it in your Google Play or App Store account.

## 5. Sync (Termphin Pro)

Sync keeps your machines, keys, snippets, groups and known host keys the same
on every device signed in to your account. It is off until you turn it on and
choose a passphrase.

**It is end-to-end encrypted.** Your passphrase never leaves your device. It is
stretched into a 256-bit key on the device (PBKDF2-SHA256, 210,000 rounds),
and each item is encrypted with that key (AES-256-GCM) before it is uploaded.
What we store, in **Cloud Firestore** by Google in the EU (`eur3`), is:

- the encrypted items, each under an identifier derived from the key, so the
  identifiers say nothing about what they hold either
- the random salt your key was stretched with, and a small encrypted value
  that lets a new device tell a right passphrase from a wrong one
- when each item last changed, and whether it was deleted

We cannot read any of it, and neither could anyone who obtained a copy from
us. That has a consequence: **if you forget your passphrase, nobody can
recover the synced copy.** Your devices keep their own data; only the cloud
copy is lost, and you can delete it and start sync again.

**Deleting it.** In the app, under Settings, Account, Sync, you can delete
the synced copy at any time, Pro or not. That turns sync off on all your
devices; what is on them stays.

**If Pro ends,** sync pauses and the synced copy is kept, so renewing picks up
where it stopped. It is kept for 12 months after Pro ends. A month before it
is deleted we email you once, to the address of your account.

## 6. Push notifications (Termphin Pro)

With push on, a program on one of your servers - a long command finishing, an
assistant asking for you - can reach your phone while nothing is connected to
that server. It is off until you turn it on.

What it involves:

- **Each phone** with push on registers a notification token from Google
  Firebase Cloud Messaging, stored under your account with the phone's
  platform, so we know where to deliver.
- **Each server** you connect to with push on gets a relay key, written to a
  file in your home directory on that server. We store only a hash of its
  secret, the name you gave that machine in Termphin, a random identifier
  for it, when the key was made and when it last sent something. You can see
  and revoke these keys in the app under Settings, Notifications, Servers.
- **A notification** - its title, its text and the name of the session it
  came from - goes from your server to our relay (a Cloud Function in the EU,
  `europe-central2`), which passes it to Firebase Cloud Messaging and, for
  iPhones, Apple's push service, for delivery. The relay does not store it or
  log it.
- **What a notification says.** A program on your server can ask for a
  notification with any text it chooses. When the Termphin helper announces
  one itself - a long command that finished, a program that stopped and may
  need you - the text is the command's name, never the options typed after
  it, how long it ran and, unless you turn it off under Settings,
  Notifications, the last line it printed. You can also turn either kind
  off there; the relay then sends nothing for it. On a locked phone the
  text stays hidden until you unlock it, where the system allows.

Without Pro, Termphin still shows these notifications while it is connected,
straight from the session, with nothing sent anywhere.

## 7. Purchases

Termphin Pro is sold through **Google Play** and the **App Store**. The store
takes the payment; we never see your card or billing details.

Purchases are managed by **RevenueCat**, which receives your account
identifier and the store's record of the purchase - product, price, currency,
country, dates and renewal status - so it can tell the app and our backend
whether your account has Pro. We keep only that answer and its expiry date
with your account (section 4).

## 8. Analytics and crash reports, only if you allow them

The first time you run Termphin you are asked whether to share anonymous usage
data and crash reports. Until you answer yes, neither is started and nothing
is written for them on your device. You can change your answer in Settings at
any time, and it takes effect immediately.

If you allow it, we use **Google Analytics for Firebase** and
**Firebase Crashlytics**. They receive:

- **what you do in the app, in broad strokes**: which screens you open, which
  settings you change and to what value when it is an option rather than
  something you typed, whether a connection came up or why it failed in one
  of a fixed set of categories, how long it took, and the steps of buying Pro.
  The complete list of events and their fields is in the app's source code, at
  https://github.com/Termphin/Termphin/blob/main/lib/services/analytics/analytics_service.dart
- **crash reports**: the error, the stack trace of the app's own code, and the
  device's state when it happened
- **about the device**: a random identifier for this installation, the app
  version, device model, operating system, language and country

No event carries a hostname, address, port, username, machine name, file name,
path, command or snippet. Analytics are not linked to your account, and the
advertising identifier and ad personalisation are switched off.

## 9. The website

termphin.dev is a static site: pages, screenshots, the changelog and this
document. There are no accounts and nothing to sign in to.

**Nothing is stored on your device.** The site sets no cookies and writes
nothing to local or session storage. That is why there is no cookie banner:
Article 5(3) of the ePrivacy Directive asks for consent before information is
stored on or read from your device, and the site does neither.

**Visits are counted without identifying you.** PostHog, on EU
infrastructure, runs on the site in its cookieless mode. Your IP address is
used only in passing, with your browser's user agent, to derive a hash that
tells one visitor from another within a single day, and is never stored. The
hash is re-salted every day, so it cannot follow you from one day to the
next. A page view records the page, the referring site if your browser sent
one, device type, browser, operating system and language; leaving the page
records how long the visit lasted. Nothing else is recorded.

**Server logs.** Our hosting provider keeps ordinary web-server logs - IP
address, time, requested address, user agent - for a short period, for
security and abuse handling. We do not analyse them.

## 10. Legal basis for processing

- **Your account, sync, push notifications and purchases** (sections 4 to 7)
  are processed because they are needed to provide Termphin Pro, which you
  asked for: performance of a contract, Article 6(1)(b) GDPR.
- **Analytics and crash reports** (section 8) are processed on your
  **consent**, Article 6(1)(a) GDPR. Withdrawing it in Settings does not
  affect processing before.
- **Keeping the relay from being abused** - limiting how often a key can
  send - is in our **legitimate interest** in a service that works for
  everyone, Article 6(1)(f) GDPR.
- **The website's visit counting** (section 9) is in our legitimate interest
  in knowing which pages are read, by a method that cannot identify a visitor
  or follow one across days. You may object at contact@termphin.dev.

## 11. How long it is kept

| Data | Kept |
| --- | --- |
| Account, device registrations, relay keys | Until you delete them or your account |
| Sync data | Until you delete it or your account; 12 months after Pro ends, with an email a month before |
| A relay key you revoke, or a device that turns push off | Deleted at once |
| A notification on its way to your phone | Not kept |
| RevenueCat's purchase record | Until you delete your account |
| Analytics events | 2 months |
| Crash reports | 90 days |
| Website visit counts | 12 months |

The stores keep their own records of purchases under their own policies. Data
on your device stays there until you delete it or uninstall the app.

## 12. Who else is involved

| Provider | What for | Where the data is |
| --- | --- | --- |
| Google (Firebase Authentication, Cloud Firestore, Cloud Functions, Cloud Messaging) | Accounts, sync, push | Firestore and Functions in the EU; Authentication and Cloud Messaging global |
| Google (Analytics for Firebase, Crashlytics) | Analytics and crash reports, if you allow them | United States and other countries |
| Apple (Apple Push Notification service) | Delivering push notifications to iPhones | United States and other countries |
| RevenueCat | Managing Pro purchases | United States |
| Resend | Sending the one email we send: the notice before a synced copy is deleted | United States |
| Google Play, App Store | Selling Pro; their own terms apply | - |
| PostHog | Website visit counting | EU (Germany) |
| Railway | Website hosting | EU |
| Cloudflare | Website CDN and DNS | Global |

Where data goes to the United States, the transfer relies on the EU-US Data
Privacy Framework where the provider is certified under it, and otherwise on
the European Commission's standard contractual clauses. We do not sell
personal data or share it for advertising, and there are no advertising SDKs
in the app.

The servers you connect to are yours, not ours. Whatever happens to data on
them is governed by whoever runs them.

## 13. Your rights

If you are in the EEA or the UK, the GDPR gives you the right to:

- **access** the personal data we hold about you
- **rectify** it if it is inaccurate
- **erase** it - deleting your account in the app does this for everything in
  sections 4 to 7, and deleting the synced copy does it for section 5
- **restrict** or **object to** its processing
- receive it in a portable form
- **withdraw consent** at any time
- **lodge a complaint** with a supervisory authority

Requests go to contact@termphin.dev and are answered within one month. In
Poland the supervisory authority is the President of the Personal Data
Protection Office (Prezes Urzędu Ochrony Danych Osobowych, uodo.gov.pl); if you
live elsewhere in the EEA you may also complain to your own national
authority.

Analytics are not linked to your account, so to act on a request about them we
need the installation identifier from you; uninstalling the app severs the
link for good.

## 14. Security

Credentials on the device are encrypted as described in section 2, and synced
data is encrypted before it leaves the device (section 5). SSH and SFTP are
encrypted by the SSH protocol itself, and everything the app sends to us or
to our providers goes over TLS. A relay key's secret is stored only as a hash.
The app can be locked with a PIN or biometrics.

No system is perfectly secure. If a breach affects your personal data and is
likely to put your rights at risk, we will notify the supervisory authority
within 72 hours and tell you where the law requires it.

## 15. Children

Termphin is a developer tool and is not directed at children. We do not
knowingly collect personal data from anyone under 16. If you believe a child
has given us personal data, write to us and we will delete it.

## 16. International users

Termphin is published from Poland and available worldwide. Wherever you live,
the practices in this policy apply to you. Depending on your country you may
have additional rights under local law; nothing here is meant to limit them.

## 17. Changes to this policy

When this policy changes, the date at the top changes with it, and the
current version is always at https://termphin.dev/privacy. Material changes
to what we collect are announced in the app before they take effect, and if a
change needs your consent we ask again rather than assume the old answer
still applies.

## 18. Contact

Questions, requests or complaints: **contact@termphin.dev**
