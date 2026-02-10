#!/usr/bin/env python3
"""
Distribute the latest TestFlight build to the 'Family' external test group.

Usage:
    python3 scripts/distribute_testflight.py [--build-number BUILD]

If --build-number is omitted, distributes the most recent build.
"""

import json
import time
import sys
import argparse
from pathlib import Path

import jwt
import urllib.request
import urllib.error

# --- Configuration ---
ISSUER_ID = "0abea7d2-dc18-4109-818e-327b3ad1909e"
KEY_ID = "GJU5L8J2YM"
PRIVATE_KEY_PATH = Path.home() / ".appstoreconnect" / "private_keys" / "AuthKey_GJU5L8J2YM.p8"
BUNDLE_ID = "com.johnhoffman.CoParentingApp"
BETA_GROUP_NAME = "Family"


def generate_token():
    """Generate a JWT for App Store Connect API."""
    private_key = PRIVATE_KEY_PATH.read_text()
    now = int(time.time())
    payload = {
        "iss": ISSUER_ID,
        "iat": now,
        "exp": now + 20 * 60,  # 20 minutes
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": KEY_ID})


def api_get(token, url):
    """Make a GET request to the App Store Connect API."""
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def api_post(token, url, data):
    """Make a POST request to the App Store Connect API."""
    req = urllib.request.Request(url, method="POST")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    body = json.dumps(data).encode()
    try:
        with urllib.request.urlopen(req, body) as resp:
            if resp.status == 204:
                return None
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        print(f"  API error {e.code}: {error_body}")
        raise


def find_app(token):
    """Find the app by bundle ID."""
    url = f"https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]={BUNDLE_ID}"
    data = api_get(token, url)
    apps = data.get("data", [])
    if not apps:
        print(f"ERROR: No app found with bundle ID {BUNDLE_ID}")
        sys.exit(1)
    return apps[0]["id"]


def find_beta_group(token, app_id):
    """Find the beta group by name."""
    url = f"https://api.appstoreconnect.apple.com/v1/apps/{app_id}/betaGroups"
    data = api_get(token, url)
    groups = data.get("data", [])
    for g in groups:
        if g["attributes"]["name"] == BETA_GROUP_NAME:
            return g["id"]
    print(f"ERROR: No beta group named '{BETA_GROUP_NAME}' found")
    print("  Available groups:")
    for g in groups:
        print(f"    - {g['attributes']['name']}")
    sys.exit(1)


def find_latest_build(token, app_id, build_number=None):
    """Find a build — latest or by build number."""
    url = f"https://api.appstoreconnect.apple.com/v1/builds?filter[app]={app_id}&sort=-version&limit=5"
    if build_number:
        url += f"&filter[version]={build_number}"
    data = api_get(token, url)
    builds = data.get("data", [])
    if not builds:
        print("ERROR: No builds found")
        sys.exit(1)
    return builds[0]


def add_build_to_group(token, group_id, build_id):
    """Add a build to a beta group."""
    url = f"https://api.appstoreconnect.apple.com/v1/betaGroups/{group_id}/relationships/builds"
    data = {"data": [{"type": "builds", "id": build_id}]}
    api_post(token, url, data)


def submit_for_beta_review(token, build_id):
    """Submit a build for beta app review (required for external testing)."""
    url = "https://api.appstoreconnect.apple.com/v1/betaAppReviewSubmissions"
    data = {
        "data": {
            "type": "betaAppReviewSubmissions",
            "relationships": {
                "build": {
                    "data": {"type": "builds", "id": build_id}
                }
            }
        }
    }
    try:
        api_post(token, url, data)
    except urllib.error.HTTPError as e:
        # 409 = already submitted/approved, which is fine
        if e.code == 409:
            print("  (Already submitted or approved)")
        else:
            raise


def main():
    parser = argparse.ArgumentParser(description="Distribute build to TestFlight group")
    parser.add_argument("--build-number", help="Specific build number (default: latest)")
    args = parser.parse_args()

    print("Generating API token...")
    token = generate_token()

    print(f"Finding app ({BUNDLE_ID})...")
    app_id = find_app(token)

    print(f"Finding '{BETA_GROUP_NAME}' beta group...")
    group_id = find_beta_group(token, app_id)

    print("Finding build...")
    build = find_latest_build(token, app_id, args.build_number)
    build_id = build["id"]
    version = build["attributes"]["version"]
    status = build["attributes"]["processingState"]
    print(f"  Build {version} (status: {status})")

    if status != "VALID":
        print(f"  Waiting for build to finish processing...")
        for i in range(60):
            time.sleep(10)
            build = find_latest_build(token, app_id, version)
            status = build["attributes"]["processingState"]
            print(f"  ... {status} ({(i+1)*10}s)")
            if status == "VALID":
                break
            if status == "INVALID":
                print("ERROR: Build is invalid")
                sys.exit(1)
        else:
            print("ERROR: Build still processing after 10 minutes")
            sys.exit(1)

    print(f"Submitting build {version} for beta review...")
    submit_for_beta_review(token, build_id)

    print(f"Adding build {version} to '{BETA_GROUP_NAME}' group...")
    add_build_to_group(token, group_id, build_id)
    print(f"Done! Build {version} is now available to '{BETA_GROUP_NAME}' testers.")


if __name__ == "__main__":
    main()
