#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["httpx>=0.28", "pyjwt[crypto]>=2.10"]
# ///
"""Print the build number Xcode Cloud gives the App Store build of a commit.

Xcode Cloud stamps its own run number as the build number, so the Developer ID
build of the same release has to use that number too. Otherwise switching from
the App Store copy to the DMG installs a lower build number, and macOS keeps
the higher one registered until it is unregistered.

Waits for Xcode Cloud to start a run for the commit, then prints the newest
run's number.

Usage: xcode_cloud_build_number.py <commit sha>
Environment: APP_STORE_CONNECT_API_*; see app_store_connect.py
"""

import sys
import time

from app_store_connect import APP_ID, AppStoreConnect

POLL_SECONDS = 15


def main():
    commit = sys.argv[1]
    api = AppStoreConnect()
    product_id = api.get("/v1/ciProducts", **{"filter[app]": APP_ID})[0]["id"]
    while True:
        runs = api.get(
            f"/v1/ciProducts/{product_id}/buildRuns",
            **{"sort": "-number", "limit": "20", "fields[ciBuildRuns]": "number,sourceCommit"},
        )
        for run in runs:
            if run["attributes"]["sourceCommit"]["commitSha"] == commit:
                print(run["attributes"]["number"])
                return
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
