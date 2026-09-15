# Daniel Petrovic

Personal website and blog source for GitHub Pages, built with Jekyll.

## Local preview

The most reliable local preview path is Docker:

```sh
PORT=4000
docker run --rm -p "$PORT:4000" \
  -v "$PWD:/srv/jekyll:Z" \
  -v /etc/ssl/certs:/etc/ssl/certs:ro \
  -e SSL_CERT_DIR=/etc/ssl/certs \
  -e SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
  -w /srv/jekyll \
  jekyll/jekyll:4 \
  sh -lc 'bundle install && bundle exec jekyll serve --host 0.0.0.0 --disable-disk-cache --destination /tmp/jekyll-site'
```

Open `http://127.0.0.1:$PORT`.

If port `4000` is already in use, pick another one, for example `PORT=4001`.

If you prefer a local Ruby install:

```sh
bundle install
bundle exec jekyll serve
```

## Build

```sh
bundle exec jekyll build
```

## Contact form setup

The contact page shows LinkedIn until `formspree_form_id` in `_config.yml` is set.

1. Create a form in Formspree and verify its recipient mailbox privately in the dashboard.
2. Copy only the public ID from `https://formspree.io/f/FORM_ID` into `formspree_form_id`. Never commit the recipient email or an API key.
3. Keep Formspree spam filtering and hosted CAPTCHA protection enabled. The form includes the supported `_gotcha` honeypot.
4. Review applicable business disclosures and privacy requirements before publishing. The brief form disclosure is not a complete site privacy policy.
5. Rebuild/restart Jekyll after changing configuration. Send one clearly labeled test inquiry and verify delivery, reply routing, and the hosted confirmation page before announcing the form.

Run `bundle exec ruby tests/contact_check.rb` to check configured and unconfigured rendering. No submissions are sent by this check.

Removing current contact details does not erase public Git history or previously collected copies. History rewriting and mailbox changes are separate tasks.

## Structure

```text
/
├── _layouts/
├── _posts/
├── assets/
│   └── css/
└── .github/workflows/
```

## Deployment

The repository includes a GitHub Actions workflow that builds and deploys the Jekyll site to GitHub Pages.
