#!/usr/bin/env ruby
# 
#  preproc01.rb
#  
#  This script preprocessing rest and task-based fMRI data
#
#  Created by Zarrar Shehzad on 2012-09-24.
# 

# require 'pry'
# binding.pry

require 'pathname'
SCRIPTDIR   = Pathname.new(__FILE__).realpath.dirname.dirname
SCRIPTNAME  = Pathname.new(__FILE__).basename.sub_ext("")

# add lib directory to ruby path
$: << SCRIPTDIR + "lib" # will be scriptdir/lib

require 'config.rb'       # globalish variables
require 'for_commands.rb' # provides various function such as 'run'
require 'colorize'        # allows adding color to output
require 'erb'             # for interpreting erb to create report pages
require 'reg_help.rb'     # provides 'create_reg_pics' function
require 'trollop'         # command-line option parser

# Process command-line inputs
p = Trollop::Parser.new do
  banner "Usage: #{File.basename($0)} (-e 2) -n scan -r 1 .. N -s sub1 ... subN\n"
  opt :name, "Name of scan (movie or rest)", :type => :string, :required => true
  opt :runs, "Which runs to process", :type => :ints, :required => true
  opt :subjects, "Which subjects to process", :type => :strings, :required => true
  opt :fwhm, "FWHM for spatial smoothing", :type => :int, :default => 6
  opt :resolution, "Resolution in mm to use for standard brain", 
    :type => :int, :default => 3
end
opts = Trollop::with_standard_exception_handling p do
  raise Trollop::HelpNeeded if ARGV.empty? # show help screen
  p.parse ARGV
end

# Gather inputs
scan        = opts[:name]
runs        = opts[:runs]
subjects    = opts[:subjects]
fwhm        = opts[:fwhm]
resolution  = opts[:resolution]

standard    = "#{ENV['FSLDIR']}/data/standard/MNI152_T1_#{resolution}mm_brain.nii.gz"

subjects.each do |subject|
  puts "\n= Subject #{subject}".white.on_blue
    
  puts "\n== Setting input variables".magenta
  subdir        = "#{@preprocdir}/#{subject}"
  funcdir       = "#{subdir}/#{scan}"
  regdir        = "#{funcdir}/reg"
  func2highres  = "#{regdir}/func2highres"
  warp          = "#{regdir}/highres2standard_warp.nii.gz"
  
  puts "\n== Checking inputs".magenta
  next if any_inputs_dont_exist_including "#{func2highres}.mat", warp, standard 
  
  runs.each do |run|
    
    puts "\n== Run #{run}".white.on_blue
    
    puts "\n=== Setting input variables".magenta
    rundir          = "#{funcdir}/run_%02d" % run
    func_denoise    = "#{rundir}/func_dnoise.nii.gz"
    func_filtered   = "#{rundir}/func_denoise+filt.nii.gz"
    
    puts "\nChecking inputs".magenta
    next if any_inputs_dont_exist_including func_denoise, func_filtered
    
    puts "\n=== Setting output variables".magenta
    func_denoise2stsd           = "#{rundir}/func_denoise2standard.nii.gz"
    func_smoothed2std           = "#{rundir}/func_denoise+smooth2standard.nii.gz"
    
    puts "\n=== Checking outputs".magenta
    next if all_outputs_exist_including func_denoise2std, func_smoothed2std, 
                                        func_filtered2std, func_filtered_smoothed2std
    
    puts "\n=== Creating output directories (if necessary)".magenta
    Dir.mkdir nvrdir if not File.directory? nvrdir
    
    puts "\n=== Transforming EPIs => Standard".magenta
    run "applywarp --in=#{func_denoise} \
          --ref=#{standard} \
          --premat=#{func2highres}.mat \
          --warp=#{warp} \
          --out=#{func_denoise2std}"
    run "3dmerge -1blur_fwhm #{fwhm} -doall \
          -prefix #{func_smoothed2std} #{func_denoise2std}"
    
  end
end



