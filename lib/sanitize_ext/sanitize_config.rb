# frozen_string_literal: true

class Sanitize
  module Config
    HTTP_PROTOCOLS = %w(
      http
      https
    ).freeze

    LINK_PROTOCOLS = %w(
      http
      https
      dat
      dweb
      ipfs
      ipns
      ssb
      gopher
      xmpp
      magnet
      gemini
    ).freeze

    CLASS_WHITELIST_TRANSFORMER = lambda do |env|
      node = env[:node]
      class_list = node['class']&.split(/[\t\n\f\r ]/)

      return unless class_list

      class_list.keep_if do |e|
        next true if /^(h|p|u|dt|e)-/.match?(e) # microformats classes
        next true if /^(mention|hashtag)$/.match?(e) # semantic classes
        next true if /^(ellipsis|invisible)$/.match?(e) # link formatting classes
      end

      node['class'] = class_list.join(' ')
    end

    IMG_TAG_TRANSFORMER = lambda do |env|
      node = env[:node]

      return unless env[:node_name] == 'img'

      node.name = 'a'

      node['href'] = node['src']
      if node['alt'].present?
        node.content = "[🖼  #{node['alt']}]"
      else
        url = node['href']
        prefix = url.match(/\Ahttps?:\/\/(www\.)?/).to_s
        text   = url[prefix.length, 30]
        text   = text + "…" if url[prefix.length..-1].length > 30
        node.content = "[🖼  #{text}]"
      end
    end

    LINK_REL_TRANSFORMER = lambda do |env|
      return unless env[:node_name] == 'a' and env[:node]['href']

      node = env[:node]

      rel = (node['rel'] || '').split(' ') & ['tag']
      unless env[:config][:outgoing] && TagManager.instance.local_url?(node['href'])
        rel += ['nofollow', 'noopener', 'noreferrer']
      end
      node['rel'] = rel.join(' ')
    end

    UNSUPPORTED_HREF_TRANSFORMER = lambda do |env|
      return unless env[:node_name] == 'a'

      current_node = env[:node]

      scheme = begin
        if current_node['href'] =~ Sanitize::REGEX_PROTOCOL
          Regexp.last_match(1).downcase
        else
          :relative
        end
      end

      current_node.replace(current_node.text) unless LINK_PROTOCOLS.include?(scheme)
    end

    UNSUPPORTED_ELEMENTS_TRANSFORMER = lambda do |env|
      return unless %w(h1 h2 h3 h4 h5 h6 blockquote pre ul ol li).include?(env[:node_name])

      current_node = env[:node]

      case env[:node_name]
      when 'li'
        current_node.traverse do |node|
          next unless %w(p ul ol li).include?(node.name)

          node.add_next_sibling('<br>') if node.next_sibling
          node.replace(node.children) unless node.text?
        end
      else
        current_node.name = 'p'
      end
    end

    MASTODON_STRICT ||= freeze_config(
      elements: %w(p br span a abbr del pre blockquote code b strong u sub sup i em h1 h2 h3 h4 h5 ul ol li),

      attributes: {
        'a'          => %w(href rel class title),
        'span'       => %w(class),
        'abbr'       => %w(title),
        'blockquote' => %w(cite),
        'ol'         => %w(start reversed),
        'li'         => %w(value),
      },

      add_attributes: {
        'a' => {
          'target' => '_blank',
        },
      },

      protocols: {
        'a'          => { 'href' => LINK_PROTOCOLS },
        'blockquote' => { 'cite' => LINK_PROTOCOLS },
      },

      transformers: [
        CLASS_WHITELIST_TRANSFORMER,
        IMG_TAG_TRANSFORMER,
        UNSUPPORTED_HREF_TRANSFORMER,
        LINK_REL_TRANSFORMER,
      ]
    )

    MASTODON_OEMBED ||= freeze_config(
      elements: %w(audio embed iframe source video),

      attributes: {
        'audio'  => %w(controls),
        'embed'  => %w(height src type width),
        'iframe' => %w(allowfullscreen frameborder height scrolling src width),
        'source' => %w(src type),
        'video'  => %w(controls height loop width),
      },

      protocols: {
        'embed'  => { 'src' => HTTP_PROTOCOLS },
        'iframe' => { 'src' => HTTP_PROTOCOLS },
        'source' => { 'src' => HTTP_PROTOCOLS },
      },

      add_attributes: {
        'iframe' => { 'sandbox' => 'allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox allow-forms' },
      }
    )
  end
end
