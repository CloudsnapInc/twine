module Twine
  class TwineDefinition
    PLURAL_KEYS = %w(zero one two few many other)

    attr_reader :key
    attr_accessor :comment
    attr_accessor :tags
    attr_reader :translations
    attr_reader :plural_translations
    attr_reader :is_plural
    attr_accessor :reference
    attr_accessor :reference_key
    attr_accessor :is_plural # setter method

    def initialize(key)
      @key = key
      @comment = nil
      @tags = nil
      @translations = {}
      @plural_translations = {}
      @is_plural = false  # Initialize is_plural to false by default

      #puts "TwineDefinition: initialize #{key}"
    end

    def plural_translation_for_lang(lang)
      #puts "TwineDefinition: plural_translation_for_lang #{lang}"
      if @plural_translations.has_key? lang
        @plural_translations[lang].dup
      end
    end

    def is_plural?
      #puts "TwineDefinition: is_plural #{@key} #{!@plural_translations.empty?}"
      !@plural_translations.empty?
    end

    def comment
      raw_comment || (reference.comment if reference)
    end

    def raw_comment
      @comment
    end

    # [['tag1', 'tag2'], ['~tag3']] == (tag1 OR tag2) AND (!tag3)
    def matches_tags?(tags, include_untagged)
      #puts "TwineDefinition: matches_tags #{tags}"
      if tags == nil || tags.empty?  # The user did not specify any tags. Everything passes.
        return true
      elsif @tags == nil  # This definition has no tags -> check reference (if any)
        return reference ? reference.matches_tags?(tags, include_untagged) : include_untagged
      elsif @tags.empty?
        return include_untagged
      else
        return tags.all? do |set|
          regular_tags, negated_tags = set.partition { |tag| tag[0] != '~' }
          negated_tags.map! { |tag| tag[1..-1] }
          matches_regular_tags = (!regular_tags.empty? && !(regular_tags & @tags).empty?)
          matches_negated_tags = (!negated_tags.empty? && (negated_tags & @tags).empty?)
          matches_regular_tags or matches_negated_tags
        end
      end

      return false
    end

    def translation_for_lang(lang)
     # puts "TwineDefinition: translation_for_lang #{lang}"
