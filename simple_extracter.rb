#!/usr/bin/env ruby 

require 'mspire/mzml'
require 'optparse'
# Debugging tool: 
  require 'pry'

options = {}
parser = OptionParser.new do |opts|
  opts.banner = "#{__FILE__} file.mzML"
  opts.separator "Returns: file.tsv"
  opts.on_tail('-h', "--help", "Display this help and exit") do 
    puts opts
    exit
  end

  opts.on("-v", "--verbose", "turn on verbosity") do |v|
    options[:verbose] = v
  end

end

parser.parse!
if ARGV.size == 0
  puts "Input file required"
  puts parser
  exit
end

Tolerance = 10 #(ppm)
Intensity_threshold_MS1 = 1500
Mass_difference = 8.0507
Max_charge_state = 3.0
MS2_intensity_tolerance_range = (0.9..1.1)
# Range metaprogramming
class Range 
  def *(float)
    Range.new(self.min*float, self.max*float)
  end
end

# Methods 
def calculate_mass_range_by_ppm(mass, ppm = Tolerance)
  tol = ppm/1.0e6*mass
  (mass-tol..mass+tol)
end
def calculate_ppm_error(mass1, mass2)
  (mass2-mass1)/mass1.to_f*1.0e6
end
def charge_stater_for_mass_tag(mass, charge_state=2)
  mass/charge_state
end
def detect_charge_state(initial_mass, spectrum)
  #TODO
end
def scan_for_isotopes(spectrum)
  #@[return] array of matches
  matches = []
  check_arr = [spectrum.mzs]
  spectrum.peaks do |mz,int|
    next if int < Intensity_threshold_MS1
    potential_matches = []
    (1..Max_charge_state).to_a.each do |z|
      index = spectrum.find_nearest_index(mz+charge_stater_for_mass_tag(Mass_difference, z)) 
      intensity_range = MS2_intensity_tolerance_range*int
      matches << {peaks: spectrum.peaks[index], mass_error: calculate_ppm_error(mz+charge_stater_for_mass_tag(Mass_difference, z),spectrum.mzs[index]), charge_state: z} if calculate_mass_range_by_ppm(mz+charge_stater_for_mass_tag(Mass_difference, z)).include?(spectrum.mzs[index]) and intensity_range.include?(spectrum.intensities[index])
    end 
  end
  matches.uniq.map{|a| a.to_s}
end

# Analysis
ARGV.each do |file|
  Mspire::Mzml.open(file) do |mzml|
    matches = []
    results = []
    mzml.each do |spectrum|
      next if spectrum.ms_level > 1
      resp = scan_for_isotopes(spectrum)
      if resp.size >= 1
        matches << ["id: #{spectrum.id}\tRT: #{spectrum.retention_time}", resp] 
# TODO: Check matches for consistency between runs
        results << [spectrum, resp] if options[:output_results]
      end
    end
    puts matches.join("\n")
  end
end


