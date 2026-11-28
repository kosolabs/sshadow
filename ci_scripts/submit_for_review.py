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
  TAG                                   Release tag, e.g. v1.5.2
  APP_STORE_CONNECT_API_*               An App Manager key; see app_store_connect.py
  GITHUB_SERVER_URL, GITHUB_REPOSITORY  Set by GitHub Actions
"""

import os
import time

from app_store_connect import APP_ID, AppStoreConnect

PLATFORM = "MAC_OS"
POLL_SECONDS = 60
OPEN_SUBMISSION_STATES = "READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES"
EDITABLE_VERSION_STATES = (
    "PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED,INVALID_BINARY"
)


def main():
    tag = os.environ["TAG"]
    version = tag.removeprefix("v")
    release_url = (
        f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/releases/tag/{tag}"
    )
    api = AppStoreConnect()

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
