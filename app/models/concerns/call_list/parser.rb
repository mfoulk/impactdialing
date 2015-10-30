class CallList::Parser
  attr_reader :voter_list, :csv_mapping, :results, :batch_size, :cursor

private
  def read_file(&block)
    s3           = AmazonS3.new
    lines        = []
    partial_line = nil

    # todo: handle stream disruption (timeouts => retry, ghosts => you know who to call)
    # todo: handle stream pickup & process continuation
    s3.stream(voter_list.s3path) do |chunk|
      i = 0
      chunk.each_line do |line|
        unless partial_line.nil? and i.zero?
          Rails.logger.debug "Parser partial_line not nil: #{partial_line}"
          # first line of this chunk is last part of current partial_line
          last_part    = line
          line         = "#{partial_line}#{last_part}"
          partial_line = nil
        end

        lines << line
        i += 1
      end

      if lines.last !~ /#{$/}\Z/
        # last line doesn't have newline character
        partial_line = lines.pop
      end

      if lines.size >= batch_size
        yield lines
        lines = []
      end
    end

    yield lines if lines.size > 0
  end

  def csv_options
    {col_sep: voter_list.separator}
  end

  def redis_key(phone)
    voter_list.campaign.dial_queue.households.key(phone)
  end

  def redis_custom_id_register_key(custom_id)
    voter_list.campaign.call_list.custom_id_register_key(custom_id)
  end

  def invalid_row!(csv_row)
    results[:invalid_rows] << CSV.generate_line(csv_row.to_a)
  end

  def invalid_phone!(phone, csv_row)
    results[:invalid_numbers] << phone
    invalid_row!(csv_row)
  end

  def invalid_line!(line)
    results[:invalid_formats] += 1
    # store unparsable lines separate from rows with invalid data
    # so that a simple file can be generated w/out triggering csv exceptions
    results[:invalid_lines] << "#{line}\n"
  end

  def phone_valid?(phone, csv_row)
    unless PhoneNumber.valid?(phone)
      invalid_phone!(phone, csv_row)
      return false
    end

    true
  end

public
  def initialize(voter_list, cursor, results, batch_size)
    @voter_list              = voter_list
    @csv_mapping             = CsvMapping.new(voter_list.csv_to_system_map)
    @batch_size              = batch_size
    @cursor                  = cursor
    @results                 = results
    @results[:use_custom_id] = @csv_mapping.use_custom_id?

    # set from parse_headers
    @header_index_map = {}
    @phone_index      = nil
  end

  def parse_file(&block)
    i = 0
    start_at = nil

    if @cursor > 0
      # continue from previous position
      start_at = @cursor
    end

    read_file do |lines|
      if i.zero?
        parse_headers(lines.shift)
        i     += 1
        @cursor = i
      end

      unless start_at.nil?
        @cursor += lines.size

        if start_at <= cursor
          lines = lines[start_at-@cursor..-1]
          start_at = nil
        else
          next
        end
      end

      keys, data = parse_lines(lines.join)

      @cursor += lines.size

      yield keys, data, @cursor, results
    end
  end

  def parse_headers(line)
    row              = CSV.parse_line(line, csv_options)
    row.each_with_index do |header,i|
      header = Windozer::String.bom_away(header)
      @phone_index              = i if csv_mapping.mapping[header] == 'phone'
      @header_index_map[header] = i
    end
  end

  def parse_lines(lines, &block)
    line_count = lines.size
    rows       = CSV.new(lines, csv_options)
    keys       = []
    data       = []
    lines_arr  = if lines.include?("\r\n")
                   lines.split("\r\n")
                 else
                   lines.split("\n")
                 end
    next_line  = lines_arr.first

    begin
      rows.each_with_index do |row, i|
        next_line = lines_arr[i+1] # capture next line in case #each raises MalformedCSVError
        raw_phone = row[@phone_index]
        phone     = PhoneNumber.sanitize(raw_phone)

        next unless phone_valid?(phone, row)

        # build keys here to maintain cluster support
        keys << redis_key(phone)
        data << [phone, row, i]

        # debugging nil key: #104590114
        if keys.last.nil?
          ImpactPlatform::Metrics.count('imports.parser.nil_redis_key')
          pre = "[CallList::Imports::Parser]"
          p "#{pre} Last redis key was nil."
          p "#{pre} Phone: #{phone}"
          p "#{pre} Current row (#{i}): #{row}"
        end
        # /debugging
      end
    rescue CSV::MalformedCSVError => e
      invalid_line!(next_line)
      retry
    end

    [keys.uniq, data]
  end
end

