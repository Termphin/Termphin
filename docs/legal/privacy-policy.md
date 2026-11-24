# Privacy Policy

**Last updated: 23 November 2026**

## Summary

Termphin is an SSH client. It is built so that there is as little as possible
for us to collect, and what it does need is described here. This policy covers
the app, the website at termphin.dev and the account page at app.termphin.dev.

- **Your sessions never pass through us.** SSH and SFTP connections go straight
  from your device to your server. We cannot see terminal output, commands,
  files or anything else you do on your servers - except what you choose to
  show Phin, the assistant in Termphin Pro.
- **Everything works without an account.** An account is only needed for
  Termphin Pro. If you never create one, the app stores your data on your
  device and nowhere else.
- **Sync is end-to-end encrypted.** If you turn it on, your machines, keys and
  snippets are encrypted on your device with a passphrase only you know. We
  store the result and cannot read it.
- **Push notifications pass through, they are not kept.** The text a server
  sends to your phone goes through our relay to Google or Apple for delivery
  and is not stored.
- **Live status is end-to-end encrypted.** Which sessions are open on your
  servers reaches your other devices through our server sealed with a key
  only your devices and that server hold, and is kept in memory only.
- **Phin sees only what it is asked about.** When you ask Phin, the assistant
  in Termphin Pro, for help, your question and what it reads on your server
  go to an AI model to answer it, with names, addresses and secrets replaced
  first. Nothing is kept by us, and you can turn Phin off.
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
notification on its way to your phone (section 6). With live status on, the
sessions on your servers reach us only encrypted (section 6). When you ask
Phin for help, what it reads on your server passes through us to an AI model,
with names, addresses and secrets replaced first (section 7).

## 4. Your account (only for Termphin Pro)

You need an account only to buy and use Termphin Pro. You can sign in with
Google, with Apple, with GitHub, or with an email address and a password.
Accounts are run on **Firebase Authentication** by Google.

What an account holds:

- your email address, and whether you have confirmed it
- how you sign in (Google, Apple, GitHub or email)
- the name and profile picture your Google, Apple or GitHub account provides,
  if any
- a random account identifier
- when the account was created and last signed in
- whether it has Pro, and until when

The app shows that profile picture as your account's avatar: it downloads it
once from Google's or GitHub's servers and keeps a copy on your device, which
signing out deletes.

Your password, if you use one, is held by Firebase Authentication as a salted
hash; we never see it.

**Signing in on a computer.** Termphin on a computer signs in with a code you
type into the account page. While that code is open - at most ten minutes -
we keep which kind of computer asked (macOS, Windows or Linux) and the
country its request came from, read from its network address, and show them
to you on the page before you confirm, so you can tell whether it was you.
The address itself is only held in memory, for up to ten minutes, to limit
how many sign-ins one address can start; it is never written down. The
computer's kind and country are deleted with the code.

**Deleting your account** is in the app under Settings, Account. It deletes
the account itself and, at once, everything stored for it: sync data, device
registrations, server relay keys and your customer record at RevenueCat
(section 8). It does not cancel a subscription, which the store bills -
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

## 6. Push notifications and live status (Termphin Pro)

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

### Live status

With live status on, your devices show which of your servers are online and
which sessions are open on them, without connecting. It is off until you
turn it on in Settings, Account, and works on servers that have push on.

What it involves:

- **Each server** gets a second key, written next to its relay key in your
  home directory, which your devices also keep. On a Linux or macOS server
  the app also adds two lines marked `termphin-presence` to your crontab, so
  the server reports every five minutes and after a restart even with no
  session open; turning live status off removes them.
- **A report** - the names of the sessions, when they started, which of
  your devices are attached to them (the name and type of each device), what
  each one is doing and the name of the program running in it - is sealed
  on the server with that key before it leaves, and opened only on your
  devices. Our server passes it on and cannot read it.
- **What our server does see** is the identifier of the relay key a report
  comes with, which account each of your devices signs in as, whether a
  server says it is online, when servers and devices connect and leave, the
  size and timing of reports, and the network addresses of the connections
  while they are open. It keeps this in memory only, never on disk, and
  forgets a server 12 minutes after its last report. Its logs do not record
  your sessions or your account.
- **Our server** is run by us on a machine at Hetzner in Nuremberg, Germany.

## 7. Phin, the assistant (Termphin Pro, beta)

