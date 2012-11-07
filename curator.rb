#!/usr/bin/env ruby 
#Reads the output from simple_extractor and ms2_extractor
Profile = false
if Profile
  require 'ruby-prof'
  RubyProf.start
end

#TODO ms3 extractor
class Range
  def +(number)
    begin 
    (self.min + number)..(self.max + number)
    rescue 
      binding.pry
      abort

    end
  end
end

require 'optparse'
options = {}
parser = OptionParser.new do |opts|
  opts.on('-v', '--verbose', "Turn up the verbosity") do |v|
    options[:verbose] = v
  end

  opts.banner = "Usage: ruby #{__FILE__} simple_extractor_output_file.yml ms2_extractor_output_file.yml"

  opts.on('-m','--ms3','Output ms3 spectra') do |m|
    options[:ms3_output] = m
  end
  opts.on('-p', '--ppm N', Integer, "PPM tolerance for precursor ion matching") do |p|
    options[:parent_tolerance] = p
  end
  opts.on('-s', '--scan N', Integer, "Scan +/- tolerance for scan number alignment between the ms1 and ms2 evidence") do |s|
    options[:scan_tolerance] = (-s..s)
  end
end

parser.parse!
if ARGV.size > 0
  simple_file = ARGV.shift
  ms2_file = ARGV.shift
else
  puts "FAILURE, no files given"
  puts parser
  exit
end

CrosslinkingEvidence = Struct.new(:type, :ppm_error, :scan_number, :retention_time, :base_mz, :base_int, :match_mz, :match_int, :precursor_mass)
TagEvidence = Struct.new(:base_peak, :heavy_peak, :mass_error, :charge_state, :intensity_error_percentage, :retention_time, :base_scan_number, :heavy_scan_number )
require 'yaml'
# Debugging tool
    require 'pry'
simples = YAML::load_file(simple_file)
ms2s = YAML::load_file(ms2_file)

ScanRange = options[:scan_tolerance] ? options[:scan_tolerance] : (-20..20)
# implement an alternative search by time difference between scans
Tolerance = options[:parent_tolerance] ? options[:parent_tolerance] : 500

def check_ms2s(mass_arr, ms2s, scan)
  response = []
  ms2s.each do |ms2|
    mass = ms2.first.precursor_mass
    loop_scan = ms2.first.scan_number.to_i
    mz_check = check_mass_by_tolerance(mass, mass_arr)
   # puts ["scan:", scan, loop_scan] if mz_check
    scan_check = check_scan_range(loop_scan, ScanRange+scan)
    #binding.pry
    response << ms2 if mz_check and scan_check
  end
  response
end

def check_scan_range(scan, range)
  range.include? scan
end

def calculate_mass_range_by_ppm(mass, ppm = Tolerance)
  tol = ppm/1.0e6*mass
  (mass-tol..mass+tol)
end

def check_mass_by_tolerance(mass, mass_arr)
  mass_arr.map do |mz|
    check_range = calculate_mass_range_by_ppm(mz)
    ans = check_range.include?(mass)
  end.uniq.first
end

# Curate!!
curated_hits = []

resp = []
simples.each do |tagevidence|
  precursor_masses = [tagevidence.base_peak.first, tagevidence.heavy_peak.first]
  scan = tagevidence.scan_number.to_i
  reply = check_ms2s(precursor_masses, ms2s, scan)
  resp << [tagevidence, reply, "#{'='*50}"] unless reply.empty?
end

p resp
if options[:ms3_output]
  File.open("ms3_curation_output_#{Time.now.to_i}.txt", 'w') do |out|
    out.puts resp.join("\n")
  end
end

outfile = File.absolute_path(simple_file).sub("_ms1s.yml","_curated_hits.txt")
File.open(outfile, 'w') do |out|
  out.puts resp.join("\n")
end
puts "OUTFILE: #{outfile}" 

if Profile
  result = RubyProf.stop

  # Print a flat profile to text
  printer = RubyProf::FlatPrinter.new(result)
  printer.print(STDOUT)
end
  

