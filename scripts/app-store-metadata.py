#!/usr/bin/env python3
"""Fills the App Store page of "Lanes for Safari" through the App Store
Connect API, from LanesForSafari/Store/metadata.json and the screenshots in
LanesForSafari/Store/screenshots/<locale>/.

It sets: content rights, categories, name, subtitle and privacy policy URL,
age rating (nothing objectionable, 4+), free price in every territory, the
version number and copyright, description, keywords, promotional text,
support and marketing URLs, screenshots, review notes and the build. It
never submits the version for review.

Apple's API has no way to answer the App Privacy questions, so "Data Not
Collected" stays a click in App Store Connect. Review contact details
(name, phone, e-mail) are also left to the account owner.

Every part runs on its own: a part that fails is reported at the end and the
rest still run, so the script can be run again until everything is in place.

Needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_FILE (as scripts/app-store.sh)
and the PyJWT and cryptography packages. Usage:
  scripts/app-store-metadata.py [--version 1.3.1] [--build 80] [--wait-build 1200]
"""
import argparse
import hashlib
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

ROOT = pathlib.Path(__file__).resolve().parent.parent
STORE = ROOT / "LanesForSafari" / "Store"
API = "https://api.appstoreconnect.apple.com"


class APIError(Exception):
    def __init__(self, status, body):
        self.status = status
        self.body = body
        try:
            errors = json.loads(body).get("errors", [])
        except ValueError:
            errors = []
        self.errors = errors
        detail = "; ".join(f"{e.get('title', '')}: {e.get('detail', '')}" for e in errors) or body[:500]
        super().__init__(f"HTTP {status}: {detail}")


