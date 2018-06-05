module Twine
  module Formatters
    class Django < Abstract
      def format_name
        'django'
      end

      def extension
        '.po'
      end

      def default_file_name
        'strings.po'
      end

      def read(io, lang)
        comment_regex = /#\. *"?(.*)"?$/
        key_regex = /msgid *"(.*)"$/
        value_regex = /msgstr *"(.*)"$/m

        last_comment = nil
        while line = io.gets          
          comment_match = comment_regex.match(line)
          if comment_match
            comment = comment_match[1]
          end

          key_match = key_regex.match(line)
          if key_match
            key = key_match[1].gsub('\\"', '"')
          end
          value_match = value_regex.match(line)
          if value_match
            value = value_match[1].gsub(/"\n"/, '').gsub('\\"', '"')
          end

          if key and key.length > 0 and value and value.length > 0
            set_translation_for_key(key, lang, value)
            if comment and comment.length > 0 and !comment.start_with?("--------- ")
              set_comment_for_key(key, comment)
            end
            key = nil
            value = nil
            comment = nil
          end
        end
      end

      def format_file(lang)
        @default_lang = @twine_file.language_codes[0]
        result = super
        @default_lang = nil
        result
      end

      def format_header(lang)
        "##\n # Django Strings File\n # Generated by Twine #{Twine::VERSION}\n # Language: #{lang}\nmsgid \"\"\nmsgstr \"\"\n\"Content-Type: text/plain; charset=UTF-8\\n\""
      end

      def format_section_header(section)
        "#--------- #{section.name} ---------#\n"
      end

      def format_definition(definition, lang)
        [format_comment(definition, lang), format_base_translation(definition), format_key_value(definition, lang)].compact.join
      end

      def format_base_translation(definition)
        base_translation = definition.translations[@default_lang]
        "# base translation: \"#{base_translation}\"\n" if base_translation
      end

      def key_value_pattern
        "msgid \"%{key}\"\n" +
        "msgstr \"%{value}\"\n"
      end

      def format_comment(definition, lang)
        "#. #{escape_quotes(definition.comment)}\n" if definition.comment
      end

      def format_key(key)
        escape_quotes(key)
      end

      def format_value(value)
        escape_quotes(value)
      end
    end
  end
end

Twine::Formatters.formatters << Twine::Formatters::Django.new
