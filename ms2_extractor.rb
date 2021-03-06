#!/usr/bin/env ruby 

#require 'ruby-prof'
#RubyProf.start


require 'optparse'
require 'mspire/mzml'
# Debugging tool
  require 'pry'

options = {}
parser = OptionParser.new do |opts|
  opts.banner = "#{__FILE__} file.mzML"
  opts.separator "Returns: file.tsv"
  opts.separator "Currently tuned for TOF/TOF ms2 data.  Customize input parameters for your dataset"
  opts.on_tail('-h', "--help", "Display this help and exit") do 
    puts opts
    exit
  end

  opts.on("-v", "--verbose", "turn on verbosity") do |v|
    options[:verbose] = v
  end
  opts.on('-i N', '--intensity N', Float, "Minimum intensity value acceptable for evidence peaks") do |i|
    options[:minimum_intensity] = i
  end
  opts.on('-p N', "--ppm N", Float, "Run search at ms2 ppm value of N") do |p|
    options[:ppm_tolerance] = p
  end
  opts.on('-d', '--debug_mode', "Add debugging output to the output files") do |d|
    options[:debugging_output] = d
  end
end

parser.parse!
if ARGV.size == 0
  puts "Input file required"
  puts parser
  exit
end
$PROTON_MASS = 1.00727638



Mass_shift_pairs = 401.0762
Dead_end_doublet = [472.593, 469.5679] #"4.0251 Dalton split at ~472.52 below light precursor"
Dead_end_reporter_ions = [474.16,528.20,611.29, 478.19, 536.25, 619.34] # From their TOF/TOF data #[474.16, 478.16, 528.20, 536.25, 611.29, 619.29]
#Dead_end_reporter_ions = [474.593,478.6181,528.657, 532.6821,611.804, 618.8542] # From their TOF/TOF data #[474.16, 478.16, 528.20, 536.25, 611.29, 619.29]

Reporter_ion_tolerance = options[:ppm_tolerance] ? options[:ppm_tolerance] : 500 # ppm
EvidenceIntensityThreshold = options[:minimum_intensity] ? options[:minimum_intensity] : 800


## Fxns I might want to use... 
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

CrosslinkingEvidence = Struct.new(:type, :ppm_error, :scan_number, :retention_time, :base_mz, :base_int, :match_mz, :match_int, :precursor_mass)

extradata_file = nil
data_file = nil

ARGV.each do |file|
  Mspire::Mzml.open(file) do |mzml|
    matches = []
    mzml.each do |spectrum|
      next unless spectrum.ms_level == 2
      evidences = []
      #Doublet reporters of dead_ends
      Dead_end_doublet.map do |ion| 
        check_mass = spectrum.precursor_mz-ion
        id = spectrum.find_nearest_index(check_mass)
        match = spectrum[id].first
        error = calculate_ppm_error(check_mass, match)
        evidences << CrosslinkingEvidence.new(:dead_end_loss, error, spectrum.id[/scan=(\d*)/,1], spectrum.retention_time, nil, nil, match, spectrum[id].last, spectrum.precursors.first.selected_ions.first.fetch_by_acc("MS:1000744")) if error.abs < Reporter_ion_tolerance and spectrum[id].last > EvidenceIntensityThreshold
      end
      Dead_end_reporter_ions.map do |ion|
        id = spectrum.find_nearest_index(ion)
        match = spectrum[id].first
        error = calculate_ppm_error(ion, match)
        evidences << CrosslinkingEvidence.new(:dead_end_reporter, error, spectrum.id[/scan=(\d*)/,1], spectrum.retention_time, nil, nil, match, spectrum[id].last, spectrum.precursors.first.selected_ions.first.fetch_by_acc("MS:1000744")) if error.abs < Reporter_ion_tolerance and spectrum[id].last > EvidenceIntensityThreshold
      end
      spectrum.peaks do |mz,int|
        next if int < EvidenceIntensityThreshold
        match = spectrum.find_nearest_index(mz+Mass_shift_pairs) 
        error = calculate_ppm_error(mz+Mass_shift_pairs, spectrum[match].first)
        if error.abs < Reporter_ion_tolerance and spectrum[match].last > EvidenceIntensityThreshold
          evidences << CrosslinkingEvidence.new(:crosslink_match, error, spectrum.id[/scan=(\d*)/,1], spectrum.retention_time, mz, int, spectrum[match].first, spectrum[match].last, spectrum.precursors.first.selected_ions.first.fetch_by_acc("MS:1000744"))
        end
      end
      matches << evidences unless evidences.empty?
    end # mzml.each
    require 'yaml'
    extradata_file = File.absolute_path(file)[/(.*)\.mzML/,1]+'_ms2_extradata.yml'
    data_file = File.absolute_path(file)[/(.*)\.mzML/,1]+'_ms2_crosslinks.yml' 
    File.open(extradata_file, 'w') do |out|
      YAML.dump(matches, out)
    end
    File.open(data_file, 'w') do |out|
      YAML.dump(matches.select{|a| a.size > 1 }, out)
    end
  end # open(file)
  puts "Extra Data File: #{extradata_file}"
  puts "Data File: #{data_file}"
end # ARGV.each

#result = RubyProf.stop
## Print a flat profile to text
#printer = RubyProf::FlatPrinter.new(result)
#printer.print(STDOUT)
