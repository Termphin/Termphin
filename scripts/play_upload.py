"""Uploads a release AAB to Google Play and releases it on a testing track.

    python3 scripts/play_upload.py <aab> <version> [track]

The version's entry in assets/release_notes.yaml becomes the release notes.
The service account key comes from GOOGLE_PLAY_SERVICE_ACCOUNT_JSON (the JSON
itself, as the release workflow passes it) or, for a local run, from
~/.config/termphin/google-service-account.json. The account needs "Release
apps to testing tracks" in Play Console, nothing more: promoting a build to
production stays a step taken by hand in Play Console.

Needs google-auth and pyyaml.
"""

import json
import os
import re
import sys
from pathlib import Path

import yaml
from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

PACKAGE = "dev.termphin.termphin"
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"
UPLOAD = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}"
LOCAL_KEY = Path.home() / ".config/termphin/google-service-account.json"
NOTES_LIMIT = 500


def credentials():
    """The service account, from the environment first, then the local file."""
    raw = os.environ.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")
    info = json.loads(raw) if raw else json.loads(LOCAL_KEY.read_text())
    return service_account.Credentials.from_service_account_info(
        info, scopes=["https://www.googleapis.com/auth/androidpublisher"]
    )


def release_notes(version):
    """The version's release notes as Play shows them: one line per entry,
    cut at Play's limit on a whole line."""
    entries = yaml.safe_load(Path("assets/release_notes.yaml").read_text())
    entry = next((e for e in entries if str(e.get("version")) == version), None)
    if entry is None:
        sys.exit(f"assets/release_notes.yaml has no entry for {version}")
    lines = []
    for key in ("added", "changed", "fixed", "security", "removed", "deprecated"):
        lines += [f"- {item}" for item in entry.get(key) or []]
    text = ""
    for line in lines:
        candidate = f"{text}\n{line}" if text else line
        if len(candidate) > NOTES_LIMIT:
            break
        text = candidate
    return text


def check(response, what):
    """Stops with Play's own message when [response] failed."""
    if not response.ok:
        sys.exit(f"{what} failed: HTTP {response.status_code}: {response.text[:800]}")
    return response.json()


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    aab, version = Path(sys.argv[1]), re.sub(r"\+.*$", "", sys.argv[2])
    track = sys.argv[3] if len(sys.argv) > 3 else "alpha"
    notes = release_notes(version)
    session = AuthorizedSession(credentials())

    edit = check(session.post(f"{API}/edits", json={}), "opening the edit")["id"]
    with aab.open("rb") as body:
        bundle = check(
            session.post(
                f"{UPLOAD}/edits/{edit}/bundles?uploadType=media",
                data=body,
                headers={"Content-Type": "application/octet-stream"},
                timeout=900,
            ),
            "uploading the bundle",
        )
    code = str(bundle["versionCode"])
    check(
        session.put(
            f"{API}/edits/{edit}/tracks/{track}",
            json={
                "track": track,
                "releases": [{
                    "name": f"{version} ({code})",
                    "versionCodes": [code],
                    "status": "completed",
                    "releaseNotes": [{"language": "en-US", "text": notes}],
                }],
            },
        ),
        "setting the track",
    )
    check(session.post(f"{API}/edits/{edit}:commit", json={}), "committing the edit")
    print(f"{version} ({code}) released on {track}")


if __name__ == "__main__":
    main()
