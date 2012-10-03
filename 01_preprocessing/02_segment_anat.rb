#!/usr/bin/env ruby
# 
#  preproc02.rb
#  
#  This script preprocessing rest and task-based fMRI data
#
#  Created by Zarrar Shehzad on 2012-09-24.
# 

require 'pathname'
SCRIPTDIR   = Pathname.new(__FILE__).realpath.dirname.dirname
SCRIPTNAME  = Pathname.new(__FILE__).basename.sub_ext("")

# add lib directory to ruby path
$: << SCRIPTDIR + "lib" # will be scriptdir/lib

require 'config.rb'       # globalish variables
require 'for_commands.rb' # provides various function such as 'run'
require 'colorize'        # allows adding color to output
require 'erb'             # for interpreting erb to create report pages
require 'trollop'

# Process command-line inputs
p = Trollop::Parser.new do
  banner "Usage: #{File.basename($0)} -s sub1 ... subN\n"
  opt :subjects, "Which subjects to process", :type => :strings, :required => true
end
opts = Trollop::with_standard_exception_handling p do
  raise Trollop::HelpNeeded if ARGV.empty? # show help screen
  p.parse ARGV
end

# Gather inputs
subjects    = opts[:subjects]
csf_thresh  = 0.95
wm_thresh   = 0.95

# Loop through each subject
subjects.each do |subject|
  puts "\n= Subject: #{subject} \n".white.on_blue
  
  anatdir   = "#{@preprocdir}/#{subject}/anat"
  
  puts "\n== Setting input variables".magenta
  brain     = "#{anatdir}/brain.nii.gz"
  
  puts "\n== Checking inputs".magenta
  next if any_inputs_dont_exist_including brain
  
  puts "\n== Setting output variables".magenta
  segdir    = "#{anatdir}/segment"
  fast      = "#{segdir}/fast"
  csf_mask  = "#{anatdir}/csf_mask.nii.gz"
  wm_mask   = "#{anatdir}/wm_mask.nii.gz"
  wm_edge   = "#{anatdir}/wm_mask_edge.nii.gz"
    
  puts "\n== Checking outputs".magenta
  next if all_outputs_exist_including csf_mask, wm_mask, wm_edge
  
  puts "\n== Creating output directories (if needed)".magenta
  Dir.mkdir segdir if not File.directory? segdir
  
  begin
  
    puts "\n== Segmenting skullstripped anatomical".magenta
    run "fast -g -p -o #{fast} #{brain}"
    
    puts "\n== Thresholding CSF mask".magenta
    run "3dcalc -a #{fast}_prob_0.nii.gz -expr 'step(a-%.4f)' \
          -prefix #{csf_mask} -datum short" % csf_thresh
    
    puts "\n== Thresholding WM mask".magenta
    run "3dcalc -a #{fast}_prob_2.nii.gz -expr 'step(a-%.4f)' \
          -prefix #{wm_mask} -datum short" % wm_thresh
    
    puts "\n== Find edges of WM for evaluating segmentation and bbreg results".magenta
    run "fslmaths #{wm_mask} -edge -bin -mas #{wm_mask} #{wm_edge}"
    
  ensure
    
    puts "\n== doing good".magenta
    #puts "\n== Removing intermediate files".magenta
    #run "rm -f #{fast}*"
    
  end
  
end



