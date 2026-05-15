---
title: Blog
description: Coding notes and technical writing about software engineering, C++, tooling, and related topics.
permalink: /blog/
---

<section class="panel">
  <p class="eyebrow">Writing</p>
  <h1>Blog</h1>
  <p class="lead">
    A place for engineering notes, experiments, and posts about coding topics that are worth
    writing down.
  </p>

  {% if site.posts.size > 0 %}
    <div class="post-list">
      {% for post in site.posts %}
        <article class="post-preview">
          <p class="post-meta">
            <time datetime="{{ post.date | date_to_xmlschema }}">{{ post.date | date: "%B %-d, %Y" }}</time>
          </p>
          <h2><a href="{{ post.url | relative_url }}">{{ post.title }}</a></h2>
          <p>{{ post.description | default: post.excerpt | strip_html }}</p>
          {% if post.tags and post.tags.size > 0 %}
            <ul class="tag-list" aria-label="Tags">
              {% for tag in post.tags %}
                <li>{{ tag }}</li>
              {% endfor %}
            </ul>
          {% endif %}
        </article>
      {% endfor %}
    </div>
  {% else %}
    <p class="empty-state">No posts yet. Add a file to <code>_posts/</code> to publish the first one.</p>
  {% endif %}
</section>
