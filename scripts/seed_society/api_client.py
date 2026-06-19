"""Ed25519 device-seed auth + GraphQL transport for the Tentura local server.

Wire contract (verified against packages/server/lib/domain/use_case/auth_case.dart):

  1. A device "seed" is 32 random bytes -> Ed25519 keypair (PyNaCl SigningKey).
  2. An auth-request JWT is EdDSA-signed by that key. Payload:
       {"int": "sign_up"|"sign_in", "pk": <base64url(pubkey)>, "iat", "exp"}
     The server verifies the token against the `pk` embedded in its own payload
     (proof of possession). Only `pk` is strictly required.
  3. signUp(authRequestToken, displayName, handle?) and signIn(authRequestToken)
     both return an AuthResponse { subject, access_token, expires_in, ... }.
     With NEED_INVITE=false (local default) signUp needs no invite code.
  4. Authenticated calls send `Authorization: Bearer <access_token>`.
"""

from __future__ import annotations

import base64
import json
import os
import time

import requests
from nacl import signing


# --------------------------------------------------------------------------- #
# base64url helpers
# --------------------------------------------------------------------------- #
def b64url_nopad(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def b64url_pad(data: bytes) -> str:
    """Matches Dart's base64UrlEncode (padding retained); server normalizes it."""
    return base64.urlsafe_b64encode(data).decode("ascii")


def make_seed() -> bytes:
    return os.urandom(32)


def seed_to_b64(seed: bytes) -> str:
    """Persisted/displayable seed form (base64url with padding) for app login."""
    return b64url_pad(seed)


# --------------------------------------------------------------------------- #
# EdDSA JWT (manual, so we only depend on PyNaCl, not a JWT lib)
# --------------------------------------------------------------------------- #
def _auth_request_jwt(signing_key: signing.SigningKey, intent: str) -> str:
    pub = bytes(signing_key.verify_key)
    now = int(time.time())
    header = {"alg": "EdDSA", "typ": "JWT"}
    payload = {
        "int": intent,
        "pk": b64url_pad(pub),
        "iat": now,
        "exp": now + 30,
    }
    signing_input = (
        b64url_nopad(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + b64url_nopad(json.dumps(payload, separators=(",", ":")).encode())
    )
    sig = signing_key.sign(signing_input.encode("ascii")).signature
    return signing_input + "." + b64url_nopad(sig)


class GraphQLError(RuntimeError):
    """Surfaces the real GraphQL error message(s) from the server."""


class UserSession:
    """One authenticated persona. Holds the device key + bearer token."""

    def __init__(self, graphql_url: str, *, seed: bytes | None = None):
        self.graphql_url = graphql_url
        self.seed = seed or make_seed()
        self.signing_key = signing.SigningKey(self.seed)
        self.public_key_b64 = b64url_pad(bytes(self.signing_key.verify_key))
        self.subject: str | None = None
        self.handle: str | None = None
        self.display_name: str | None = None
        self.access_token: str | None = None
        self._http = requests.Session()

    # -- auth ------------------------------------------------------------- #
    def sign_up(self, display_name: str, handle: str | None = None) -> str:
        token = _auth_request_jwt(self.signing_key, "sign_up")
        variables = {"authRequestToken": token, "displayName": display_name}
        if handle:
            variables["handle"] = handle
        data = self._raw_gql(
            """
            mutation SignUp($authRequestToken: String!, $displayName: String!, $handle: String) {
              signUp(authRequestToken: $authRequestToken, displayName: $displayName, handle: $handle) {
                subject
                access_token
                expires_in
              }
            }
            """,
            variables,
            authed=False,
        )
        resp = data["signUp"]
        self.subject = resp["subject"]
        self.access_token = resp["access_token"]
        self.display_name = display_name
        self.handle = handle
        return self.subject

    def sign_in(self) -> str:
        token = _auth_request_jwt(self.signing_key, "sign_in")
        data = self._raw_gql(
            """
            mutation SignIn($authRequestToken: String!) {
              signIn(authRequestToken: $authRequestToken) {
                subject
                access_token
                expires_in
              }
            }
            """,
            {"authRequestToken": token},
            authed=False,
        )
        resp = data["signIn"]
        self.subject = resp["subject"]
        self.access_token = resp["access_token"]
        return self.subject

    # -- transport -------------------------------------------------------- #
    def gql(self, query: str, variables: dict | None = None) -> dict:
        return self._raw_gql(query, variables or {}, authed=True)

    def _raw_gql(self, query: str, variables: dict, *, authed: bool) -> dict:
        headers = {"Content-Type": "application/json"}
        if authed:
            if not self.access_token:
                raise GraphQLError("No access token; sign in first")
            headers["Authorization"] = f"Bearer {self.access_token}"
        r = self._http.post(
            self.graphql_url,
            headers=headers,
            data=json.dumps({"query": query, "variables": variables}),
            timeout=60,
        )
        try:
            body = r.json()
        except ValueError:
            raise GraphQLError(f"HTTP {r.status_code}: {r.text[:400]}") from None
        if body.get("errors"):
            msgs = "; ".join(e.get("message", str(e)) for e in body["errors"])
            raise GraphQLError(msgs)
        if "data" not in body:
            raise GraphQLError(f"No data in response: {body}")
        return body["data"]
