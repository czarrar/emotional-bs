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

require 'colorize'        # allows adding color to output
require 'for_commands.rb' # provides various function such as 'run'
require 'erb'             # for interpreting erb to create report pages
require 'reg_help.rb'     # provides 'create_reg_pics' function

# Usage
if ARGV.length == 0
  puts "usage: #{$0} subject1 subject2 ... subjectN".light_blue
  exit 1
end

# Gather scans by subjects and runs to process
subjects  = ARGV

# Set Paths
## general
ENV['BASEDIR']  ||= "/home/data/Projects/emotional-bs"
basedir           = ENV['BASEDIR']
qadir             = "#{basedir}/00_QA"
preprocdir        = "#{basedir}/02_PreProcessed"
## html output    
layout_file       = SCRIPTDIR + "etc/layout.html.erb"
body_file         = SCRIPTDIR + "etc/01_preprocessing/#{SCRIPTNAME}.md.erb"
report_file       = "#{qadir}/02_PreProcessed_#{SCRIPTNAME}.html"
@body             = ""

exit 2 if any_inputs_dont_exist_including qadir, preprocdir

# Loop through each subject
subjects.each do |subject|
  puts "\n= Subject: #{subject} \n".white.on_blue
  
  anatdir       = "#{preprocdir}/#{subject}/anat"
  
  puts "\n== Setting input variables".magenta
  standard      = ENV['FSLDIR'] + "/data/standard/MNI152_T1_2mm_brain.nii.gz"
  brain         = "#{anatdir}/brain.nii.gz"
  gm            = "#{anatdir}/segment/fast_pve_1.nii.gz"
    
  puts "\n== Setting output variables".magenta
  regdir        = "#{anatdir}/reg"
  regprefix     = "#{regdir}/highres2standard"
  gm2std        = "#{regdir}/gm2standard.nii.gz"
  gm2std_smooth = "#{gm2std.rmext}_smooth.nii.gz"
  
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
