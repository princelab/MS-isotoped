#!/usr/bin/env ruby 
#require 'ruby-prof'
#RubyProf.start
require 'mspire/mzml'
require 'optparse'
# Debugging tool: 
  require 'pry'
TagEvidence = Struct.new(:base_peak, :heavy_peak, :mass_error, :charge_state, :intensity_error_percentage, :retention_time, :scan_number)
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
  opts.separator "Returns: file.tsv"
  opts.on_tail('-h', "--help", "Display this help and exit") do 
    puts opts
    exit
  end
  opts.on('-o STRING', "--output STRING", "Give me a file name for a yml file output of the information, with an attempt to correlate the information by charge states and hopefully by chromatography (coming soon)") do |outfile|
    options[:output_results] = outfile
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
Max_charge_state = 3.0
Isotope_mass_tolerance = Tolerance # * 2 ##Perhaps a different value would be better, as the error increases as you drop in intensity 
MS2_intensity_tolerance_range = options[:intensity_tolerance_range] ? options[:intensity_tolerance_range] : (0.8..1.2)
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
      matches << TagEvidence.new([mz,int], spectrum.peaks[index], calculate_ppm_error(mz+charge_stater_for_mass_tag(Mass_difference, z),spectrum.mzs[index]), z, calculate_percent_error(int, spectrum.intensities[index]), spectrum.retention_time, spectrum.id[/scan=(\d*)/,1]) if calculate_mass_range_by_ppm(mz+charge_stater_for_mass_tag(Mass_difference, z)).include?(spectrum.mzs[index]) and intensity_range.include?(spectrum.intensities[index])
    end 
  end
  matches.uniq
end

# Analysis
ARGV.each do |file|
  file2 = nil
  matches = []
  results = []
  Mspire::Mzml.open(file) do |mzml|
    mzml.each do |spectrum|
      next if spectrum.ms_level > 1
      resp = scan_for_isotopes(spectrum)
      if resp.size >= 1
        matches << [resp.to_s] 
# TODO: Check matches for consistency between runs
        results << [spectrum, resp] if options[:output_results]
      end
    end
  end # Mspire File read
  #puts matches.join("\n")
  if options[:output_results]
    File.open(options[:output_results], 'w') do |out|
      require 'yaml'
      file2 = options[:output_results].sub('.yml', '_ms1s.yml')
      File.open(file2, 'w') do |out_yaml|
        yaml_output = []
        # Output the data, after analyzing it for isotopic distribution matches by Z state and chromatographic correlations from scan to scan
        # Z state checking 
        results.each do |arr|
          spectrum = arr.first
          arr.last.each do |resp|
            charges = confirm_charge_state(resp[:base_peak].first, resp[:charge_state], spectrum)
            if charges.include?(resp[:charge_state])
              out.puts "==== #{spectrum.id[/scan=\d*/]}\t@#{spectrum.retention_time} seconds\t===="
              out.puts resp
              out.puts "charge_state confirmed:\t#{charges}"
            else
              out.puts "***#{resp.to_s}\t Doesn't match on charge" if options[:debugging_output]
            end
          end
          arr.last.each {|a| yaml_output << a}
        end # Results.each
        YAML.dump(yaml_output, out_yaml)
      end # yml File output
    end # File writing
  end # options[:output_results]
  if options[:kalman]
    File.open(File.basename(file)[/(.*)\.mzML/,1]+'_kalman.txt', 'w') do |out|
      # Decide how to output the data
    end # File.open ***_kalman.txt
  end #options[:kalman]
  puts "File1: #{options[:output_results]}"
  puts "File2: #{file2}"
end
#result = RubyProf.stop

# Print a flat profile to text
#printer = RubyProf::FlatPrinter.new(result)
#printer.print(STDOUT)


