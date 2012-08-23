
options = {}
parser = OptionParser.new do |opts|
  opts.banner = "#{__FILE__} file.mzML"
  opts.separator "Returns: file.tsv"
  opts.on_tail('-h', "--help", "Display this help and exit") do 
    puts opts
    exit
  end
  opts.on('-o STRING', "--output STRING", "Give me a file name for a tsv file output of the information, with an attempt to correlate the information by charge states and hopefully by chromatography (coming soon)") do |outfile|
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
end

parser.parse!
if ARGV.size == 0
  puts "Input file required"
  puts "********ALERT************\nThe options given here are wrong..."
  puts parser
  exit
end
$PROTON_MASS = 1.00727638

Mass_shift_pairs = 401.22..401.19
Dead_end_doublet = "4.0251 Dalton split at ~472.52 below light precursor"
Dead_end_reporter_ions = [474.16, 478.16, 528.20, 536.25, 611.29, 619.29]
