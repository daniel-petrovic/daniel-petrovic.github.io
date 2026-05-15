---
title: Home
description: Personal website and engineering notes about coding, C++, tooling, and practical software work.
permalink: /
---

<section class="hero">
  <p class="eyebrow">Personal website</p>
  <h1>Daniel Petrovic</h1>
  <p class="lead">
    I build software, enjoy clean engineering, and like exploring topics such as C++, tooling,
    performance, and practical web development.
  </p>
  <div class="hero-actions">
    <a class="button" href="{{ '/blog/' | relative_url }}">Read the blog</a>
    <a class="button button-secondary" href="https://github.com/daniel-petrovic">GitHub</a>
  </div>
</section>

<section class="grid-two">
  <article class="panel">
    <h2>About</h2>
    <p>
      This site is a home base for a short personal introduction, current interests, and notes
      about the kind of software work I care about.
    </p>
    <p>
      The goal is to keep it simple: a clear homepage now, plus enough structure to publish
      technical writing without rebuilding the site later.
    </p>
  </article>
  <article class="panel">
    <h2>Right now</h2>
    <ul class="plain-list">
      <li>Writing about coding and developer workflow</li>
      <li>Exploring C++ and systems-oriented topics</li>
      <li>Keeping the site minimal, fast, and easy to maintain</li>
    </ul>
  </article>
</section>

<section class="panel">
  <div class="section-header">
    <div>
      <p class="eyebrow">Focus areas</p>
      <h2>What you can expect here</h2>
    </div>
  </div>
  <div class="card-grid">
    <article class="card">
      <h3>Engineering notes</h3>
      <p>Short posts about things learned while building, debugging, and maintaining software.</p>
    </article>
    <article class="card">
      <h3>C++ and low-level interests</h3>
      <p>Ideas, experiments, and references related to performance-aware programming.</p>
    </article>
    <article class="card">
      <h3>Personal presentation</h3>
      <p>A lightweight profile page that can stay readable even as the site grows.</p>
    </article>
  </div>
</section>

{% assign latest_posts = site.posts | slice: 0, 3 %}
<section class="panel">
  <div class="section-header">
    <div>
      <p class="eyebrow">Latest writing</p>
      <h2>Blog scaffold</h2>
    </div>
    <a href="{{ '/blog/' | relative_url }}">See all posts</a>
  </div>

  {% if latest_posts.size > 0 %}
    <div class="post-list">
      {% for post in latest_posts %}
        <article class="post-preview">
          <p class="post-meta">
            <time datetime="{{ post.date | date_to_xmlschema }}">{{ post.date | date: "%B %-d, %Y" }}</time>
          </p>
          <h3><a href="{{ post.url | relative_url }}">{{ post.title }}</a></h3>
          <p>{{ post.description | default: post.excerpt | strip_html }}</p>
        </article>
      {% endfor %}
    </div>
  {% else %}
    <p class="empty-state">No posts yet. The structure is ready whenever the first article is.</p>
  {% endif %}
</section>
