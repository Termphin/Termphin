# Privacy Policy

**Last updated: 22 September 2026**

## Summary

Termphin is an SSH client that runs on your phone. It is built so that there
is almost nothing for us to collect. This policy covers both the app and the
website at termphin.dev.

- **Your servers, credentials and keys never reach us.** Profiles, passwords,
  private keys and snippets are stored on your device only. There is no
  Termphin account and no Termphin server to sign in to.
- **We cannot see your sessions.** SSH and SFTP connections go straight from
  your phone to your server. Nothing is relayed or proxied through us, so
  terminal output, commands, transferred files and hostnames are not
  something we could read even if we wanted to.
- **Analytics are off until you turn them on.** If you allow them, the app
  sends a short, fixed list of named events - which screen you opened, which
  setting you changed, whether a connection succeeded - and no more. No screen
  recording, no keystrokes, no automatic tracking of anything.
- **The website sets no cookies.** termphin.dev stores nothing on your device,
  which is why it has no cookie banner. Visits are counted in a way that
  discards your IP address and cannot recognise you tomorrow.
- **No ads, no advertising identifiers, no data sold or shared for marketing.**
- **You can change your mind at any time** in Settings, and it takes effect
  immediately.

The rest of this document is the detail behind those six points.

## 1. Who is responsible for your data

The controller of any personal data described here is:

**Mikołaj Badyl**
Email: contact@termphin.dev

For anything in this policy, including requests about your rights, write to
that address. We have not appointed a Data Protection Officer, as we are not
required to.

## 2. What stays on your device

The following never leaves your phone unless you deliberately export or share
it yourself:

| Data | Where it is kept |
| --- | --- |
| Connection profiles (host, port, username, labels, tags) | App storage on the device |
| Passwords, private keys and key passphrases | App storage, encrypted (see below) |
| Snippets, snippet run history and their output | App storage on the device |
| Terminal settings, themes, toolbar and dock layout | App storage on the device |
| App lock PIN state and biometric preference | App storage and the Android Keystore |
| Files you download over SFTP | The Downloads folder or a folder you pick |

Credentials are not stored in plain text. Every secret is sealed with
authenticated encryption under a random 256-bit master key, and that master
key is held by the Android Keystore, which is backed by the device's secure
hardware where the device provides it.

Android's cloud backup is disabled for the app (`allowBackup="false"`), so the
system does not copy this data off the device either.

## 3. What we never receive

Termphin does not operate any server that your sessions pass through. As a
consequence, we do not receive and cannot produce:

- the hostnames, IP addresses or ports you connect to
- your usernames, passwords, private keys or passphrases
- anything typed into or printed by a terminal session
- the contents, names or paths of files browsed or transferred over SFTP
- the contents of your snippets or their output

This is a property of how the app is built, not a promise about how carefully
we handle such data. There is no copy of it on our side to handle.

## 4. Analytics, and only if you allow them

The first time you run Termphin you are asked whether to share anonymous usage
data. The answer is stored on your device. Until you answer yes, the analytics
SDK is not started at all: nothing is sent, and nothing - including the random
identifier described below - is written to your device. If you answer no, or
close the question without answering, it is never started.

If you allow it, we use **PostHog** on their **EU-hosted** infrastructure
(`eu.i.posthog.com`). We collect:

**Events.** This is the complete list. The app sends these and nothing else:

| Event | Sent when |
| --- | --- |
| `app_opened` | The app starts |
| `screen_viewed` | A screen is opened |
| `setting_changed` | A preference is changed |
| `profile_created` | You add a connection profile |
| `connection_success` | A connection is established |
| `connection_failed` | A connection attempt does not come up |
| `connection_dropped` | An established connection is lost |
| `session_resumed` | A persistent remote-agent session is reattached |
| `review_prompt_requested` | The app asks Google Play to show its rating dialog |
| `review_store_opened` | You open the store listing from Settings |

**Event properties.** Some events carry a few extra fields describing the
*shape* of what happened. Like the events themselves, the field names are a
fixed list built into the app:

