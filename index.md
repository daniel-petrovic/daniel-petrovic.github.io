---
title: Home
description: Embedded systems engineering, C and C++, Linux, Yocto, IoT, and practical software work.
permalink: /
---

<section class="hero">
  <p class="eyebrow">Personal website</p>
  <h1>Daniel Petrovic</h1>
  <p class="lead">
    Embedded software and systems engineer focused on C, modern C++, Linux, Yocto, IoT, and
    industrial automation, with an interest in compiler design.
  </p>
  <div class="hero-actions">
    <a class="button" href="{{ '/about/' | relative_url }}">About me</a>
    <a class="button button-secondary" href="https://github.com/daniel-petrovic">GitHub</a>
  </div>
</section>

<section class="grid-two">
  <article class="panel">
    <h2>What I do</h2>
    <p>
      I help meet project deadlines and fix hard-to-find bugs in embedded products and software
      stacks where reliability, performance, and maintainability matter.
    </p>
    <p>
      To me <b>SOLID</b> is not just a word.
    </p>
  </article>
  <article class="panel">
    <h2>Interests</h2>
    <ul class="plain-list">
      <li>C and C++</li>
      <li>Modern C++ (C++23 and newer)</li>
      <li>Embedded systems and IoT</li>
      <li>Scalable distributed systems</li>
      <li>Async I/O and multithreading</li>
      <li>Industrial automation</li>
      <li>Linux and Yocto</li>
      <li>Compiler design</li>
    </ul>
  </article>
</section>

<section class="panel">
  <div class="section-header">
    <div>
      <p class="eyebrow">Services</p>
      <h2>How I can help</h2>
    </div>
  </div>
  <div class="card-grid">
    <article class="card">
      <h3>Embedded development</h3>
      <p>Firmware and application work in C and modern C++ for embedded products and connected devices.</p>
    </article>
    <article class="card">
      <h3>Linux and Yocto</h3>
      <p>Linux-based platform work, build integration, and Yocto-driven system customization.</p>
    </article>
    <article class="card">
      <h3>IoT systems</h3>
      <p>Connected-device software with attention to integration, stability, and practical constraints.</p>
    </article>
    <article class="card">
      <h3>Industrial automation</h3>
      <p>Software for industrial systems where reliability, integration, and long-term maintainability matter.</p>
    </article>
  </div>
</section>

<section class="panel">
  <div class="section-header">
    <div>
      <p class="eyebrow">Latest writing</p>
      <h2>Technical notes</h2>
    </div>
    <a href="{{ '/blog/' | relative_url }}">See all posts</a>
  </div>
  <p>
    I write about the technical details behind the work: C/C++, low-level embedded software, execution models,
    and the problems that show up in real systems.
  </p>
</section>

{% assign latest_posts = site.posts | slice: 0, 2 %}
<section class="panel">
  <div class="section-header">
    <div>
      <p class="eyebrow">Recent posts</p>
      <h2>Latest writing</h2>
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
