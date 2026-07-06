#!/bin/bash
set -euo pipefail

PORT="${PORT:-4000}"

# Kill any container using the target port
CID="$(docker ps -q --filter "publish=$PORT" 2>/dev/null || true)"
[ -n "$CID" ] && docker kill "$CID" >/dev/null 2>&1 || true

docker run --rm --name jekyll-dev \
  -p "$PORT:4000" \
  -v "$PWD:/srv/jekyll:Z" \
  -v /etc/ssl/certs:/etc/ssl/certs:ro \
  -e SSL_CERT_DIR=/etc/ssl/certs \
  -e SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
  -w /srv/jekyll \
  jekyll/jekyll:4 \
  sh -lc 'bundle install && bundle exec jekyll serve --host 0.0.0.0 --disable-disk-cache --destination /tmp/jekyll-site'