class Client:
    def __init__(self, key_id, issuer, key_file):
        self.key_id = key_id
        self.issuer = issuer
        self.key = pathlib.Path(key_file).read_text()
        self.token = None
        self.token_time = 0

    def _auth(self):
        if not self.token or time.time() - self.token_time > 600:
            now = int(time.time())
            self.token = jwt.encode(
                {"iss": self.issuer, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                self.key,
                algorithm="ES256",
                headers={"kid": self.key_id, "typ": "JWT"},
            )
            self.token_time = now
        return self.token

    def request(self, method, path, body=None, query=None):
        url = path if path.startswith("http") else API + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", "Bearer " + self._auth())
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            raise APIError(error.code, error.read().decode(errors="replace")) from None

    def get(self, path, **query):
        return self.request("GET", path, query=query or None)

    def all(self, path, **query):
        out = []
        page = self.get(path, **query)
        while True:
            out.extend(page.get("data") or [])
            nxt = (page.get("links") or {}).get("next")
            if not nxt:
                return out
            page = self.request("GET", nxt)

    def patch(self, kind, ident, attributes=None, relationships=None):
        data = {"type": kind, "id": ident}
        if attributes:
            data["attributes"] = attributes
        if relationships:
            data["relationships"] = relationships
        return self.request("PATCH", f"/v1/{kind}/{ident}", {"data": data})

    def create(self, kind, attributes=None, relationships=None):
        data = {"type": kind}
        if attributes:
            data["attributes"] = attributes
        if relationships:
            data["relationships"] = relationships
        return self.request("POST", f"/v1/{kind}", {"data": data})["data"]


def rel(kind, ident):
    return {"data": {"type": kind, "id": ident}}


def patch_tolerant(client, kind, ident, attributes):
    """PATCH, dropping attributes the API says it doesn't know (the age rating
    questions change between API versions)."""
    attributes = dict(attributes)
    for _ in range(len(attributes) + 1):
        try:
            return client.patch(kind, ident, attributes)
        except APIError as error:
            unknown = []
            for e in error.errors:
                pointer = ((e.get("source") or {}).get("pointer") or "")
                if pointer.startswith("/data/attributes/"):
                    unknown.append(pointer.rsplit("/", 1)[-1])
            unknown = [name for name in unknown if name in attributes]
            if error.status not in (409, 422) or not unknown:
                raise
            for name in unknown:
                print(f"    (age rating: API doesn't take {name}, left out)")
                attributes.pop(name)
    raise RuntimeError("could not save attributes")


class Run:
    def __init__(self):
        self.failed = []

    def part(self, title, fn):
        print(f"==> {title}")
        try:
            fn()
            print("    ok")
        except Exception as error:  # noqa: BLE001 - each part reports and the rest continue
            print(f"    FAILED: {error}")
            self.failed.append((title, str(error)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", help="version string (default: MARKETING_VERSION in project.yml)")
    parser.add_argument("--build", help="build number to attach (default: newest processed build of the version)")
    parser.add_argument("--wait-build", type=int, default=0, help="seconds to wait for the build to finish processing")
    args = parser.parse_args()

    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_FILE"):
        if not os.environ.get(name):
            sys.exit(f"app-store-metadata: {name} gerekli.")
    meta = json.loads((STORE / "metadata.json").read_text())
    version = args.version
    if not version:
        for line in (ROOT / "project.yml").read_text().splitlines():
            if "MARKETING_VERSION:" in line:
                version = line.split('"')[1]
                break
    client = Client(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_KEY_FILE"])
    run = Run()

    apps = client.get("/v1/apps", **{"filter[bundleId]": meta["bundleId"]})["data"]
    if not apps:
        sys.exit(f"app-store-metadata: App Store Connect'te {meta['bundleId']} için uygulama kaydı yok.")
    app_id = apps[0]["id"]
    print(f"App {apps[0]['attributes'].get('name')} ({app_id}), version {version}")

    run.part("Content rights", lambda: client.patch(
        "apps", app_id, {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}))

    # The app info that can still be edited (a new app has one).
    infos = client.all(f"/v1/apps/{app_id}/appInfos")
    info = next((i for i in infos if (i["attributes"].get("appStoreState") or i["attributes"].get("state")) not in
                 ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_INFO")), infos[0])
    info_id = info["id"]

    run.part("Categories", lambda: client.patch("appInfos", info_id, relationships={
        "primaryCategory": rel("appCategories", meta["primaryCategory"]),
        "secondaryCategory": rel("appCategories", meta["secondaryCategory"]),
    }))

    def info_localizations():
        existing = {l["attributes"]["locale"]: l["id"] for l in client.all(f"/v1/appInfos/{info_id}/appInfoLocalizations")}
        for locale, texts in meta["locales"].items():
            attributes = {"name": texts["name"], "subtitle": texts["subtitle"], "privacyPolicyUrl": meta["privacyPolicyUrl"]}
            if locale in existing:
                client.patch("appInfoLocalizations", existing[locale], attributes)
            else:
                client.create("appInfoLocalizations", dict(attributes, locale=locale),
                              {"appInfo": rel("appInfos", info_id)})
            print(f"    {locale}: name, subtitle, privacy policy")
    run.part("Name, subtitle, privacy policy URL", info_localizations)

    def age_rating():
        declaration = client.get(f"/v1/appInfos/{info_id}/ageRatingDeclaration")["data"]
        none = "NONE"
        attributes = {
            "alcoholTobaccoOrDrugUseOrReferences": none, "contests": none, "gamblingSimulated": none,
            "gunsOrOtherWeapons": none, "horrorOrFearThemes": none, "matureOrSuggestiveThemes": none,
            "medicalOrTreatmentInformation": none, "profanityOrCrudeHumor": none,
            "sexualContentGraphicAndNudity": none, "sexualContentOrNudity": none,
            "violenceCartoonOrFantasy": none, "violenceRealistic": none,
            "violenceRealisticProlongedGraphicOrSadistic": none,
            "gambling": False, "unrestrictedWebAccess": False, "lootBox": False,
            "messagingAndChat": False, "userGeneratedContent": False, "advertising": False,
            "healthOrWellnessTopics": False, "parentalControls": False, "ageAssurance": False,
        }
        patch_tolerant(client, "ageRatingDeclarations", declaration["id"], attributes)
    run.part("Age rating (4+)", age_rating)

    def price():
        points = client.all(f"/v1/apps/{app_id}/appPricePoints", **{"filter[territory]": "USA", "limit": 200})
        free = next(p for p in points if float(p["attributes"]["customerPrice"]) == 0)
        client.request("POST", "/v1/appPriceSchedules", {
            "data": {"type": "appPriceSchedules", "relationships": {
                "app": rel("apps", app_id),
                "baseTerritory": rel("territories", "USA"),
                "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]},
            }},
            "included": [{"type": "appPrices", "id": "${free}", "attributes": {"startDate": None},
                          "relationships": {"appPricePoint": rel("appPricePoints", free["id"])}}],
        })
    run.part("Price: free", price)

    def availability():
        territories = [t["id"] for t in client.all("/v1/territories", limit=200)]
        try:
            client.request("POST", "/v2/appAvailabilities", {
                "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                         "relationships": {"app": rel("apps", app_id), "territoryAvailabilities": {
                             "data": [{"type": "territoryAvailabilities", "id": f"${{{t}}}"} for t in territories]}}},
                "included": [{"type": "territoryAvailabilities", "id": f"${{{t}}}", "attributes": {"available": True},
                              "relationships": {"territory": rel("territories", t)}} for t in territories],
            })
        except APIError as error:
            if error.status == 409 and "already" in error.body.lower():
                print("    already set")
                return
            raise
        print(f"    {len(territories)} territories")
    run.part("Availability: all territories", availability)

    # The version being prepared.
    versions = client.all(f"/v1/apps/{app_id}/appStoreVersions", **{"filter[platform]": "MAC_OS"})
    editable = [v for v in versions if (v["attributes"].get("appStoreState") or v["attributes"].get("appVersionState"))
                in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")]
    if editable:
        version_id = editable[0]["id"]
    else:
        version_id = client.create("appStoreVersions", {"platform": "MAC_OS", "versionString": version},
                                   {"app": rel("apps", app_id)})["id"]
        print(f"Created version {version}")

    run.part(f"Version {version}, copyright, release after approval", lambda: client.patch(
        "appStoreVersions", version_id,
        {"versionString": version, "copyright": meta["copyright"], "releaseType": "AFTER_APPROVAL"}))

    localization_ids = {}

    def version_localizations():
        existing = {l["attributes"]["locale"]: l["id"]
                    for l in client.all(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")}
        for locale, texts in meta["locales"].items():
            attributes = {
                "description": texts["description"], "keywords": texts["keywords"],
                "promotionalText": texts["promotionalText"],
                "supportUrl": meta["supportUrl"], "marketingUrl": meta["marketingUrl"],
            }
            if locale in existing:
                client.patch("appStoreVersionLocalizations", existing[locale], attributes)
                localization_ids[locale] = existing[locale]
            else:
                localization_ids[locale] = client.create(
                    "appStoreVersionLocalizations", dict(attributes, locale=locale),
                    {"appStoreVersion": rel("appStoreVersions", version_id)})["id"]
            print(f"    {locale}: description, keywords, promotional text, URLs")
    run.part("Description, keywords, promotional text, URLs", version_localizations)

    def screenshots():
        for locale, localization_id in localization_ids.items():
            files = sorted((STORE / "screenshots" / locale).glob("*.png"))
            if not files:
                continue
            sets = client.all(f"/v1/appStoreVersionLocalizations/{localization_id}/appScreenshotSets")
            desktop = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == "APP_DESKTOP"), None)
            if desktop is None:
                desktop = client.create("appScreenshotSets", {"screenshotDisplayType": "APP_DESKTOP"},
                                        {"appStoreVersionLocalization": rel("appStoreVersionLocalizations", localization_id)})
            # Start clean, so running again doesn't add duplicates.
            for old in client.all(f"/v1/appScreenshotSets/{desktop['id']}/appScreenshots"):
                client.request("DELETE", f"/v1/appScreenshots/{old['id']}")
            for path in files:
                data = path.read_bytes()
                shot = client.create("appScreenshots", {"fileName": path.name, "fileSize": len(data)},
                                     {"appScreenshotSet": rel("appScreenshotSets", desktop["id"])})
                for op in shot["attributes"]["uploadOperations"]:
                    part = data[op["offset"]:op["offset"] + op["length"]]
                    req = urllib.request.Request(op["url"], data=part, method=op["method"])
                    for header in op.get("requestHeaders") or []:
                        req.add_header(header["name"], header["value"])
                    with urllib.request.urlopen(req, timeout=120):
                        pass
                client.patch("appScreenshots", shot["id"],
                             {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()})
                print(f"    {locale}: {path.name}")
    run.part("Screenshots", screenshots)

    def review_notes():
        try:
            detail = client.get(f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail")["data"]
        except APIError as error:
            if error.status != 404:
                raise
            detail = None
        attributes = {"notes": meta["reviewNotes"], "demoAccountRequired": False}
        if detail:
            client.patch("appStoreReviewDetails", detail["id"], attributes)
        else:
            client.create("appStoreReviewDetails", attributes, {"appStoreVersion": rel("appStoreVersions", version_id)})
    run.part("Review notes (no demo account)", review_notes)

    def build():
        deadline = time.time() + args.wait_build
        while True:
            query = {"filter[app]": app_id, "filter[preReleaseVersion.version]": version, "sort": "-uploadedDate", "limit": 20}
            if args.build:
                query["filter[version]"] = args.build
            builds = client.get("/v1/builds", **query)["data"]
            valid = [b for b in builds if b["attributes"].get("processingState") == "VALID"]
            if valid:
                chosen = valid[0]
                break
            states = ", ".join(f"{b['attributes'].get('version')}={b['attributes'].get('processingState')}" for b in builds) or "none yet"
            if time.time() >= deadline:
                raise RuntimeError(f"no processed build of {version} ({states})")
            print(f"    waiting for the build to be processed ({states})")
            time.sleep(60)
        if chosen["attributes"].get("usesNonExemptEncryption") is None:
            client.patch("builds", chosen["id"], {"usesNonExemptEncryption": False})
        client.request("PATCH", f"/v1/appStoreVersions/{version_id}/relationships/build",
                       {"data": {"type": "builds", "id": chosen["id"]}})
        print(f"    build {chosen['attributes'].get('version')}")
    run.part("Build", build)

    print()
    print("Left for App Store Connect (the API can't do these):")
    print("  - App Privacy: 'Data Not Collected', then Publish")
    print("  - App Review Information: contact name, phone and e-mail")
    print("  - Add for Review > Submit for Review")
    if run.failed:
        print()
        print("Failed parts (run again after fixing):")
        for title, error in run.failed:
            print(f"  - {title}: {error}")
        sys.exit(1)


if __name__ == "__main__":
    main()
