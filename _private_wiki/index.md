---
title: Private Wiki
---

# Private Wiki

This wiki is reachable at `/private_wiki/` but is kept out of search
engines: it is excluded from the generated sitemap (`sitemap: false`) and
blocked in `robots.txt`.

Add notes as Markdown files in `_private_wiki/`. Each page inherits
`sitemap: false` and the default layout from `_config.yml`, so no front
matter is required.