#!/usr/bin/env ruby 
#Reads the output from simple_extractor and ms2_extractor

#calls ms3 extractor?
class Range
  def +(number)
    (self.min + number)..(self.max + number)
  end
end

require 'optparse'
options = {}
parser = OptionParser.new do |opts|
  opts.on('-v', '--verbose', "Turn up the verbosity") do |v|
    options[:verbose] = v
  end

  opts.banner = "Usage: ruby #{__FILE__} simple_extractor_output_file.tsv ms2_extractor_output_file.tsv"

  opts.on('-m','--ms3','Output ms3 spectra') do |m|
    options[:ms3_output] = m
  end
end

parser.parse!

simple_file = ARGV.shift
ms2_file = ARGV.shift

CrosslinkingEvidence = Struct.new(:type, :ppm_error, :scan_number, :retention_time, :base_mz, :base_int, :match_mz, :match_int, :precursor_mass)
TagEvidence = Struct.new(:base_peak, :heavy_peak, :mass_error, :charge_state, :intensity_error_percentage, :retention_time, :scan_number)

require 'yaml'
# Debugging tool
    require 'pry'
simples = YAML::load_file(simple_file)
ms2s = YAML::load_file(ms2_file)

ScanRange = -20..20
ToleranceRange = -0.5..0.5

def check_ms2s(mass_arr, ms2s)
  response = []
  ms2s.each do |ms2|
    mass = ms2.first.precursor_mass
    scan = ms2.first.scan_number
    mz_check = check_mass_by_tolerance(mass, mass_arr)
    scan_check = check_scan_range(scan)
    response << ms2 if mz_check and scan_check
  end
  response
end

def check_scan_range(scan, range = ScanRange)
  range.include? scan
end

def check_mass_by_tolerance(mass, mass_arr, tol_range = ToleranceRange)
  mass_arr.map do |mz|
    check_range = tol_range+mz
    ans = check_range.include?(mass)
  end.uniq.first
end

# Curate!!
curated_hits = []

resp = []
simples.each do |tagevidence|
  masses = [tagevidence.base_peak.first, tagevidence.heavy_peak.first]
  reply = check_ms2s(masses, ms2s)
  resp << [tagevidence, reply] unless reply.empty?
end

p resp
