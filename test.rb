require 'optparse'

options = {}
parser = OptionParser.new do |opts|
  opts.on('-h') do |h|
    options[:help] = h
  end
end
p parser.parse(ARGV)
p options