#       puts "======== Printing Translations: ========"
#       @translations.each do |lang, translation|
#         puts "#{lang}: #{translation}"
#       end
#
#       puts "======== Printing Plural Translations: ========"
#       @plural_translations.each do |lang, translation|
#         puts "#{lang}: #{translation}"
#       end

      if @plural_translations.has_key?(lang)
        plural_translation = @plural_translations[lang]
       # puts "+++++ plural_translation #{plural_translation}"
        return plural_translation if plural_translation
      end

      translation = [lang].flatten.map { |l| @translations[l] }.compact.first

      translation = reference.translation_for_lang(lang) if translation.nil? && reference

      return translation
    end
  end

  class TwineSection
    attr_reader :name
    attr_reader :definitions

    def initialize(name)
      @name = name
      @definitions = []
    end
  end

  class TwineFile
    attr_reader :sections
    attr_reader :definitions_by_key
    attr_reader :language_codes

    private

    def match_key(text)
      match = /^\[(.+)\]$/.match(text)
      return match[1] if match
    end

    def write_value_for_lang(definition, f, section, used_definition)
      @language_codes[0..-1].sort.each do |lang|
        value = get_value(definition, lang, f)
        if value != nil && value.include?("@string/")
          used_definition = process_value_with_reference(definition, value, lang, f, section)
          value = get_value(used_definition, lang, f)
        end

        if !value && !used_definition.reference_key
          Twine::stdout.puts "WARNING: #{used_definition.key} does not exist in developer language '#{lang}'"
        end

        if used_definition.reference_key
          f.puts "\t\tref = #{used_definition.reference_key}"
        end
        if used_definition.tags && used_definition.tags.length > 0
          tag_str = used_definition.tags.join(',')
          f.puts "\t\ttags = #{tag_str}"
        end
        if used_definition.raw_comment && used_definition.raw_comment.length > 0
          f.puts "\t\tcomment = #{used_definition.raw_comment}"
        end
        write_value(used_definition, lang, f)
      end
    end

    def process_value_with_reference(definition, value, lang, f, section)
      #puts "TwineFile: process_value_with_reference #{definition} - #{value}"
      referenced_key = value.sub(/^@string\//, '')
      referenced_definition = section.definitions.find { |defn| defn.key == referenced_key }
      if referenced_definition.nil?
        return definition # Return the current definition if referenced_definition is nil
      else
        value = get_value(referenced_definition, lang, f)
        if value != nil && value.include?("@string/")
          return process_value_with_reference(referenced_definition, value, lang, f, section)
        else
          return referenced_definition
        end
      end
    end

    public

    def initialize
      @sections = []
      @definitions_by_key = {}
      @language_codes = []
    end

    def add_language_code(code)
      if @language_codes.length == 0
        @language_codes << code
      elsif !@language_codes.include?(code)
        dev_lang = @language_codes[0]
        @language_codes << code
        @language_codes.delete(dev_lang)
        @language_codes.sort!
        @language_codes.insert(0, dev_lang)
      end
    end

    def set_developer_language_code(code)
      @language_codes.delete(code)
      @language_codes.insert(0, code)
    end

    def read(path)
      #puts "TwineFile: read #{path}"
      if !File.file?(path)
        raise Twine::Error.new("File does not exist: #{path}")
      end

      File.open(path, 'r:UTF-8') do |f|
        line_num = 0
        current_section = nil
        current_definition = nil
        while line = f.gets
          parsed = false
          line.strip!
          line_num += 1

          if line.length == 0
            next
          end

          if line.length > 4 && line[0, 2] == '[['
            match = /^\[\[(.+)\]\]$/.match(line)
            if match
              current_section = TwineSection.new(match[1])
              @sections << current_section
              parsed = true
            end
          elsif line.length > 2 && line[0, 1] == '['
            key = match_key(line)
            if key
              current_definition = TwineDefinition.new(key)
              @definitions_by_key[current_definition.key] = current_definition
              if !current_section
                current_section = TwineSection.new('')
                @sections << current_section
              end
              current_section.definitions << current_definition
              parsed = true
            end
          else
            match = /^([^:=]+)(?::([^=]+))?=(.*)$/.match(line)
            if match
              key = match[1].strip
              plural_key = match[2].to_s.strip
              value = match[3].strip
              
              value = value[1..-2] if value[0] == '`' && value[-1] == '`'

              case key
              when 'comment'
                current_definition.comment = value
              when 'tags'
                current_definition.tags = value.split(',')
              when 'ref'
                current_definition.reference_key = value if value
              else
                if !@language_codes.include? key
                  add_language_code(key)
                end
                # Providing backward compatibility
                # for formatters without plural support
                if plural_key.empty? || plural_key == 'other'
                  current_definition.translations[key] = value
                end
                if !plural_key.empty?
                  if !TwineDefinition::PLURAL_KEYS.include? plural_key
                    warn("Unknown plural key #{plural_key}")
                    next
                  end
                  (current_definition.plural_translations[key] ||= {})[plural_key] = value
                end
              end
              parsed = true
            end
          end

          if !parsed
            raise Twine::Error.new("Unable to parse line #{line_num} of #{path}: #{line}")
          end
        end
      end

      # resolve_references
      @definitions_by_key.each do |key, definition|
        next unless definition.reference_key
        definition.reference = @definitions_by_key[definition.reference_key]
      end
    end

    def write(path)
      #puts "TwineFile: write #{path}"
      dev_lang = @language_codes[0]

      File.open(path, 'w:UTF-8') do |f|
        @sections.each do |section|
          if f.pos > 0
            f.puts ''
          end

          f.puts "[[#{section.name}]]"

          section.definitions.each do |definition|
            f.puts "\t[#{definition.key}]"
            write_value_for_lang(definition, f, section, definition)
          end
        end
      end
    end

    private

    def write_value(definition, language, file)
      #puts "TwineFile: write_value #{definition.key} - #{language}"
      #puts "TwineFile: is_plural #{definition.is_plural}"
      if definition.is_plural
        # Handle plural translations
        #puts "TwineFile: is_plural"
        plural_translations = definition.plural_translations[language]
        return nil unless plural_translations

        plural_translations.each do |key, translation|
          #puts "TwineFile: plural_translations: lang #{language}:#{key} = #{translation} "
          file.puts "\t\t#{language}:#{key} = #{translation}"
        end
      else
        # Handle non-plural translations
        value = definition.translations[language]
        return nil unless value

        if value[0] == ' ' || value[-1] == ' ' || (value[0] == '`' && value[-1] == '`')
          value = '`' + value + '`'
        end

        file.puts "\t\t#{language} = #{value}"
      end

      return value
    end

    def get_value(definition, language, file)
      #puts "TwineFile: get_value #{definition} - #{language} - #{file}"
      value = definition.translations[language]
      return nil unless value

      if value[0] == ' ' || value[-1] == ' ' || (value[0] == '`' && value[-1] == '`')
        value = '`' + value + '`'
      end

      return value
    end

  end
end
