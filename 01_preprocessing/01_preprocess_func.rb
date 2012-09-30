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
require 'trollop'

# Process command-line inputs
p = Trollop::Parser.new do
  banner "Usage: #{File.basename($0)} -n scan -r 1 ... N -s sub1 ... subN\n"
  opt :name, "Name of scan (movie or rest)", :type => :string, :required => true
  opt :runs, "Which runs to process", :type => :ints, :required => true
  opt :subjects, "Which subjects to process", :type => :strings, :required => true
end
opts = Trollop::with_standard_exception_handling p do
  raise Trollop::HelpNeeded if ARGV.empty? # show help screen
  p.parse ARGV
end

# Gather inputs
scan        = opts[:name]
runs        = opts[:runs]
subjects    = opts[:subjects]

# Set Paths
## general
ENV['BASEDIR']  ||= "/home/data/Projects/emotional-bs"
basedir           = ENV['BASEDIR']
qadir             = "#{basedir}/00_QA"
origdir           = "#{basedir}/01_Originals"
preprocdir        = "#{basedir}/02_PreProcessed"
## html output    
layout_file       = SCRIPTDIR + "etc/layout.html.erb"
body_file         = SCRIPTDIR + "etc/01_preprocessing/#{SCRIPTNAME}.md.erb"
report_file       = "#{qadir}/02_PreProcessed_#{SCRIPTNAME}.html"
@body             = ""

exit 2 if any_inputs_dont_exist_including qadir, origdir, preprocdir

# Loop through each subject
subjects.each do |subject|
  puts "= Subject: #{subject} \n".white.on_blue
    
  puts "\n== Setting input variables".magenta
  in_subdir     = "#{origdir}/#{subject}"
  
  puts "\n== Checking inputs".magenta
  next if any_inputs_dont_exist_including in_subdir
  
  puts "\n== Setting output variables".magenta
  out_subdir    = "#{preprocdir}/#{subject}"
    
  puts "\n== Creating output directories (if needed)".magenta
  Dir.mkdir out_subdir if not File.directory? out_subdir
  
  runs.each_with_index do |run, i|
    puts "\n== Run #{run}"
    
    puts "\n=== Setting input variables".magenta
    in_rundir           = "#{in_subdir}/#{scan}#{run}"
    original            = "#{in_rundir}/func.nii.gz"
    
    puts "\n== Checking inputs".magenta
    next if any_inputs_dont_exist_including original    
    
    puts "\n=== Setting output variables".magenta
    out_rundir          = "#{out_subdir}/#{scan}/run_%02d" % run
    ppdir               = "#{out_rundir}/01_preprocess"
    mcref               = "#{out_subdir}/#{scan}/run_01/func_ref.nii.gz"  # same across runs
    motion              = "#{out_rundir}/motion.1D"
    brain_mask          = "#{out_rundir}/func_mask.nii.gz"
    brain_axial_pic     = "#{out_rundir}/func_brain_mask_axial.png"
    brain_sagittal_pic  = "#{out_rundir}/func_brain_mask_sagittal.png"
    brain               = "#{out_rundir}/func_brain.nii.gz"
    mean                = "#{out_rundir}/func_mean.nii.gz"
    
    puts "\n== Checking outputs".magenta
    next if all_outputs_exist_including csf_mask, wm_mask, wm_edge
    
    puts "\n== Creating output directories (if needed)".magenta
    Dir.mkdir out_rundir if not File.directory? out_rundir
    Dir.mkdir ppdir if not File.directory? ppdir
    
    puts "\n=== Excluding first 4 time points".magenta
    run "3dcalc -a #{original}'[4..$]' -expr 'a' \
          -prefix #{ppdir}/01_exclude_tpts.nii.gz"
    
    puts "\n=== Performing slice time correction".magenta
    run "3dTshift -TR Xs -slice X -tpattern X \
          -prefix #{ppdir}/02_slice_time.nii.gz"
    
    puts "\n=== Deobliquing to be AFNI friendly".magenta
    run "3dcopy #{ppdir}/02_slice_time.nii.gz #{ppdir}/03_deoblique.nii.gz"
    run "3drefit -deoblique #{ppdir}/03_deoblique.nii.gz"
    
    puts "\n=== Reorienting to be FSL friendly".magenta
    run "3dresample -inset #{ppdir}/03_deoblique.nii.gz -orient RPI \
          -prefix #{ppdir}/04_reorient.nii.gz"
    
    if i == 0
      run "3dcalc -a #{ppdir}/04_reorient.nii.gz'[0]' -expr 'a' -prefix #{mcref}"
    else
      run "ln -s #{mcref} #{rundir}/"
    end
    
    puts "\n=== Motion correcting".magenta
    puts "=== using the 1st image of run #1 as the reference".magenta
    run "3dvolreg -Fourier -prefix #{ppdir}/05_motion_correct.nii.gz \
          -base #{mcref} -1Dfile #{motion} #{ppdir}/04_reorient.nii.gz"
    
    puts "\n=== Generating brain mask".magenta
    run "3dAutomask -dilate 1 -prefix #{brain_mask} #{ppdir}/05_motion_correct.nii.gz"
    
    puts "\n=== Creating pretty pictures".magenta
    run "slicer.py -w 5 -l 4 -s axial --overlay #{brain_mask} 1 1 -t #{mcref} #{brain_axial_pic}"
    run "slicer.py -w 5 -l 4 -s sagittal --overlay #{brain_mask} 1 1 -t #{head} #{brain_sagittal_pic}"
    
    puts "\n=== Applying mask to get only the brain".magenta
    run "3dcalc -a #{ppdir}/05_motion_correct.nii.gz -b #{brain_mask} \
          -expr 'a*ispositive(b)' -prefix #{brain}"
    
    puts "\n=== Creating average EPI".magenta
    run "3dTstat -mean -prefix #{mean} #{brain}"
    
  end
    
end
