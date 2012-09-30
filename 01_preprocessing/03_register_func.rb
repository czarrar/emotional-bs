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
require 'trollop'         # command-line option parser

# Process command-line inputs
p = Trollop::Parser.new do
  banner "Usage: #{File.basename($0)} (-e 2) -n scan -r 1 .. N -s sub1 ... subN\n"
  opt :name, "Name of scan (movie or rest)", :type => :string, :required => true
  opt :runs, "Which runs to process", :type => :ints, :required => true
  opt :subjects, "Which subjects to process", :type => :strings, :required => true
  opt :resolution, "Resolution in mm to use for standard brain", :type => :int, :default => 2
end
opts = Trollop::with_standard_exception_handling p do
  raise Trollop::HelpNeeded if ARGV.empty? # show help screen
  p.parse ARGV
end

# Gather inputs
scan        = opts[:name]
runs        = opts[:runs]
subjects    = opts[:subjects]
resolution  = opts[:resolution]

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

exit 2 if any_inputs_dont_exist_including qadir, origdir, preprocdir

# Loop through each subject
subjects.each do |subject|
  puts "= Subject: #{subject} \n".white.on_blue
  
  anatdir           = "#{preprocdir}/#{subject}/anat"
  funcdir           = "#{preprocdir}/#{subject}/#{scan}"
  
  puts "\n== Setting input variables".magenta
  rundirs           = runs.collect{|run| "#{funcdir}/run#{run}"}
  run_means         = rundirs.collect{|rundir| "#{rundir}/func_mean.nii.gz"}
  anat_regdir       = "#{anatdir}/reg"
  highres2standard  = "#{anat_regdir}/highres2standard"
  standard          = "#{ENV['FSLDIR']}/data/standard/MNI152_T1_#{resolution}mm_brain.nii.gz"
  highres           = "#{anatdir}/brain.nii.gz"
  wm_mask           = "#{anatdir}/wm_mask.nii.gz"
  
  puts "\n== Checking inputs".magenta
  next if any_inputs_dont_exist_including *rundirs, *run_means, 
                                          anat_regdir, standard, 
                                          highres, wm_mask
  
  puts "\n== Setting output variables".magenta
  example_func      = "#{funcdir}/func_mean.nii.gz"
  regdir            = "#{funcdir}/reg"
  func2highres      = "#{regdir}/func2highres"
  highres2func      = "#{regdir}/highres2func"
  func2standard     = "#{regdir}/func2standard"
  
  puts "\n== Checking outputs".magenta
  next if any_outputs_exist_including example_func, regdir
      
  puts "\n== Creating output directories (if needed)".magenta
  Dir.mkdir regdir if not File.directory? regdir
  
  puts "\n== Combine mean EPIs from each run".magenta
  run "3dTcat -prefix #{funcdir}/tmp_means.nii.gz \
        #{run_means.join(' ')}"
  
  puts "\n== Averaging mean EPIs".magenta
  run "3dTstat -mean -prefix #{example_func} #{funcdir}/tmp_means.nii.gz"
  run "rm #{funcdir}/tmp_means.nii.gz"
  
  puts "\n== Initial coregistration using flirt EPI => T1".magenta
  run "flirt -in #{example_func} -ref #{highres} -dof 6 \
        -omat #{func2highres}_init.mat -out #{func2highres}.nii.gz"
  
  puts "\n=== Creating pretty pictures".magenta
  create_reg_pics "#{func2highres}.nii.gz", highres, "#{func2highres}_initial.png"
  
  puts "\n== BBreg coregistration using flirt EPI => T1".magenta
  run "flirt -in #{example_func} -ref #{highres} -dof 6 -cost bbr \
        -wmseg #{wm_mask} -init #{func2highres}_init.mat \
        -omat #{func2highres}.mat -out #{func2highres}.nii.gz \
        -schedule %s/etc/flirtsch/bbr.sch" % ENV['FSLDIR']
  
  puts "\n=== Creating pretty pictures".magenta
  create_reg_pics "#{func2highres}.nii.gz", highres, "#{func2highres}.png"
  
  puts "\n== Linking registration output from T1 => Standard".magenta
  run "ln -s #{anat_regdir}/* #{regdir}/"
  run "rm -f #{regdir}/standard.nii.gz"
  run "ln -s #{standard} #{regdir}/standard.nii.gz"
  
  puts "\n== Invert transform to get T1 => EPI".magenta
  run "convert_xfm -omat #{highres2func}.mat -inverse #{func2highres}.mat"
  
  puts "\n== Combine transforms to get EPI => Standard".magenta
  run "convert_xfm -omat #{func2standard}.mat -concat #{highres2standard}.mat \
        #{func2highres}.mat"
  
  puts "\n== Invert transform to get Standard => EPI".magenta
  run "convert_xfm -omat #{standard2func}.mat -inverse #{func2standard}.mat"
  
  puts "\n== Apply transform to get EPI => Standard"
  run "applyxfm -i #{example_fun} -r #{standard} -o #{func2standard}.nii.gz \
        -w #{highres2standard}_warp.nii.gz --premat=#{func2highres}.mat"
  
  puts "\n=== Creating pretty pictures".magenta
  create_reg_pics "#{func2highres}.nii.gz", highres, "#{func2highres}.png"
  
  puts "\n=== Linking registration directory to individual runs".magenta
  rundirs.each{|rundir| run "ln -s #{regdir} #{rundir}/reg"}
  
end
