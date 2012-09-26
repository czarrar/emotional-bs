#!/usr/bin/env ruby
# 
#  preproc02.rb
#  
#  This script preprocessing rest and task-based fMRI data
#
#  Created by Zarrar Shehzad on 2012-09-24.
# 

# add lib directory to ruby path
$: << File.join(File.dirname(__FILE__), "/../lib")

require 'colorize'        # allows adding color to output
require 'for_commands.rb' # provides 'run' function


# Usage
if ARGV.length == 0
  puts "usage: #{$0} subject1 subject2 ... subjectN".light_blue
  exit 1
end

# Gather scans by subjects and set other variables
subjects    = ARGV
csf_thresh  = 0.5
wm_thresh   = 0.5


# Set Paths
# => note: prefix of 't_' is for string variables that have element(s) requiring 
# =>       subtitution/interpolation.
## general
basedir     = "/home/data/Projects/emotional-bs"
preprocdir  = "#{basedir}/02_PreProcessed"
t_subdir    = "#{preprocdir}/%{subject}"
t_anatdir   = "#{t_subdir}/anat"
## inputs
t_in_brain  = "#{t_anatdir}/brain.nii.gz"
## outputs
t_csf_mask  = "#{t_anatdir}/csf_mask.nii.gz"
t_wm_mask   = "#{t_anatdir}/wm_mask.nii.gz"
t_wm_edge   = "#{t_anatdir}/wm_mask_edge.nii.gz"


# Loop through each subject
subjects.each do |subject|
  puts "= Subject: #{subject} \n".white.on_blue
  
  svars = {:subject => subject}
  in_brain  = t_in_brain % svars
  fast      = "#{t_anatdir}/segment/fast" % svars
  csf_mask  = t_csf_mask % svars
  wm_mask   = t_wm_mask % svars
  wm_edge   = t_wm_edge % svars
  
  begin
  
    puts "== Segmenting skullstripped anatomical".magenta
    run "fast --channels=1 --type=1 --class=3 --out=#{fast} #{in_brain}"
    
    puts "== Thresholding CSF mask".magenta
    run "3dcalc -a #{fast}_pve_0.nii.gz -expr 'step(a-%.4f)' \
          -prefix #{csf_mask} -datum short" % csf_thresh
    
    puts "== Thresholding WM mask".magenta
    run "3dcalc -a #{fast}_pve_2.nii.gz -expr 'step(a-%.4f)' \
          -prefix #{wm_mask} -datum short" % wm_thresh
    
    puts "== Find edges of WM for evaluating segmentation and bbreg results"
    run "fslmaths #{wm_mask} -edge -bin -mas #{wm_mask} #{wm_edge}"
    
  ensure
    
    puts "\n== Removing intermediate files"
    run "rm -f %s*" % [fast]
    
  end
  
end



