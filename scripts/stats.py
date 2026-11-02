#!/usr/bin/env python3
"""Snapshots download, install and traffic numbers from GitHub into CSV files.

Usage: scripts/stats.py <output folder>
Env:   GITHUB_TOKEN (required), TRAFFIC_TOKEN (optional; GitHub's traffic API needs a token
       with the repository's Administration read permission, which GITHUB_TOKEN can't have)
       GITHUB_REPOSITORY (default bar-amir/takes)

GitHub only reports running totals for downloads and keeps 14 days of traffic, so running this
once a day keeps a history. Each file is updated in place: re-running on the same day replaces
that day's rows. Nothing here identifies a person: these are the same counts GitHub shows the
repository's owner.
"""
import csv
import datetime
import json
import os
import sys
import urllib.request

REPO = os.environ.get("GITHUB_REPOSITORY", "bar-amir/takes")
TODAY = datetime.date.today().isoformat()

README = """# Takes stats

Written once a day by `scripts/stats.py` (the Stats workflow). Download counts are running totals:
subtract yesterday's row to get one day's number.

- `daily.csv`: stars, forks, watchers; `dmg_downloads` (every Takes disk image ever downloaded);
  `appcast_checks` (update checks: installed copies with automatic checks on fetch `appcast.xml`
  about once a day, so the daily increase is roughly the number of copies in use).
- `releases.csv`: the same two counts for each release. Update checks count on the latest release only.
- `traffic.csv`: repository page views and git clones per day (needs `TRAFFIC_TOKEN`).
- `referrers.csv`: sites that sent visitors to the repository over the 14 days before each date.
"""


def api(path, token):
    req = urllib.request.Request(f"https://api.github.com/{path}", headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    with urllib.request.urlopen(req) as res:
        return json.load(res)


def upsert(path, fields, rows, key):
    """Writes rows into a CSV, replacing existing rows with the same key."""
    existing = []
    if os.path.exists(path):
        with open(path, newline="") as f:
            existing = list(csv.DictReader(f))
    new_keys = {key(r) for r in rows}
    merged = [r for r in existing if key(r) not in new_keys] + [{k: str(v) for k, v in r.items()} for r in rows]
    merged.sort(key=key)
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(merged)


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    token = os.environ["GITHUB_TOKEN"]

    repo = api(f"repos/{REPO}", token)
    releases = api(f"repos/{REPO}/releases?per_page=100", token)
    release_rows = []
    for rel in releases:
        if rel["draft"]:
            continue
        assets = rel["assets"]
        release_rows.append({
            "date": TODAY,
            "tag": rel["tag_name"],
            "dmg_downloads": sum(a["download_count"] for a in assets if a["name"].endswith(".dmg")),
            "appcast_checks": sum(a["download_count"] for a in assets if a["name"] == "appcast.xml"),
        })
    latest = next((r for r in releases if not r["draft"] and not r["prerelease"]), None)
    upsert(f"{out}/releases.csv", ["date", "tag", "dmg_downloads", "appcast_checks"], release_rows,
           key=lambda r: (r["date"], r["tag"]))
    upsert(f"{out}/daily.csv",
           ["date", "stars", "forks", "watchers", "dmg_downloads", "appcast_checks", "latest_version"],
           [{
               "date": TODAY,
               "stars": repo["stargazers_count"],
               "forks": repo["forks_count"],
               "watchers": repo["subscribers_count"],
               "dmg_downloads": sum(r["dmg_downloads"] for r in release_rows),
               "appcast_checks": sum(r["appcast_checks"] for r in release_rows),
               "latest_version": latest["tag_name"] if latest else "",
           }], key=lambda r: r["date"])

    traffic_token = os.environ.get("TRAFFIC_TOKEN")
    if traffic_token:
        views = {v["timestamp"][:10]: v for v in api(f"repos/{REPO}/traffic/views", traffic_token)["views"]}
        clones = {c["timestamp"][:10]: c for c in api(f"repos/{REPO}/traffic/clones", traffic_token)["clones"]}
        upsert(f"{out}/traffic.csv", ["date", "views", "unique_views", "clones", "unique_clones"], [{
            "date": day,
            "views": views.get(day, {}).get("count", 0),
            "unique_views": views.get(day, {}).get("uniques", 0),
            "clones": clones.get(day, {}).get("count", 0),
            "unique_clones": clones.get(day, {}).get("uniques", 0),
        } for day in sorted(set(views) | set(clones)) if day < TODAY],  # today isn't over yet
            key=lambda r: r["date"])
        upsert(f"{out}/referrers.csv", ["date", "referrer", "views", "unique_views"], [{
            "date": TODAY, "referrer": r["referrer"], "views": r["count"], "unique_views": r["uniques"],
        } for r in api(f"repos/{REPO}/traffic/popular/referrers", traffic_token)],
            key=lambda r: (r["date"], r["referrer"]))
    else:
        print("TRAFFIC_TOKEN not set: skipping views, clones and referrers.")

    with open(f"{out}/README.md", "w") as f:
        f.write(README)


if __name__ == "__main__":
    main()
