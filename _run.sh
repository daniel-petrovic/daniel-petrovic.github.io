#!/bin/bash

docker run --rm -p 4000:4000 -v "$PWD:/srv/jekyll:Z" -w /srv/jekyll jekyll/jekyll:4 jekyll serve --host 0.0.0.0
