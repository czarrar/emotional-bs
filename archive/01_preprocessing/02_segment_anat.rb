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

# html output    
layout_file       = SCRIPTDIR + "etc/layout.html.erb"
body_file         = SCRIPTDIR + "etc/01_preprocessing/#{SCRIPTNAME}.html.erb"
report_file       = "#{@qadir}/01_PreProcessed_#{SCRIPTNAME}.html"
@body             = ""

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
  
  puts "\n== TEMP".magenta
  run "slicer.py -w 5 -l 4 -s axial --overlay #{wm_edge} 1 1 #{brain} #{wm_edge.rmext}_pic.png"
  
  puts "\n== Saving contents for report page".magenta
  text      = File.open(body_file).read
  erbified  = ERB.new(text).result(binding)
  @body    += "\n #{erbified} \n"
  
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
    
    puts "\n== Taking pretty pictures".magenta
    run "slicer.py -w 5 -l 4 -s axial --overlay #{csf_mask} 1 1 #{brain} #{csf_mask.rmext}_pic.png"
    run "slicer.py -w 5 -l 4 -s axial --overlay #{wm_mask} 1 1 #{brain} #{wm_mask.rmext}_pic.png"
    run "slicer.py -w 5 -l 4 -s axial --overlay #{wm_edge} 1 1 #{brain} #{wm_edge.rmext}_pic.png"
    
  ensure
    
    puts "\n== doing good".magenta
    #puts "\n== Removing intermediate files".magenta
    #run "rm -f #{fast}*"
    
  end
  
end

@title          = "Anatomical Segmentation"
@nav_title      = @title
@dropdown_title = "Subjects"
@dropdown_elems = subjects
@foundation     = SCRIPTDIR + "lib/foundation"

puts "\n= Compiling and writing report page to %s".magenta % report_file
text      = File.open(layout_file).read
erbified  = ERB.new(text).result(binding)
File.open(report_file, 'w') { |file| file.write(erbified) }



