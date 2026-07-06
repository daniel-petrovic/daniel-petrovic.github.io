#!/bin/bash
set -euo pipefail

PORT="${PORT:-4000}"

if command -v ss >/dev/null 2>&1 && ss -ltn "sport = :$PORT" | grep -q LISTEN; then
  echo "Port $PORT is already in use. Run with a different port, for example: PORT=4001 ./_run.sh" >&2
  exit 1
fi

docker run --rm -p "$PORT:4000" \
  -v "$PWD:/srv/jekyll:Z" \
  -v /etc/ssl/certs:/etc/ssl/certs:ro \
  -e SSL_CERT_DIR=/etc/ssl/certs \
  -e SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
  -w /srv/jekyll \
  jekyll/jekyll:4 \
  sh -lc 'bundle install && bundle exec jekyll serve --host 0.0.0.0 --disable-disk-cache --destination /tmp/jekyll-site'
