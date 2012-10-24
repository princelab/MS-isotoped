#!/usr/bin/env ruby 

require 'mspire/mzml'
require 'optparse'
# Debugging tool: 
  require 'pry'
TagEvidence = Struct.new(:base_peak, :heavy_peak, :mass_error, :charge_state, :intensity_error_percentage, :retention_time, :scan_number) 
=begin
example = { 
  base_peak: [mz,int], 
  heavy_peak: spectrum.peaks[index], 
  mass_error: calculate_ppm_error(mz+charge_stater_for_mass_tag(Mass_difference, z),spectrum.mzs[index]),
  charge_state: z, 
  intensity_error_percentage: calculate_percent_error(int, spectrum.intensities[index])
  }
=end
options = {}
# To do
  options[:output_results] = nil#= outfile
# Parser
parser = OptionParser.new do |opts|
  opts.banner = "#{__FILE__} [options] file.mzML"
  opts.separator "Returns: file_{ms1_hits.tsv,ms2_hits.tsv,matches.tsv,ms3_search.tsv}"
  opts.on_tail('-h', "--help", "Display this help and exit") do 
    puts opts
    exit
  end

  opts.on("-v", "--verbose", "turn on verbosity") do |v|
    options[:verbose] = v
  end

  opts.on('-z', "--z_state", "Check by Z state that we are actually looking at the right charge state for the matched isotopic pattern") do |z|
    options[:z_check] = z
  end
  opts.on("--intensity_range x,y", Array, "Modify the default Intensity tolerance range, e.g. (DEFAULTS) 0.8,1.2") do |i|
    i.map!(&:to_f)
    if i.size == 2 and (i.first < 1 or i.last > 1)
      options[:intensity_tolerance_range] = i.first..i.last
    else
      puts "Invalid range values given\nExiting..."
      puts opts
      exit
    end
  end
  opts.on("--ppm N", Float, "Run search at ppm value of N") do |p|
    options[:ppm_tolerance] = p
  end
  opts.on('-d', '--debug_mode', "Add debugging output to the output files") do |d|
    options[:debugging_output] = d
  end
  opts.on('--kalman', 'Output some data for generating XIC plots and matching to Kalman filters') do |k|
    options[:kalman] = k
  end
end

parser.parse
if ARGV.size == 0
  puts "Input file required"
  puts parser
  exit
end

file = parser.parse(ARGV).first

p %x[ruby simple_extractor.rb #{ARGV}]
