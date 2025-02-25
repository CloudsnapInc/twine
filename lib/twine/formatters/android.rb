# encoding: utf-8
require 'cgi'
require 'rexml/document'

module Twine
  module Formatters
    class Android < Abstract
      include Twine::Placeholders

      SUPPORTS_PLURAL = true
      LANG_CODES = Hash[
        'zh' => 'zh-Hans',
        'zh-CN' => 'zh-Hans',
        'zh-HK' => 'zh-Hant',
        'en-GB' => 'en-GB',
        'in' => 'id'
      ]

      def format_name
        'android'
      end

      def extension
        '.xml'
      end

      def can_handle_directory?(path)
        Dir.entries(path).any? { |item| /^values.*$/.match(item) }
      end

      def default_file_name
        'strings.xml'
      end

      def determine_language_given_path(path)
        path_arr = path.split(File::SEPARATOR)
        path_arr.each do |segment|
          if segment == 'values'
            return "en"
          else
            # The language is defined by a two-letter ISO 639-1 language code, optionally followed by a two letter ISO 3166-1-alpha-2 region code (preceded by lowercase "r").
            # see http://developer.android.com/guide/topics/resources/providing-resources.html#AlternativeResources
            match = /^values-([a-z]{2}(-r[a-z]{2})?)$/i.match(segment)

            if match
              lang = match[1].sub('-r', '-')
              return LANG_CODES.fetch(lang, lang)
            end
          end
        end

        return super
      end

      def should_include_definition(definition, lang)
        # puts "should_include_definition #{!definition.is_plural? && super}"
        return true
      end

      def format_plural_keys(key, plural_hash)
        result = "\t<plurals name=\"#{key}\">\n"
        result += plural_hash.map{|quantity,value| "\t#{' ' * 2}<item quantity=\"#{quantity}\">#{value}</item>"}.join("\n")
        result += "\n\t</plurals>"
      end

      def output_path_for_language(lang)
        if lang == @twine_file.language_codes[0]
          "values"
        else
          "values-#{lang}".gsub(/-(\p{Lu})/, '-r\1')
        end
      end

      def set_translation_for_key(key, lang, value, is_plural)
        if is_plural
          # Handle the case when is_plural is true (value is a Hash)
          updated_value = {}
          value.each do |quantity, text|
            text = CGI.unescapeHTML(text)
            text.gsub!('\\\'', '\'')
            text.gsub!('\\"', '"')
            text.gsub("\n", "\\n")
            text = convert_placeholders_from_android_to_twine(text) # Apply the conversion
            text.gsub!('\@', '@')
            text.gsub!(/(\\u0020)*|(\\u0020)*\z/) { |spaces| ' ' * (spaces.length / 6) }
            updated_value[quantity] = text # Replace the old value with the converted one
          end
          super(key, lang, updated_value, is_plural)
        else
          # Handle the case when is_plural is false (value is a String)
          value = CGI.unescapeHTML(value)
          value.gsub!('\\\'', '\'')
          value.gsub!('\\"', '"')
          value.gsub("\n", "\\n")
          value = convert_placeholders_from_android_to_twine(value)
          value.gsub!('\@', '@')
          value.gsub!(/(\\u0020)*|(\\u0020)*\z/) { |spaces| ' ' * (spaces.length / 6) }
          super(key, lang, value, is_plural)
        end
      end

      def read(io, lang)
        document = REXML::Document.new io, :compress_whitespace => %w{ string }
        document.context[:attribute_quote] = :quote
        comment = nil
        document.root.children.each do |child|
          if child.is_a? REXML::Comment
            content = child.string.strip
            content.gsub!(/[\s]+/, ' ')
            comment = content if content.length > 0 and not content.start_with?("SECTION:")
          elsif child.is_a? REXML::Element
            next unless child.name == 'string' || 'plurals'

            key = child.attributes['name']

            if child.name == 'string'
              content = child.children.map(&:to_s).join
              set_translation_for_key(key, lang, content, false)
              set_comment_for_key(key, comment) if comment
            elsif child.name == 'plurals'
              plural_values = {} # Create a map to store plurals quantity to value

              child.children.each do |item|
                if item.is_a? REXML::Element
                  item.children.each_with_index do |text, index|
                    quantity = item.attributes["quantity"] # zero, one, other, etc.
                    value = text.to_s
                    plural_values[quantity] = value # Store the quantity to value mapping
                  end
                end
              end

              set_translation_for_key(key, lang, plural_values, true) # Pass the map as content
            end
            comment = nil
          end 
        end
      end

      def format_header(lang)
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
      end

      def format_sections(twine_file, lang)
        result = '<resources>'
        
        result += super + "\n"

        result += "</resources>\n"
      end

      def format_section_header(section)
        nil
      end

      def format_comment(definition, lang)
        "    <!-- #{definition.comment.gsub('--', '—')} -->\n" if definition.comment
      end

      def key_value_pattern
        "    <string name=\"%{key}\">%{value}</string>"
      end

      def gsub_unless(text, pattern, replacement)
        text.gsub(pattern) do |match|
          match_start_position = Regexp.last_match.offset(0)[0]
          yield(text[0, match_start_position]) ? match : replacement
        end
      end

      # http://developer.android.com/guide/topics/resources/string-resource.html#FormattingAndStyling
      def escape_value(value)
        inside_cdata = /<\!\[CDATA\[((?!\]\]>).)*$/              # opening CDATA tag ('<![CDATA[') not followed by a closing tag (']]>')
        inside_opening_tag = /<(a|font|span|p)\s?((?!>).)*$/     # tag start ('<a ', '<font ', '<span ' or '<p ') not followed by a '>'

        # escape double and single quotes and & signs
        value = gsub_unless(value, '"', '\\"') { |substring| substring =~ inside_cdata || substring =~ inside_opening_tag }
        value = gsub_unless(value, "'", "\\'") { |substring| substring =~ inside_cdata }
        value = gsub_unless(value, /&/, '&amp;') { |substring| substring =~ inside_cdata || substring =~ inside_opening_tag }

        # if `value` contains a placeholder, escape all angle brackets
        # if not, escape opening angle brackes unless it's a supported styling tag
        # https://github.com/scelis/twine/issues/212
        # https://stackoverflow.com/questions/3235131/#18199543
        if number_of_twine_placeholders(value) > 0 or @options[:escape_all_tags]
          # matches all `<` but <![CDATA
          angle_bracket = /<(?!(\/?(\!\[CDATA)))/
        else
          # matches all '<' but <b>, <em>, <i>, <cite>, <dfn>, <big>, <small>, <font>, <tt>, <s>,
          # <strike>, <del>, <u>, <super>, <sub>, <ul>, <li>, <br>, <div>, <span>, <p>, <a>
          # and <![CDATA
          angle_bracket = /<(?!(\/?(b|em|i|cite|dfn|big|small|font|tt|s|strike|del|u|super|sub|ul|li|br|div|span|p|a|\!\[CDATA)))/
        end
        value = gsub_unless(value, angle_bracket, '&lt;') { |substring| substring =~ inside_cdata }

        # escape non resource identifier @ signs (http://developer.android.com/guide/topics/resources/accessing-resources.html#ResourcesFromXml)
        resource_identifier_regex = /@(?!([a-z\.]+:)?[a-z+]+\/[a-zA-Z_]+)/   # @[<package_name>:]<resource_type>/<resource_name>
        value.gsub(resource_identifier_regex, '\@')
      end

      # see http://developer.android.com/guide/topics/resources/string-resource.html#FormattingAndStyling
      # however unescaped HTML markup like in "Welcome to <b>Android</b>!" is stripped when retrieved with getString() (http://stackoverflow.com/questions/9891996/)
      def format_value(value)
        value = value.dup

        # convert placeholders (e.g. %@ -> %s)
        value = convert_placeholders_from_twine_to_android(value)

        # capture xliff tags and replace them with a placeholder
        xliff_tags = []
        value.gsub! /<xliff:g.+?<\/xliff:g>/ do
          xliff_tags << $&
          'TWINE_XLIFF_TAG_PLACEHOLDER'
        end

        # escape everything outside xliff tags
        value = escape_value(value)

        # put xliff tags back into place
        xliff_tags.each do |xliff_tag|
          # escape content of xliff tags
          xliff_tag.gsub! /(<xliff:g.*?>)(.*)(<\/xliff:g>)/ do "#{$1}#{escape_value($2)}#{$3}" end
          value.sub! 'TWINE_XLIFF_TAG_PLACEHOLDER', xliff_tag
        end
        
        # replace beginning and end spaces with \u0020. Otherwise Android strips them.
        value.gsub(/\A *| *\z/) { |spaces| '\u0020' * spaces.length }
      end

    end
  end
end

Twine::Formatters.formatters << Twine::Formatters::Android.new
