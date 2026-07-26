---
title: Home
description: Senior Software Engineer | Linux | Windows | Embedded | Networking | Databases | AI Enthusiast | CyberSecurity
permalink: /
---

<section class="hero">
  <p class="eyebrow">Senior Software Engineer | Linux | Windows | Embedded | Networking | Databases | AI Enthusiast | CyberSecurity</p>
  <h1>Daniel Petrovic</h1>
  <p class="lead">
    Building robust Linux-based embedded software for complex products and platforms.
  </p>
  <div class="hero-actions">
    <a class="button" href="{{ '/cv/' | relative_url }}">Services &amp; Experience</a>
    <a class="button button-secondary" href="https://github.com/daniel-petrovic">GitHub</a>
  </div>
</section>

<section class="grid-two">
  <article class="panel">
    <h2>What I do</h2>
    <p>
      I help teams meet project deadlines and solve hard-to-find problems in software systems where reliability, performance, and maintainability matter.
    </p>
    <p>
      I work across the full stack of embedded Linux systems — from Yocto BSP integration and low-level I/O to Qt6/QML user interfaces and cloud connectivity.
    </p>
  </article>
  <article class="panel">
    <h2>Specialties</h2>
    <ul class="plain-list">
      <li>Embedded Linux &amp; Yocto</li>
      <li>Modern C++ (C++17/20/23)</li>
      <li>Qt6 &amp; QML</li>
      <li>OPC UA, CAN/CANopen</li>
      <li>Software Architecture</li>
      <li>Mentoring</li>
      <li>Performance Optimization</li>
      <li>Build Systems &amp; CI/CD</li>
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
      <h3>Embedded Linux &amp; Yocto</h3>
      <p>Platform integration, BSP customization, build system optimization, and Yocto layer development for ARM/Linux devices.</p>
    </article>
    <article class="card">
      <h3>Qt6 &amp; QML Applications</h3>
      <p>Cross-platform UI development, Qt6 application frameworks, QML interfaces, and embedded GUI optimization.</p>
    </article>
    <article class="card">
      <h3>Industrial Protocols</h3>
      <p>OPC UA server/client integration, CAN/CANopen communication, PLC interfacing, and IoT connectivity solutions.</p>
    </article>
    <article class="card">
      <h3>Software Architecture</h3>
      <p>Modular application design, clean architecture patterns, code quality tooling, and technical strategy for embedded systems.</p>
    </article>
  </div>
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
