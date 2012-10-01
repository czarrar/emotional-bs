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
require 'trollop'

# Process command-line inputs
p = Trollop::Parser.new do
  banner "Usage: #{File.basename($0)} (-r 2) -s sub1 ... subN\n"
  opt :resolution, "Resolution in mm to use for standard brain", 
    :type => :int, :default => 2
  opt :subjects, "Which subjects to process", 
    :type => :strings, :required => true
end
opts = Trollop::with_standard_exception_handling p do
  raise Trollop::HelpNeeded if ARGV.empty? # show help screen
  p.parse ARGV
end

# Gather inputs
resolution  = opts[:resolution]
subjects    = opts[:subjects]

standard    = "#{ENV['FSLDIR']}/data/standard/MNI152_T1_#{resolution}mm_brain.nii.gz"

# Loop through each subject
subjects.each do |subject|
  puts "\n= Subject: #{subject} \n".white.on_blue
  
  anatdir       = "#{preprocdir}/#{subject}/anat"
  
  puts "\n== Setting input variables".magenta
  brain         = "#{anatdir}/brain.nii.gz"
  gm            = "#{anatdir}/segment/fast_pve_1.nii.gz"
  
  puts "\n== Checking inputs".magenta
  next if any_inputs_dont_exist_including standard, brain
  
  puts "\n== Setting output variables".magenta
  regdir        = "#{anatdir}/reg"
  regprefix     = "#{regdir}/highres2standard"
  gm2std        = "#{regdir}/gm2standard.nii.gz"
  gm2std_smooth = "#{gm2std.rmext}_smooth.nii.gz"
  
  puts "\n== Checking outputs".magenta
  next if all_outputs_exist_including regprefix, gm2std, gm2std_smooth
  
  puts "\n== Creating output directories (if needed)"
  Dir.mkdir regdir if not File.directory? regdir
  
  begin
        
    puts "\n== Linear registration T1 => Standard".magenta
    run "flirt \
          -in #{brain} \
          -ref #{standard} \
          -omat #{regprefix}.mat \
          -o #{regprefix}.nii.gz"        
    
    puts "\n=== Creating pretty pictures".magenta
    create_reg_pics "#{regprefix}.nii.gz", standard, "#{regprefix}_flirt.png"
    
    puts "\n== Invert transform to get Standard => T1"
    run "convert_xfm -omat #{regdir}/standard2highres.mat -inverse #{regprefix}.mat"
    
    puts "\n== Non-linear registration T1 Head => Standard".magenta
    run "fnirt \
          --in=#{head} \
          --aff=#{regprefix}.mat \
          --cout=#{regprefix}_warp.nii.gz \
          --config=T1_2_MNI152_2mm"
    
    puts "\n== Applying transform T1 Brain => Standard".magenta
    run "applywarp \
          --ref=#{standard} \
          --in=#{brain} \
          --warp=#{regprefix}_warp.nii.gz \
          --out=#{regprefix}.nii.gz"
    
    puts "\n=== Creating pretty pictures".magenta
    create_reg_pics "#{regprefix}.nii.gz", standard, "#{regprefix}_flirt.png"
    
    puts "\n== Linking standard brain".magenta
    run "ln -s #{standard} #{regdir}/standard.nii.gz"
    
    puts "\n== Applying transform GM => Standard".magenta
    run "applywarp \
          --in=#{gm} \
          --ref=#{standard} \
          --warp=#{regprefix}_warp.nii.gz \
          --out=#{gm2std}"
    
    puts "\n== Smooth GM".magenta
    run "3dmerge -1blur_fwhm 6 -doall -prefix #{gm2std_smooth} #{gm2std}"
  
  ensure
    
    puts "\n== doing good".magenta
        
  end
  
end
