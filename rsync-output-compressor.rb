#!/usr/bin/env ruby
 
require 'optparse'

VERSION = "0.9"

#===============================================================
# parse the options
#===============================================================

full_filename  = nil
rules_filename = nil
group_mode     = false
sort_results   = false

OptionParser.new do |options|
  # This banner is the first line of your help documentation.
  options.set_banner "rsync-output-compressor v#{VERSION} - (c) 2014 Blommers IT. (MIT Licensed)\n" \
  "Compresses rsync -v output to a more human friendly (and smaller format)\n"\
  "\n" \
  "Usage: rsync -v ... | rsync-output-compressor --rules=rules.txt [options] \n" \
  # Separator just adds a new line with the specified text.
  options.separator ""
  options.separator "Specific options:"
 
  options.on("-f", "--full FILENAME", String, "A file that is going to contain the full output") do |name|
    full_filename = name 
  end
 
  options.on("-r", "--rules FILENAME", String, "The rules file (required)") do |name|
    rules_filename = name 
  end

  options.on("-g", "--group", "Group the results together") do |name|
    group_mode = true
  end

  options.on("-s", "--sort", "Sort the results (enables group mode!)") do |name|
    sort_results = true
    group_mode = true  
  end

  options.on_tail("-h", "--help", "You've already found it!!") do
    $stderr.puts options
    exit 1
  end
end.parse!


# extra checks 
if !rules_filename
  $stderr.puts "This script requires a rules file! (see --help)"
  exit 1
end


#===============================================================
# Read the filters
#===============================================================

filters = IO.read(rules_filename).split("\n").map{|l| l.chomp.strip}.reject{|l|l.length==0|| l[0]=='#'}

# create the full-output file if requested
full_outputfile = nil
if full_filename
  full_outputfile = File.open( full_filename, 'w' ) 
end


#===============================================================
# Output processing
#===============================================================

# General output handling
# It sends data (or lines) to output handler
class StreamOutput

  attr_accessor :out

  def initialize( out )
    @out = out 
  end

  def emit_line( line, columns )
    str = ""
    columns.each do |column|
      str << " #{column}".rjust(7)
    end
    str << " "  
    str << line
    str << "\n"
    out <<  str
  end


  def emit_data( line, fields )
    emit_line( line, [ 
      (fields[:changed] != 0 ? "#{fields[:changed]}" : ""),
      (fields[:deleted] != 0 ? "-#{fields[:deleted]}" : "")
    ])
  end

  def flush
  end

end


# The group output handler groups the data together.
# Which can result in more memory usage, but groups the lines togeter
class GroupOutput < StreamOutput

  attr_accessor :groups, :sort

  def initialize( out, sort )
    super( out )
    @sort = sort
    @groups = {}
  end

  def emit( line, fields )
    @groups[line] = { changed: 0, deleted: 0 } if !@groups[line]
    @groups[line][:changed] += fields[:changed]
    @groups[line][:deleted] += fields[:deleted]
  end


  def flush
    keys = groups.keys 
    keys.sort! if sort
    keys.each do |line|
      emit_data( line, groups[line] )
    end
    @groups = {}
  end

end


#===============================================================
# Filtering
#===============================================================

# This is the base class that performs the filtering
# It detects the start and end of the increment filelist and 
# groups lines together when the filter stays the same (for streaming mode)
class LineFilter

  attr_reader :filters
  attr_reader :out

  attr_accessor :state_filtering
  attr_accessor :active_filter
  attr_accessor :active_totals

  # initializes the filter 
  # filters
  def initialize( filters, out)  
    @filters = filters.map{ |l| l.split('/') } 
    @out = out 
    @active_filter = nil
    @active_totals  = nil
    @state_filtering = false
  end


  # checks if the given fields are matched with the given filter
  def matches_filter?( fields, filter )
    return false if fields.length < filter.length 

    # find a match
    filter.each_with_index do |filter_field,index|
      return false if filter_field[0] != '*'  && filter_field != fields[index]
    end
    true
  end

    
  # finds the first matching filter for these fields (fields is a split line on path-separator )
  def find_filter( fields )
    filters.each do |filter|
      return filter if matches_filter?( fields, filter)
    end   
    false
  end  


  # builds a 'matched' filter from the given filter and fields
  # it interpolates all '*' and '*!' to the correct grouping filter! 
  #
  # For example: (the real arguments are arrays of path-parts!! )
  #   fields = /home/user/public_html/index.html
  #
  # Results in:  ( filter.join('/') => result.join('/') )
  #   /home/*/public_html/   =>   /home/user/public_html/
  #   /home/*!/public_html/  =>   /home/*/public_html/
  #
  # PRE: filter.length <= fields.length  
  def build_matched_filter( filter, fields )
    result = []
    filter.each_with_index do |filter_field,index|
      result << (filter_field == "*!" ? "*" : fields[index])
    end
    result
  end


  # filters the given line
  def filter_line( line )
    # check it's a deleting operation
    items = line.split(/^deleting /)
    deleting = items.length > 1
    filename = items.last.chomp 
    fields   = filename.split('/')

    # when there's a filter active, we need to adjust the totals
    if active_filter
      # does it match the active filter (just adjust thet toals)
      if matches_filter?( fields, active_filter ) 
        self.active_totals[:deleted] += 1 if deleting
        self.active_totals[:changed] += 1 if !deleting
        return
      end

      # no match, flush the filters!
      flush_active_filter
    end

    # find a matching filter
    filter = find_filter( fields )
    if filter 
      self.active_filter = build_matched_filter( filter, fields )  #fields.slice(0,filter.length)  # only match the filter part
      self.active_totals = { deleted: 0, changed: 0 } 
      self.active_totals[:deleted] += 1 if deleting
      self.active_totals[:changed] += 1 if !deleting

    # nothing?? then just emit it
    else 
      out.emit fields.join('/'), { deleted: deleting ? 1 : 0, changed: deleting ? 0 : 1 }
    end

  end


  # checks if we need to switch to filter mode to filter
  def state_filter_start?( line )
    line =~ /^(receiving|sending) incremental file list/i
  end


  # end filter mode is an empty line 
  def state_filter_end?( line )
    line.strip == ''
  end


  # flushes the active filter
  def flush_active_filter
    if active_filter
      out.emit active_filter.join('/'), active_totals
      self.active_filter = nil
      self.active_totals = {} 
    end
  end


  # flushes the buffers (and grouping filters)
  def flush
    flush_active_filter
    out.flush
  end


  # process the line
  def <<(line)
    if state_filtering
      if state_filter_end?( line )        
        self.state_filtering = false 
        flush
        out.out << "\n" # add blank line
      else 
        filter_line(line)
      end
    else
      self.state_filtering = true if state_filter_start?( line )
      out.out << line 
    end
  end

end


#===============================================================
# Main reading loop
#===============================================================

# create the filter
if group_mode
  output = GroupOutput.new( $stdout, sort_results )
else
  output = StreamOutput.new( $stdout )
end
filter = LineFilter.new( filters, output )


# Keep reading lines of input as long as they're coming.
while input = ARGF.gets
  input.each_line do |line|

    begin
      # when there's an output file emit every line
      full_outputfile << line if full_outputfile

      # else pass the line to the filter
      filter << line 

      #$stdout.puts output_line
    rescue Errno::EPIPE
      exit(74)
    end
  end
end

# flush the filter
filter.flush