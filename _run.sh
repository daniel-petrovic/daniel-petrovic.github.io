#!/bin/bash
set -euo pipefail

docker run --rm -p 5000:4000 \
  -v "$PWD:/srv/jekyll:Z" \
  -v /etc/ssl/certs:/etc/ssl/certs:ro \
  -e SSL_CERT_DIR=/etc/ssl/certs \
  -e SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
  -w /srv/jekyll \
  jekyll/jekyll:4 \
  sh -lc 'bundle install && bundle exec jekyll serve --host 0.0.0.0 --disable-disk-cache --destination /tmp/jekyll-site'
