require 'json'
require 'set'
require 'time'

RESERVED_KEYS = ['message', 'time', 'level', 'meta', 'action_id', 'pid', 'error', 'backtrace', 'error_class'].to_set

# Pass metadata options as a leading hash. Everything else is
# combined into a single logical hash.
#
# log.error('Something went wrong!')
# log.info('Booting the server on:', :host => host)
# log.error('Something went wrong', e)
# log.error({:id => 'id'}, 'Something went wrong', e, :info => info)
class Chalk::Log::Layout < ::Logging::Layout
  def format(event)
    data = event.data
    time = event.time
    level = event.level

    # Data provided by blocks may not be arrays yet
    data = [data] unless data.kind_of?(Array)
    while data.length > 0 && [nil, true, false].include?(data.last)
      maybe_assert(false, "Ignoring deprecated arguments passed to logger: #{data.inspect}") unless data.last.nil?
      data.pop
    end

    info = data.pop if data.last.kind_of?(Hash)
    error = data.pop if exception?(data.last)
    message = data.pop if data.last.kind_of?(String)
    meta = data.pop if data.last.kind_of?(Hash)

    raise "Invalid leftover arguments: #{data.inspect}" if data.length > 0

    id = meta[:id] if meta
    id ||= action_id

    pid = Process.pid

    event_description = {
      :time => timestamp_prefix(time),
      :level => Chalk::Log::LEVELS[level],
      :action_id => id,
      :message => message,
      :meta => meta,
      :error => error,
      :info => info,
      :pid => pid
    }.reject {|k,v| v.nil?}

    case output_format
    when 'json'
      json_print(event_description)
    when 'pp'
      pretty_print(event_description)
    else
      raise ArgumentError, "Chalk::Log::Config[:output_format] was not set to a valid setting of 'json' or 'pp'."
    end
  end

  private

  def maybe_assert(*args)
    # We don't require Chalk::Tools in order to avoid a cyclic
    # dependency.
    Chalk::Tools::AssertionUtils.assert(*args) if defined?(Chalk::Tools)
  end

  def exception?(object)
    if object.kind_of?(Exception)
      true
    elsif defined?(Mocha::Mock) && object.kind_of?(Mocha::Mock)
      # TODO: better answer than this?
      maybe_assert(Chalk::Tools::TestingUtils.testing?, "Passed a mock even though we're not in the tests", true) if defined?(Chalk::Tools)
      true
    else
      false
    end
  end

  def action_id; defined?(LSpace) ? LSpace[:action_id] : nil; end
  def tagging_disabled; Chalk::Log::Config[:tagging_disabled]; end
  def output_format; Chalk::Log::Config[:output_format]; end
  def tag_without_pid; Chalk::Log::Config[:tag_without_pid]; end
  def tag_with_timestamp; Chalk::Log::Config[:tag_with_timestamp]; end


  def build_message(message, error, info)
    if message && (error || info)
      message << ':'
    end
    message = stringify_info(info, message) if info
    message = stringify_error(error, message) if error
    message || ''
  end

  def append_newline(message)
    message << "\n"
  end

  def stringify_info(info, message)
    addition = info.map do |key, value|
      display(key, value)
    end
    if message
      message + " " + addition.join(' ')
    else
      addition.join(' ')
    end
  end

  # Probably let other types be logged over time, but for now we
  # should make sure that we will can serialize whatever's thrown at
  # us.
  def display(key, value, escape_keys=false)
    key = display_key(key, escape_keys)
    value = display_value(value, key)

    "#{key}=#{value}"
  end

  def display_key(key, escape_keys)
    key = key.to_s
    if escape_keys && (key.start_with?('_') || RESERVED_KEYS.include?(key))
      "_#{key}"
    else
      key
    end
  end

  def display_value(value, key)
    begin
      # Use an Array (and trim later) because Ruby's JSON generator
      # requires an array or object.
      dumped = JSON.respond_to?(:unsafe_generate) ? JSON.unsafe_generate([value]) : JSON.generate([value])
      value = dumped[1...-1] # strip off surrounding brackets
    rescue
      value = value.inspect
    rescue => e
      e.message << " (while generating display for #{key})"
      raise
    end

    value = value[1...-1] if value =~ /\A"[A-Z]\w*"\z/ # non-numeric simple strings that start with a capital don't need quotes

    value
  end

  def stringify_error(error, message)
    backtrace = error.backtrace || ['(no backtrace)']
    message = message ? message + " " : ""
    message << display(:error_class, error.class.to_s) << " "
    message << display(:error, error.to_s)
    message << "\n#{Chalk::Log::Utils.format_backtrace(backtrace)}"
  end

  def json_print(event_description)
    JSON.generate(event_description) + "\n"
  end

  def pretty_print(event_description)
    event_description[:message] = build_message(event_description[:message], event_description[:error], event_description[:info])
    append_newline(event_description[:message])
    return event_description[:message] if tagging_disabled

    add_tags_and_new_line(event_description[:message], event_description[:time], event_description)
  end

  def add_tags_and_new_line(message, time, event_description)
    tags = []
    tags << event_description[:pid] unless tag_without_pid
    tags << event_description[:action_id] if event_description[:action_id]

    if tags.length > 0
      prefix = "[#{tags.join('|')}] "
    else
      prefix = ''
    end
    prefix = "[#{time}] #{prefix}" if tag_with_timestamp

    out = ''
    message.split("\n").each do |line|
      out << prefix << line << "\n"
    end
    out
  end

  def timestamp_prefix(now)
    now_fmt = now.strftime("%Y-%m-%d %H:%M:%S")
    ms_fmt = sprintf("%06d", now.usec)
    "#{now_fmt}.#{ms_fmt}"
  end
end