| Property | What it is | Example values |
| --- | --- | --- |
| `screen` | Which screen was opened, as one of our own names | `home`, `settings`, `known_hosts` |
| `setting` | Which preference was changed, by its storage key | `terminal_font_size`, `theme_mode` |
| `value` | Its new value, when that value is a single number, flag or option name. Never a value you typed yourself - a list reports only how many entries it has | `14`, `true`, `dark` |
| `reason` | Why a connection failed, as one of a fixed set of categories | `auth_failed`, `timeout`, `host_unreachable` |
| `auth_method` | Which authentication method the profile uses | `password`, `privateKey`, `none` |
| `multiplexer` | Whether the session was backed by the remote agent | `termphin`, `none` |
| `via_jump_host` | Whether the connection went through a bastion | `true`, `false` |
| `used_fallback` | Whether an alternative address was used instead of the first one | `true`, `false` |
| `fallback_count` | How many alternative addresses the profile has | `0`, `2` |
| `port_forwards` | How many port-forwarding rules the profile has | `0`, `1` |
| `retry` | Whether this was an automatic retry rather than a first attempt | `true`, `false` |
| `duration_ms` | How long the connection attempt took, in milliseconds | `2100`, `41000` |
| `agent_installed` | Whether this connection had to upload the remote agent first | `true`, `false` |
| `lost_via` | How a lost connection was noticed, as one of a fixed set of categories | `keepalive`, `probe`, `transport` |
| `downtime_ms` | How long a lost connection took to come back, in milliseconds | `3400`, `62000` |
| `in_place` | Whether a reconnect continued the terminal on screen instead of redrawing it | `true`, `false` |

No event and no property carries a hostname, IP address, port, username, file
name, path, command, snippet, profile name or error message. Counts and
category names are all that is sent about a connection; the addresses that
failed stay on the device, in the connection log you can see on screen.

**Technical properties** attached automatically by the PostHog SDK: a randomly
generated identifier for the installation, app version, device model, operating
system version, locale and timezone. The identifier is not your advertising ID
and is not linked to any account, because there is no account.

**Crash and error reports.** Unhandled Flutter and platform errors are sent,
which includes the error message and the stack trace. Stack traces refer to
Termphin's own code. They are sent only while analytics are on.

Everything that PostHog can automatically capture is switched off: autocapture,
automatic screen views, session replay, rage clicks, application lifecycle
events, feature flags, push events and surveys. Nothing observes the app on its
own; the `screen_viewed` and `setting_changed` events above are sent by the app
itself, at the points listed, and are the entire extent of it. The app also
strips the `$ip` property before events leave the device, and IP discarding is
enabled on the PostHog project itself, so event records are not tied to your
network address.

**Turning it off.** Settings has a switch for it. Turning it off stops
collection immediately, without restarting the app.

## 5. The website

termphin.dev is a static site: pages, screenshots, the changelog and this
document. There are no accounts, no forms and nothing to log in to. The rest of
this policy describes the app, and the website is not the app, so it gets its
own section.

**Nothing is stored on your device.** The site sets no cookies and writes
nothing to local or session storage - not for analytics, not for preferences,
not at all. That is why there is no cookie banner: Article 5(3) of the ePrivacy
Directive asks for consent before information is stored on or read from your
device, and the site does neither.

**Visits are counted without identifying you.** The same provider as the app,
PostHog on EU infrastructure, runs on the site in its cookieless mode and in a
separate project from the app's, so nothing on the website can be joined to
anything in the app. Your IP address is discarded before an event is stored and
is never written down; it is used only in passing, with your browser's user
agent, to derive a hash that tells one visitor from another within a single day.
That hash is re-salted every day, so it cannot follow you from one day to the
next. A return visit tomorrow is a new visitor as far as we can tell, which is a
limitation of our own numbers and the point of the arrangement.

What a page view records: the address of the page on this site, the site that
referred you if your browser sent one, device type, browser, operating system
and language. A matching event is recorded when you leave the page, so that a
visit has a length. That is the whole list - there is no event for clicking
anything, and no button on this site reports that you pressed it.

Session replay, surveys, heatmaps, autocapture and click tracking are off here,
as they are in the app.

**Server logs.** The site is served by our hosting provider, which keeps
ordinary web-server logs - IP address, timestamp, requested address, user agent
- for a short period, for security and abuse handling. We do not analyse them
and do not combine them with anything above.

## 6. Legal basis for processing

