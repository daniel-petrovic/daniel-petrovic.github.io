---
title: Contact
description: Contact Daniel Petrovic about embedded Linux and modern C++ projects.
permalink: /contact/
---

<section class="contact-page" aria-labelledby="contact-heading">
  <h1 id="contact-heading">Contact Daniel</h1>
  <p class="lead">For project or general inquiries, please get in touch.</p>

{% assign form_id = site.formspree_form_id | default: '' | strip %}
{% if form_id != '' %}
  <form class="contact-form" action="https://formspree.io/f/{{ form_id | escape }}" method="post">
    <div>
      <label for="contact-name">Name (optional)</label>
      <input id="contact-name" name="name" type="text" autocomplete="name">
    </div>
    <div>
      <label for="contact-email">Email</label>
      <input id="contact-email" name="email" type="email" autocomplete="email" required>
    </div>
    <div>
      <label for="contact-message">Message</label>
      <textarea id="contact-message" name="message" rows="7" required></textarea>
    </div>
    <input type="text" name="_gotcha" hidden tabindex="-1" autocomplete="off" aria-hidden="true">
    <button class="button" type="submit">Send</button>
  </form>
{% endif %}

  <p><a href="https://www.linkedin.com/in/daniel-petrovic/">Contact me on LinkedIn</a></p>
</section>
