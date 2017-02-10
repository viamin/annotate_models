# == Annotate Routes
#
# Based on:
#
#
#
# Prepends the output of "rake routes" to the top of your routes.rb file.
# Yes, it's simple but I'm thick and often need a reminder of what my routes
# mean.
#
# Running this task will replace any exising route comment generated by the
# task. Best to back up your routes file before running:
#
# Author:
#  Gavin Montague
#  gavin@leftbrained.co.uk
#
# Released under the same license as Ruby. No Support. No Warranty.
#
module AnnotateRoutes
  PREFIX = '== Route Map'.freeze
  PREFIX_MD = '## Route Map'.freeze
  HEADER_ROW = ['Prefix', 'Verb', 'URI Pattern', 'Controller#Action']

  class << self
    def content(line, maxs, options = {})
      return line.rstrip unless options[:format_markdown]

      line.each_with_index.map do |elem, index|
        min_length = maxs.map { |arr| arr[index] }.max || 0

        sprintf("%-#{min_length}.#{min_length}s", elem.tr('|', '-'))
      end.join(' | ')
    end

    def header(options = {})
      routes_map = app_routes_map(options)

      out = ["# #{options[:format_markdown] ? PREFIX_MD : PREFIX}" + (options[:timestamp] ? " (Updated #{Time.now.strftime('%Y-%m-%d %H:%M')})" : '')]
      out += ['#']
      out += [options[:route_wrapper_open]] if options[:route_wrapper_open]
      return out if routes_map.size.zero?

      maxs = [HEADER_ROW.map(&:size)] + routes_map[1..-1].map { |line| line.split.map(&:size) }

      if options[:format_markdown]
        max = maxs.map(&:max).compact.max

        out += ["# #{content(HEADER_ROW, maxs, options)}"]
        out += ["# #{content(['-' * max, '-' * max, '-' * max, '-' * max], maxs, options)}"]
      else
        out += ["# #{content(routes_map[0], maxs, options)}"]
      end

      out += routes_map[1..-1]
      out += [options[:route_wrapper_close]] if options[:route_wrapper_close]
      out.map { |line| "# #{content(options[:format_markdown] ? line.split(' ') : line, maxs, options)}".rstrip }
    end

    def do_annotations(options = {})
      return unless routes_exists?
      existing_text = File.read(routes_file)

      if write_contents(existing_text, header(options), options)
        puts "#{routes_file} annotated."
      end
    end

    def remove_annotations(options={})
      return unless routes_exists?
      existing_text = File.read(routes_file)
      content, where_header_found = strip_annotations(existing_text)

      content = strip_on_removal(content, where_header_found)

      if write_contents(existing_text, content, options)
        puts "Removed annotations from #{routes_file}."
      end
    end
  end

  private

  def self.app_routes_map(options)
    routes_map = `rake routes`.split(/\n/, -1)

    # In old versions of Rake, the first line of output was the cwd.  Not so
    # much in newer ones.  We ditch that line if it exists, and if not, we
    # keep the line around.
    routes_map.shift if routes_map.first =~ /^\(in \//

    # Skip routes which match given regex
    # Note: it matches the complete line (route_name, path, controller/action)
    if options[:ignore_routes]
      routes_map.reject! { |line| line =~ /#{options[:ignore_routes]}/ }
    end

    routes_map
  end

  def self.routes_file
    @routes_rb ||= File.join('config', 'routes.rb')
  end

  def self.routes_exists?
    routes_exists = File.exists?(routes_file)
    puts "Can't find routes.rb" unless routes_exists

    routes_exists
  end

  def self.write_contents(existing_text, header, options = {})
    content, where_header_found = strip_annotations(existing_text)
    new_content = annotate_routes(header, content, where_header_found, options)

    # Make sure we end on a trailing newline.
    new_content << '' unless new_content.last == ''
    new_text = new_content.join("\n")

    if existing_text == new_text
      puts "#{routes_file} unchanged."
      false
    else
      File.open(routes_file, 'wb') { |f| f.puts(new_text) }
      true
    end
  end

  def self.annotate_routes(header, content, where_header_found, options = {})
    if %w(before top).include?(options[:position_in_routes])
      header = header << '' if content.first != ''
      new_content = header + content
    else
      # Ensure we have adequate trailing newlines at the end of the file to
      # ensure a blank line separating the content from the annotation.
      content << '' unless content.last == ''

      # We're moving something from the top of the file to the bottom, so ditch
      # the spacer we put in the first time around.
      content.shift if where_header_found == :before && content.first == ''

      new_content = content + header
    end

    new_content
  end

  # TODO: write the method doc using ruby rdoc formats
  # where_header_found => This will either be :before, :after, or
  # a number.  If the number is > 0, the
  # annotation was found somewhere in the
  # middle of the file.  If the number is
  # zero, no annotation was found.
  def self.strip_annotations(content)
    real_content = []
    mode = :content
    header_found_at = 0

    content.split(/\n/, -1).each_with_index do |line, line_number|
      if mode == :header && line !~ /\s*#/
        mode = :content
        next unless line == ''
      elsif mode == :content
        if line =~ /^\s*#\s*== Route.*$/
          header_found_at = line_number + 1 # index start's at 0
          mode = :header
        else
          real_content << line
        end
      end
    end

    where_header_found(real_content, header_found_at)
  end

  def self.where_header_found(real_content, header_found_at)
    # By default assume the annotation was found in the middle of the file

    # ... unless we have evidence it was at the beginning ...
    return real_content, :before if header_found_at == 1

    # ... or that it was at the end.
    return real_content, :after if header_found_at >= real_content.count

    # and the default
    return real_content, header_found_at
  end

  def self.strip_on_removal(content, where_header_found)
    if where_header_found == :before
      content.shift while content.first == ''
    elsif where_header_found == :after
      content.pop while content.last == ''
    end

    # TODO: If the user buried it in the middle, we should probably see about
    # TODO: preserving a single line of space between the content above and
    # TODO: below...
    content
  end
end