Phin is an assistant over the terminal: you tell it what is wrong, it looks
around the server with read-only commands, explains what it found and
proposes changes, which run only when you tap Run. It comes with Termphin
Pro, is on by default there, and can be turned off under Settings, Phin AI;
off, it sends nothing.

What it involves:

- **What Phin sends.** Only while you are using it: your question and the
  conversation so far; what the read-only commands it runs on your server
  print, and the files it reads there; the text on the terminal's screen when
  it looks at it; and, if memory is on, the notes it saved about that server.
  Phin will not read files that usually hold secrets, such as private keys.
- **What is replaced first.** On your device, before anything leaves it, host
  names, IP addresses, usernames, email addresses and anything that looks
  like a password, key or token are replaced with placeholders such as
  `HOST_1` or `[SECRET_1]`. They are put back only on your device. Something
  sensitive that does not look like any of these can still get through, so
  do not ask Phin about anything you would not share.
- **Commands run from your device**, over your own SSH connection, never from
  our servers. Nothing that changes the server runs until you approve it.
- **The way it goes.** Your device sends the conversation, with your
  account's sign-in token, to our server (on the machine at Hetzner in
  Germany, section 6), which checks that the account has Pro and is within
  its limits, and passes it on to **OpenRouter**, which sends it to
  **Anthropic**'s Claude model for the answer. Our server does not store
  conversations or write them to its logs. It keeps how much each account
  spent this week, under a one-way hash of the account identifier, until the
  week ends, and the network address of a request briefly in memory, to
  limit how often one address can call it.
- **OpenRouter and Anthropic** process the conversation to produce the answer
  and do not use it to train models. Anthropic may keep it for up to 30 days
  to detect abuse, then deletes it.
- **Memory.** With memory on, Phin can save short notes about a server - what
  runs there, where its logs are - so you do not have to explain again. They
  are kept only on your device, with the app's other secrets, and you can
  see, delete or turn them off under Settings, Phin AI.

## 8. Purchases

Termphin Pro is sold through **Google Play** and the **App Store**. The store
takes the payment; we never see your card or billing details.

Purchases are managed by **RevenueCat**, which receives your account
identifier and the store's record of the purchase - product, price, currency,
country, dates and renewal status - so it can tell the app and our backend
whether your account has Pro. We keep only that answer and its expiry date
with your account (section 4).

## 9. Analytics and crash reports, only if you allow them

Once you have used Termphin for a couple of days, it asks you once whether to
share anonymous usage data and crash reports, with "Sure" and "No thanks"
side by side. Nothing is ticked in advance, and leaving the question
unanswered counts as no. Until you answer yes, neither is started and nothing
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

## 10. The website

termphin.dev is a static site: pages, screenshots, the changelog and this
document. There are no accounts on it and nothing to sign in to; that is the
account page, below.

**No cookies, no tracking.** The site sets no cookies and runs no analytics
or tracking scripts. The one thing it keeps in your browser is a list, in
local storage, of the announcements at the top of the page you have closed, so
they stay closed; it never leaves your browser. That is why there is no cookie
banner: Article 5(3) of the ePrivacy Directive does not ask for consent to
store what is strictly needed for something you asked for.

**Server logs.** Cloudflare, which hosts the site, keeps ordinary request
logs - IP address, time, requested address, user agent - for a short period,
for security and abuse handling. It shows us traffic only in aggregate, such
as request counts per page and country; we never look at individual visitors.

**The account page.** app.termphin.dev is your Termphin account in a browser:
you can create an account, see your Pro status and what is synced, revoke a
server's notification key, change your email address or password, and delete
the synced copy or the whole account. It works with the same account data the
app does (sections 4 to 8) and keeps nothing of its own, apart from codes for
Pro you redeem there: which account redeemed a code, its email address, when,
and until when it gave Pro, kept on Cloudflare with the code; ask us to delete it at any time. Your browser stores
the sign-in session and your choice of light or dark theme; both are strictly
needed for what you asked for, so there is no cookie banner here either. The
page runs no analytics. Its request logs are kept as described above.

Before you sign in, create an account or ask for a password reset with an
email address, Cloudflare Turnstile checks that you are a person and not an
automated script. For that check Cloudflare looks at signals from your
browser and connection, under its own privacy policy; it is not used to track
you and is not linked to your account. Deleting the synced copy from the page
passes through a small Cloudflare service that hands the request to our
backend and keeps nothing.

## 11. Legal basis for processing

