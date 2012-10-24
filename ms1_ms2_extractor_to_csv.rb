#!/usr/bin/env ruby 

require 'mspire/mzml'

if ARGV.size == 0
  puts "usage: feed me an mzML file and I'll spit back the ms1 and ms2 in csv\n\twith mz,intensity,retention_time for each scan, unseparated by headers"
  exit
end

MinimumIonIntensity = 5


def write_to_csv(io_obj, spectrum)
  rt = spectrum.retention_time
  spectrum.peaks do |mz, int|
    io_obj.puts [mz,int,rt].join(',') if int > MinimumIonIntensity
  end
end

ARGV.each do |file|
  outfile_base = File.absolute_path(file).sub('.mzML','')
  Mspire::Mzml.open(ARGV.first) do |mzml|
    # Open output files for ms1 and ms2 files
    File.open(outfile_base + '_ms1.csv', 'w') do |ms1_out|
      File.open(outfile_base + '_ms2.csv', 'w') do |ms2_out|
        # Proceed through each scan
        mzml.each do |spectrum|
          if spectrum.ms_level == 1
            write_to_csv(ms1_out, spectrum)
          elsif spectrum.ms_level == 2 
            write_to_csv(ms2_out, spectrum)
          end
        end #mzml.each
      end # ms2_out
    end # ms1_out
  end # Mspire::Mzml
end # ARGV.each
