#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["httpx>=0.28", "pyjwt[crypto]>=2.10"]
# ///
"""Submit the App Store build of a release tag for review.

Waits for Xcode Cloud's build of the tag to finish processing, points the
editable macOS App Store version at it, and submits it. Any submission that is
still open is cancelled first, so the newest release always wins.

Environment:
  TAG                                Release tag, e.g. v1.5.2
  APP_STORE_CONNECT_API_KEY_ID       Key ID of an App Manager API key
  APP_STORE_CONNECT_API_ISSUER_ID    Issuer ID for that key
  APP_STORE_CONNECT_API_PRIVATE_KEY  base64 of the AuthKey_<key id>.p8 contents
  GITHUB_SERVER_URL, GITHUB_REPOSITORY  Set by GitHub Actions
"""

import base64
import os
import time

import httpx
import jwt

APP_ID = "6758317010"
PLATFORM = "MAC_OS"
POLL_SECONDS = 60
OPEN_SUBMISSION_STATES = "READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES"
EDITABLE_VERSION_STATES = (
    "PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED,INVALID_BINARY"
)


class AppStoreConnect:
    def __init__(self, key_id: str, issuer_id: str, private_key: str):
        self._key_id = key_id
        self._issuer_id = issuer_id
        self._private_key = private_key
        self._http = httpx.Client(base_url="https://api.appstoreconnect.apple.com", timeout=60)

    def get(self, path: str, **params: str) -> list[dict] | dict:
        return self._request("GET", path, params=params)

    def post(self, path: str, resource: dict) -> dict:
        return self._request("POST", path, json={"data": resource})

    def patch(self, path: str, resource: dict) -> dict:
        return self._request("PATCH", path, json={"data": resource})

    def _request(self, method: str, path: str, **kwargs):
        response = self._http.request(
            method, path, headers={"Authorization": f"Bearer {self._token()}"}, **kwargs
        )
        if response.is_error:
            raise SystemExit(f"{method} {path} failed with {response.status_code}: {response.text}")
        return response.json()["data"]

    def _token(self) -> str:
        now = int(time.time())
        return jwt.encode(
            {"iss": self._issuer_id, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
            self._private_key,
            algorithm="ES256",
            headers={"kid": self._key_id},
        )


def main():
    tag = os.environ["TAG"]
    version = tag.removeprefix("v")
    release_url = (
        f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/releases/tag/{tag}"
    )
    api = AppStoreConnect(
        os.environ["APP_STORE_CONNECT_API_KEY_ID"],
        os.environ["APP_STORE_CONNECT_API_ISSUER_ID"],
        base64.b64decode(os.environ["APP_STORE_CONNECT_API_PRIVATE_KEY"]).decode(),
    )

    build_id = wait_for_build(api, version)
    cancel_open_submissions(api)
    version_id = prepare_version(api, version, build_id)
    set_release_notes(
        api, version_id, f"Bug fixes and improvements. Full release notes: {release_url}"
    )
    submit(api, version_id)
    print(f"✅ Submitted {version} for review")


def wait_for_build(api: AppStoreConnect, version: str) -> str:
    last_state = None
    while True:
        builds = api.get(
            "/v1/builds",
            **{
                "filter[app]": APP_ID,
                "filter[preReleaseVersion.version]": version,
                "filter[preReleaseVersion.platform]": PLATFORM,
                "sort": "-uploadedDate",
                "limit": "1",
            },
        )
        state = builds[0]["attributes"]["processingState"] if builds else "NOT_UPLOADED"
        if state != last_state:
            print(f"Build(version: {version}, state: {state})")
            last_state = state
        if state == "VALID":
            return builds[0]["id"]
        time.sleep(POLL_SECONDS)


def cancel_open_submissions(api: AppStoreConnect):
    submissions = api.get(
        "/v1/reviewSubmissions",
        **{
            "filter[app]": APP_ID,
            "filter[platform]": PLATFORM,
            "filter[state]": OPEN_SUBMISSION_STATES,
        },
    )
    for submission in submissions:
        print(
            f"ReviewSubmission(id: {submission['id']}, state: {submission['attributes']['state']}) cancelling"
        )
        state = api.patch(
            f"/v1/reviewSubmissions/{submission['id']}",
            {"type": "reviewSubmissions", "id": submission["id"], "attributes": {"canceled": True}},
        )["attributes"]["state"]
        while state == "CANCELING":
            time.sleep(POLL_SECONDS)
            state = api.get(f"/v1/reviewSubmissions/{submission['id']}")["attributes"]["state"]


def prepare_version(api: AppStoreConnect, version: str, build_id: str) -> str:
    attributes = {"versionString": version, "releaseType": "AFTER_APPROVAL"}
    build = {"build": ref("builds", build_id)}
    editable = api.get(
        f"/v1/apps/{APP_ID}/appStoreVersions",
        **{"filter[platform]": PLATFORM, "filter[appVersionState]": EDITABLE_VERSION_STATES},
    )
    if editable:
        version_id = editable[0]["id"]
        print(
            f"AppStoreVersion(id: {version_id}, was: {editable[0]['attributes']['versionString']}) reusing"
        )
        api.patch(
            f"/v1/appStoreVersions/{version_id}",
            {
                "type": "appStoreVersions",
                "id": version_id,
                "attributes": attributes,
                "relationships": build,
            },
        )
        return version_id
    return api.post(
        "/v1/appStoreVersions",
        {
            "type": "appStoreVersions",
            "attributes": {**attributes, "platform": PLATFORM},
            "relationships": {**build, "app": ref("apps", APP_ID)},
        },
    )["id"]


def set_release_notes(api: AppStoreConnect, version_id: str, notes: str):
    for localization in api.get(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations"):
        api.patch(
            f"/v1/appStoreVersionLocalizations/{localization['id']}",
            {
                "type": "appStoreVersionLocalizations",
                "id": localization["id"],
                "attributes": {"whatsNew": notes},
            },
        )


def submit(api: AppStoreConnect, version_id: str):
    submission_id = api.post(
        "/v1/reviewSubmissions",
        {
            "type": "reviewSubmissions",
            "attributes": {"platform": PLATFORM},
            "relationships": {"app": ref("apps", APP_ID)},
        },
    )["id"]
    api.post(
        "/v1/reviewSubmissionItems",
        {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": ref("reviewSubmissions", submission_id),
                "appStoreVersion": ref("appStoreVersions", version_id),
            },
        },
    )
    api.patch(
        f"/v1/reviewSubmissions/{submission_id}",
        {"type": "reviewSubmissions", "id": submission_id, "attributes": {"submitted": True}},
    )


def ref(resource_type: str, resource_id: str) -> dict:
    return {"data": {"type": resource_type, "id": resource_id}}


if __name__ == "__main__":
    main()