- **Your account, sync, push notifications, live status, Phin and purchases**
  (sections 4 to 8)
  are processed because they are needed to provide Termphin Pro, which you
  asked for: performance of a contract, Article 6(1)(b) GDPR.
- **Analytics and crash reports** (section 9) are processed on your
  **consent**, Article 6(1)(a) GDPR. Withdrawing it in Settings does not
  affect processing before.
- **Keeping the relay from being abused** - limiting how often a key can
  send - and **keeping automated sign-ins off the account page** (the
  Turnstile check, section 10) are in our **legitimate interest** in a service
  that works for everyone, Article 6(1)(f) GDPR.

## 12. How long it is kept

| Data | Kept |
| --- | --- |
| Account, device registrations, relay keys | Until you delete them or your account |
| Sync data | Until you delete it or your account; 12 months after Pro ends, with an email a month before |
| A relay key you revoke, or a device that turns push off | Deleted at once |
| A notification on its way to your phone | Not kept |
| A server's live status | In memory only, until 12 minutes after its last report |
| A conversation with Phin | Not kept by us; up to 30 days at Anthropic |
| What an account spent on Phin this week | Until the week ends |
| Phin's notes about your servers | On your device, until you delete them |
| RevenueCat's purchase record | Until you delete your account |
| Analytics events | 2 months |
| Crash reports | 90 days |

The stores keep their own records of purchases under their own policies. Data
on your device stays there until you delete it or uninstall the app.

## 13. Who else is involved

| Provider | What for | Where the data is |
| --- | --- | --- |
| Google (Firebase Authentication, Cloud Firestore, Cloud Functions, Cloud Messaging) | Accounts, sync, push | Firestore and Functions in the EU; Authentication and Cloud Messaging global |
| Google (Analytics for Firebase, Crashlytics) | Analytics and crash reports, if you allow them | United States and other countries |
| Apple (Apple Push Notification service) | Delivering push notifications to iPhones | United States and other countries |
| RevenueCat | Managing Pro purchases | United States |
| Resend | Sending the one email we send: the notice before a synced copy is deleted | United States |
| Google Play, App Store | Selling Pro; their own terms apply | - |
| GitHub | Signing in with GitHub, if you choose it; its own terms apply | United States |
| Cloudflare | Hosting, CDN and DNS for the website and the account page; the Turnstile check on the account page | Global |
| Hetzner | The machine our live status and Phin servers run on | Germany (EU) |
| OpenRouter | Passing Phin's requests to the AI model | United States |
| Anthropic | The AI model that answers Phin's requests | United States |

Where data goes to the United States, the transfer relies on the EU-US Data
Privacy Framework where the provider is certified under it, and otherwise on
the European Commission's standard contractual clauses. We do not sell
personal data or share it for advertising, and there are no advertising SDKs
in the app.

The servers you connect to are yours, not ours. Whatever happens to data on
them is governed by whoever runs them.

## 14. Your rights

If you are in the EEA or the UK, the GDPR gives you the right to:

- **access** the personal data we hold about you
- **rectify** it if it is inaccurate
- **erase** it - deleting your account in the app does this for everything in
  sections 4 to 8, and deleting the synced copy does it for section 5
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

## 15. Security

Credentials on the device are encrypted as described in section 2, and synced
data is encrypted before it leaves the device (section 5). SSH and SFTP are
encrypted by the SSH protocol itself, and everything the app sends to us or
to our providers goes over TLS. A relay key's secret is stored only as a hash.
The app can be locked with a PIN or biometrics.

No system is perfectly secure. If a breach affects your personal data and is
likely to put your rights at risk, we will notify the supervisory authority
within 72 hours and tell you where the law requires it.

## 16. Children

Termphin is a developer tool and is not directed at children. We do not
knowingly collect personal data from anyone under 16. If you believe a child
has given us personal data, write to us and we will delete it.

## 17. International users

Termphin is published from Poland and available worldwide. Wherever you live,
the practices in this policy apply to you. Depending on your country you may
have additional rights under local law; nothing here is meant to limit them.

## 18. Changes to this policy

When this policy changes, the date at the top changes with it, and the
current version is always at https://termphin.dev/privacy. Material changes
to what we collect are announced in the app before they take effect, and if a
change needs your consent we ask again rather than assume the old answer
still applies.

## 19. Contact

Questions, requests or complaints: **contact@termphin.dev**
