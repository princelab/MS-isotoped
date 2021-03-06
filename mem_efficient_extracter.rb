#!/usr/bin/env ruby 

Profile = false
if Profile
  require 'ruby-prof'
  RubyProf.start
end

require 'mspire/mzml'
require 'optparse'
require 'yaml'
# Debugging tool: 
  require 'pry'
TagEvidence = Struct.new(:base_peak, :heavy_peak, :mass_error, :charge_state, :intensity_error_percentage, :retention_time, :base_scan_number, :heavy_scan_number )
=begin
                         { base_peak: [mz,int], 
        heavy_peak: spectrum.peaks[index], 
        mass_error: calculate_ppm_error(mz+charge_stater_for_mass_tag(Mass_difference, z),spectrum.mzs[index]),
        charge_state: z, 
        intensity_error_percentage: calculate_percent_error(int, spectrum.intensities[index])
=end
options = {}
parser = OptionParser.new do |opts|
  opts.banner = "#{__FILE__} file.mzML"
  opts.separator "Returns: file_ms1s.yml"
  opts.on_tail('-h', "--help", "Display this help and exit") do 
    puts opts
    exit
  end
#  opts.on('-o STRING', "--output STRING", "Give me a file name for a yml file output of the information, with an attempt to correlate the information by charge states and hopefully by chromatography (coming soon)") do |outfile|
#    options[:output_results] = outfile
#  end

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
  opts.on("-p N", "--ppm N", Float, "Run search at ppm value of N") do |p|
    options[:ppm_tolerance] = p
  end
  opts.on('-d', '--debug_mode', "Add debugging output to the output files") do |d|
    options[:debugging_output] = d
  end
  opts.on('--kalman', 'Output some data for generating XIC plots and matching to Kalman filters') do |k|
    options[:kalman] = k
  end
  opts.on('-s N', "--scan N", Integer, "Scan number to forward look to find isotopic matches (useful for deuterium isotopic tags which affect retention time") do |s|
    options[:scan_offset] = s
  end
end

parser.parse!
if ARGV.size == 0
  puts "Input file required"
  puts parser
  exit
end
$PROTON_MASS = 1.00727638

Tolerance = options[:ppm_tolerance] ? options[:ppm_tolerance] : 10 #(ppm)
Intensity_threshold_MS1 = 1500
Mass_difference = 8.0507
Max_charge_state = 4.0
Isotope_mass_tolerance = Tolerance # * 2 ##Perhaps a different value would be better, as the error increases as you drop in intensity 
MS2_intensity_tolerance_range = options[:intensity_tolerance_range] ? options[:intensity_tolerance_range] : (0.8..1.2)
Max_MS1_scan_offset = options[:scan_offset] ? options[:scan_offset] : 10
# Range metaprogramming
class Range 
  def *(float)
    Range.new(self.min*float, self.max*float)
  end
end

# Fix the YAML file formatting, to make a series of objects into a single one... 
def fix_YAML_file(file)
  lines=File.readlines(file)
  shift = false
  File.open(file, 'w') do |out|
    lines.each do |line|
      if shift
        next if line[/^---/]
        out.print line 
      end
      shift = true 
    end
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
def calculate_percent_error(int1, int2)
  (int2-int1)/int1.to_f * 100
end
def confirm_charge_state(initial_mass, z, spectrum)
  test_masses = 1.upto(Max_charge_state).map {|n| [n, initial_mass + n*$PROTON_MASS]}
  matches = test_masses.map do |test_arr|
    mass = spectrum.find_nearest(test_arr[1])
    calculate_ppm_error(mass, test_arr[1]) < Isotope_mass_tolerance ? test_arr.first : nil 
  end
  matches.uniq.compact
end
def scan_for_isotopes(spectrum, spectrum2)
  #@[return] array of matches
  matches = []
  check_arr = [spectrum.mzs]
  spectrum.peaks do |mz,int|
    next if int < Intensity_threshold_MS1
    potential_matches = []
    (1..Max_charge_state).to_a.each do |z|
      index = spectrum2.find_nearest_index(mz+charge_stater_for_mass_tag(Mass_difference, z)) 
      intensity_range = MS2_intensity_tolerance_range*int
      match = spectrum2.peaks[index]
      matched_mz = match.first
      matched_int = match.last
      if calculate_mass_range_by_ppm(mz+charge_stater_for_mass_tag(Mass_difference, z)).include?(matched_mz) and intensity_range.include?(matched_int)
        matches << TagEvidence.new([mz,int], match, calculate_ppm_error(mz+charge_stater_for_mass_tag(Mass_difference, z),matched_mz), z, calculate_percent_error(int, matched_int), spectrum.retention_time, spectrum.id[/scan=(\d*)/,1], spectrum2.id[/scan=(\d*)/,1]) 
      end 
    end
  end
  matches.uniq
end

# Analysis
ARGV.each do |file|
  #if options[:output_results] == 'auto'
    options[:output_results] = File.absolute_path(file).sub('.mzML', '.yml')
  #end
  file2 = nil
  matches = []
  results = []
  yaml_output = []
  File.open(options[:output_results], 'w') do |out|
    file2 = options[:output_results].sub('.yml', '_ms1s.yml')
    File.open(file2, 'w') do |out_yaml|
      Mspire::Mzml.open(file) do |mzml|
        max = mzml.size-1
        mzml.each_with_index do |spectrum, index|
          next if spectrum.ms_level > 1
          response = []
          (0..Max_MS1_scan_offset).each do |i|
            next if index+i > max
            next if mzml[index+i].ms_level > 1
            response << scan_for_isotopes(spectrum, mzml[index+i])
          end 
          response.flatten!
          if response.size >= 1
            response.each do |resp|
      # TODO: Check matches for consistency between runs
              charges = confirm_charge_state(resp[:base_peak].first, resp[:charge_state], spectrum)
              if charges.include?(resp[:charge_state])
                out.puts "==== #{spectrum.id[/scan=\d*/]}\t@#{spectrum.retention_time} seconds\t===="
                out.puts resp
                out.puts "charge_state confirmed:\t#{charges}"
              else
                out.puts "***#{resp.to_s}\t Doesn't match on charge" if options[:debugging_output]
              end
              yaml_output << resp
            end # response.each 
            #out_yaml.puts yaml_output.to_yaml
            YAML.dump(yaml_output, out_yaml)
            yaml_output.clear
          end
        end
      end # Mspire File read
    end #out_yaml File 
  #puts matches.join("\n")
  #if options[:output_results]
      # Output the data, after analyzing it for isotopic distribution matches by Z state and chromatographic correlations from scan to scan
      # Z state checking 
  end # File writing
  #end # options[:output_results]
  if options[:kalman]
    File.open(File.absolute_path(file)[/(.*)\.mzML/,1]+'_kalman.txt', 'w') do |out|
      # Decide how to output the data
    end # File.open ***_kalman.txt
  end #options[:kalman]
  [options[:output_results], file2].map {|f| fix_YAML_file f }
  puts "File1: #{options[:output_results]}"
  puts "File2: #{file2}"
end
if Profile
  result = RubyProf.stop

  # Print a flat profile to text
  printer = RubyProf::FlatPrinter.new(result)
  printer.print(STDOUT)
end


