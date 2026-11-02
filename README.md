# Takes stats

Written once a day by `scripts/stats.py` (the Stats workflow). Download counts are running totals:
subtract yesterday's row to get one day's number.

- `daily.csv`: stars, forks, watchers; `dmg_downloads` (every Takes disk image ever downloaded);
  `appcast_checks` (update checks: installed copies with automatic checks on fetch `appcast.xml`
  about once a day, so the daily increase is roughly the number of copies in use).
- `releases.csv`: the same two counts for each release. Update checks count on the latest release only.
- `traffic.csv`: repository page views and git clones per day (needs `TRAFFIC_TOKEN`).
- `referrers.csv`: sites that sent visitors to the repository over the 14 days before each date.
