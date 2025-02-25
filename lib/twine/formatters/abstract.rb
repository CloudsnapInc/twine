require 'fileutils'

module Twine
  module Formatters
    class Abstract
      SUPPORTS_PLURAL = false
      LANGUAGE_CODE_WITH_OPTIONAL_REGION_CODE = "[a-z]{2}(?:-[A-Za-z]{2})?"

      attr_accessor :twine_file
      attr_accessor :options

      def initialize
        @twine_file = TwineFile.new
        @options = {}
      end

      def format_name
        raise NotImplementedError.new("You must implement format_name in your formatter class.")
      end

      def extension
        raise NotImplementedError.new("You must implement extension in your formatter class.")
      end

      def can_handle_directory?(path)
        Dir.entries(path).any? { |item| /^.+#{Regexp.escape(extension)}$/.match(item) }
      end

      def default_file_name
        raise NotImplementedError.new("You must implement default_file_name in your formatter class.")
      end

      def set_translation_for_key(key, lang, value, is_plural)
        #puts "!!!!!!! Abstract: set_translation_for_key key #{key} || #{value}"

        if @twine_file.definitions_by_key.include?(key)
          #puts "!!!!!!! Abstract: set_translation_for_key - @twine_file.definitions_by_key.include?(key)"
          definition = @twine_file.definitions_by_key[key]
          reference = @twine_file.definitions_by_key[definition.reference_key] if definition.reference_key

          if !reference or value != reference.translations[lang]
           # puts "!!!!!!! Abstract: set_translation_for_key - @twine_file.definitions_by_key.include?(key) - SET"
            if is_plural
              definition.is_plural = is_plural
              definition.plural_translations[lang] = value
            else
              definition.translations[lang] = value
            end
          end
        elsif @options[:consume_all]
         # puts "!!!!!!! Abstract: set_translation_for_key - consume_all"
          current_section = @twine_file.sections.find { |s| s.name == 'Uncategorized' }
          unless current_section
            current_section = TwineSection.new('Uncategorized')
            @twine_file.sections.insert(0, current_section)
          end
          current_definition = TwineDefinition.new(key)
          current_definition.is_plural = is_plural
          current_section.definitions << current_definition
          
          if @options[:tags] && @options[:tags].length > 0
            current_definition.tags = @options[:tags]            
          end
          
          @twine_file.definitions_by_key[key] = current_definition
          if is_plural
            #puts "----- is plural save to fine #{value}"
            @twine_file.definitions_by_key[key].plural_translations[lang] = value
          else
            #puts "----- is NOT plural save to fine #{value}"
            @twine_file.definitions_by_key[key].translations[lang] = value
          end
        else
         # Twine::stdout.puts "WARNING: '#{key}' not found in twine file."
        end
        if !@twine_file.language_codes.include?(lang)
          @twine_file.add_language_code(lang)
        end
      end

      def set_comment_for_key(key, comment)
       # puts "Abstract: set_comment_for_key key #{key} || #{comment}"
        return unless @options[:consume_comments]
        
        if @twine_file.definitions_by_key.include?(key)
          definition = @twine_file.definitions_by_key[key]
          
          reference = @twine_file.definitions_by_key[definition.reference_key] if definition.reference_key

          if !reference or comment != reference.raw_comment
            definition.comment = comment
          end
        end
      end

      def determine_language_given_path(path)
        #puts "Abstract: determine_language_given_path #{path}"
        only_language_and_region = /^#{LANGUAGE_CODE_WITH_OPTIONAL_REGION_CODE}$/i
        basename = File.basename(path, File.extname(path))
        return basename if basename =~ only_language_and_region
        return basename if @twine_file.language_codes.include? basename
        
        path.split(File::SEPARATOR).reverse.find { |segment| segment =~ only_language_and_region }
      end

      def output_path_for_language(lang)
        lang
      end

      def read(io, lang)
        raise NotImplementedError.new("You must implement read in your formatter class.")
      end

      def format_file(lang)
        #puts "Abstract: format_file #{lang}"
        output_processor = Processors::OutputProcessor.new(@twine_file, @options)
        processed_twine_file = output_processor.process(lang)

        return nil if processed_twine_file.definitions_by_key.empty?

        header = format_header(lang)
        result = ""
        result += header + "\n" if header
        result += format_sections(processed_twine_file, lang)
      end

      def format_header(lang)
      end

      def format_sections(twine_file, lang)
        sections = twine_file.sections.map { |section| format_section(section, lang) }
        sections.compact.join("\n")
      end

      def format_section_header(section)
      end

      def should_include_definition(definition, lang)
        return !definition.translation_for_lang(lang).nil?
      end

      def format_section(section, lang)
        definitions = section.definitions.select { |definition| should_include_definition(definition, lang) }
        return if definitions.empty?

        result = ""

        if section.name && section.name.length > 0
          section_header = format_section_header(section)
          result += "\n#{section_header}" if section_header
        end

        definitions.map! { |definition| format_definition(definition, lang) }
        definitions.compact! # remove nil definitions
        definitions.map! { |definition| "\n#{definition}" }  # prepend newline
        result += definitions.join
      end

      def format_definition(definition, lang)
        #puts "Abstract: format_definition #{definition}"
        formatted_definition = [format_comment(definition, lang)]
        if self.class::SUPPORTS_PLURAL && definition.is_plural?
          formatted_definition << format_plural(definition, lang)
        else
          formatted_definition << format_key_value(definition, lang)
        end
        formatted_definition.compact.join
      end

      def format_comment(definition, lang)
      end

      def format_key_value(definition, lang)
        #puts "Abstract: format_key_value #{definition}"
        value = definition.translation_for_lang(lang)
        key_value_pattern % { key: format_key(definition.key.dup), value: format_value(value.dup) }
      end

      def format_plural(definition, lang)
        #puts "Abstract: format_plural #{definition}"
        plural_hash = definition.plural_translation_for_lang(lang)
        if plural_hash
          format_plural_keys(definition.key.dup, plural_hash)
        end
      end

      def format_plural_keys(key, plural_hash)
        #puts "Abstract: format_plural_keys #{key}"
        raise NotImplementedError.new("You must implement format_plural_keys in your formatter class.")
      end

      def key_value_pattern
        raise NotImplementedError.new("You must implement key_value_pattern in your formatter class.")
      end

      def format_key(key)
        key
      end

      def format_value(value)
        value
      end

      def escape_quotes(text)
        text.gsub('"', '\\\\"')
      end
    end
  end
end
