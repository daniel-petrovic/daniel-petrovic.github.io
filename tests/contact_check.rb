require 'liquid'
require 'yaml'

root = File.expand_path('..', __dir__)
config = YAML.safe_load(File.read(File.join(root, '_config.yml')))
id = config.fetch('formspree_form_id', '').to_s.strip
abort 'Use only a public alphanumeric Formspree ID' unless id.empty? || id.match?(/\A[a-zA-Z0-9]+\z/)

body = File.read(File.join(root, 'contact.md')).split('---', 3).last
template = Liquid::Template.parse(body, error_mode: :strict)
[nil, '', '  ', 'test1234'].each do |form_id|
  html = template.render!('site' => { 'formspree_form_id' => form_id })
  abort 'Missing LinkedIn alternative' unless html.include?('https://www.linkedin.com/in/daniel-petrovic/')
  if form_id == 'test1234'
    abort 'Incorrect submission endpoint' unless html.include?('action="https://formspree.io/f/test1234" method="post"')
    abort 'Missing required email' unless html.match?(/<input[^>]+name="email"[^>]+type="email"[^>]+required/)
    abort 'Missing required message' unless html.match?(/<textarea[^>]+name="message"[^>]+required/)
    abort 'Missing honeypot' unless html.match?(/<input[^>]+name="_gotcha"[^>]+hidden/)
    abort 'Missing privacy disclosure' unless html.include?('https://formspree.io/legal/privacy-policy/')
    %w[name email message].each do |field|
      abort "Missing label for #{field}" unless html.include?(%Q(for="contact-#{field}"))
    end
  else
    abort 'Unconfigured page exposes a form' if html.include?('<form') || html.include?('formspree.io')
  end
end

%w[index.md cv.md _layouts/default.html contact.md].each do |path|
  source = File.read(File.join(root, path))
  abort "Public contact details remain in #{path}" if source.match?(/mailto:|tel:|[\w.+-]+@[\w.-]+\.[a-z]{2,}|Telephone:/i)
end
puts 'Contact rendering, validation markup, and privacy checks passed.'