**In the app**, the analytics and error reports in section 4 are processed on
the basis of **your consent**, under Article 6(1)(a) GDPR. You may withdraw
consent at any time in Settings; withdrawal does not affect the lawfulness of
processing before it.

**On the website**, the measurement in section 5 is processed on the basis of
our **legitimate interests**, under Article 6(1)(f) GDPR - knowing which pages
are read and whether the download link is followed, using a method that cannot
identify a visitor, cannot follow one across days and stores nothing on the
device. We consider that this does not override your interests precisely
because of those limits. You may object to it at contact@termphin.dev.

Consent under Article 5(3) of the ePrivacy Directive is not relied upon on the
website, because nothing is stored on or read from your device there.

There is no other processing, so no other legal basis is relied upon.

## 7. How long it is kept

Analytics events and error reports are kept for **12 months** from the date of
the event, and deleted afterwards. The same limit applies to the website events
in section 5. You can also ask us to delete them sooner - see section 9.

Server logs are kept by our hosting provider for a short period and then
discarded on their schedule, not ours.

Data stored on your device stays there until you delete it or uninstall the app.
Uninstalling removes it. Nothing is stored on your device by the website, so
there is nothing there to expire.

## 8. Who else is involved

| Processor | Role | Location |
| --- | --- | --- |
| PostHog | Analytics and error reporting, for both the app and the website | EU (Germany) |
| Railway | Website hosting and server logs | EU (Warsaw) |
| Cloudflare | Website CDN and DNS, in front of the hosting | Global edge network |

That is the entire list. We do not sell personal data, we do not share it for
advertising or profiling, and there are no advertising SDKs in the app.

The app talks to no one but PostHog, and PostHog processes its data on EU
infrastructure, so nothing from the app leaves the European Economic Area.

The website is hosted in the EU and fronted by Cloudflare, whose network is
global: a request may be handled by an edge location outside the EEA, depending
on where you are. That transfer is covered by the European Commission's
standard contractual clauses in Cloudflare's data processing addendum. If any of
this changes, this policy will be updated before the change takes effect.

Note also that the servers you connect to are yours, not ours. Whatever
happens to data on them is governed by whoever runs them.

## 9. Your rights

If you are in the EEA or the UK, the GDPR gives you the right to:

- **access** the personal data we hold about you
- **rectify** it if it is inaccurate
- **erase** it
- **restrict** or **object to** its processing
- receive it in a portable form
- **withdraw consent** at any time
- **lodge a complaint** with a supervisory authority

Requests go to contact@termphin.dev and are answered within one month. In
Poland the supervisory authority is the President of the Personal Data
Protection Office (Prezes Urzędu Ochrony Danych Osobowych, uodo.gov.pl); if you
live elsewhere in the EEA you may also complain to your own national authority.

One practical caveat about access and erasure requests: analytics events are
tied to a random installation identifier and nothing else, so to act on such a
request we need that identifier from you. Uninstalling the app or clearing its
data severs the link permanently, and after that we have no way to find the
events that came from your device. They are not kept indefinitely because of
that - the 12-month limit in section 7 applies to them either way.

## 10. Security

Credentials are encrypted at rest as described in section 2. SSH and SFTP
connections are encrypted by the SSH protocol itself. Analytics are sent over
HTTPS. The app can be locked with a PIN or biometrics.

No system is perfectly secure, and the security of your servers also depends on
how they are configured and on the device the app runs on. If a data breach
affects your personal data and is likely to result in a risk to your rights, we
will notify the supervisory authority within 72 hours and inform you where the
law requires it.

## 11. Children

Termphin is a developer tool and is not directed at children. We do not
knowingly collect personal data from anyone under 16. If you believe a child
has provided personal data, write to us and we will delete it.

## 12. International users

Termphin is published from Poland and is available worldwide. Wherever you
live, the practices in this policy apply to you. Depending on your country you
may have additional rights under local law; nothing here is intended to limit
them.

## 13. Changes to this policy

If this policy changes, the date at the top changes with it, and the current
version is always published at https://termphin.dev/privacy. Material changes
to what we collect will be announced in the app before they take effect. If a
change requires consent, we will ask again rather than assume the old answer
still applies.

## 14. Contact

Questions, requests or complaints: **contact@termphin.dev**
