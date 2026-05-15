# Daniel Petrovic

Personal website and blog source for GitHub Pages, built with Jekyll.

## Local preview

The most reliable local preview path is Docker:

```sh
docker run --rm -p 4000:4000 -v "$PWD:/srv/jekyll:Z" -w /srv/jekyll jekyll/jekyll:4 sh -lc 'bundle install && bundle exec jekyll serve --host 0.0.0.0'
```

Open `http://127.0.0.1:4000`.

If you prefer a local Ruby install:

```sh
bundle install
bundle exec jekyll serve
```

## Build

```sh
bundle exec jekyll build
```

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
