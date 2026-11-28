"""App Store Connect API client shared by the ci_scripts Python scripts.

Reads credentials from the environment:
  APP_STORE_CONNECT_API_KEY_ID       Key ID of an App Store Connect API key
  APP_STORE_CONNECT_API_ISSUER_ID    Issuer ID for that key
  APP_STORE_CONNECT_API_PRIVATE_KEY  base64 of the AuthKey_<key id>.p8 contents
"""

import base64
import os
import time

import httpx
import jwt

APP_ID = "6758317010"


class AppStoreConnect:
    def __init__(self):
        self._key_id = os.environ["APP_STORE_CONNECT_API_KEY_ID"]
        self._issuer_id = os.environ["APP_STORE_CONNECT_API_ISSUER_ID"]
        self._private_key = base64.b64decode(
            os.environ["APP_STORE_CONNECT_API_PRIVATE_KEY"]
        ).decode()
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
