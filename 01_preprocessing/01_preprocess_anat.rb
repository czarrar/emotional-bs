#!/usr/bin/env ruby
# 
#  preproc01.rb
#  
#  This script preprocessing rest and task-based fMRI data
#
#  Created by Zarrar Shehzad on 2012-09-24.
# 

require 'pry'
# binding.pry

require 'pathname'
SCRIPTDIR   = Pathname.new(__FILE__).realpath.dirname.dirname
SCRIPTNAME  = Pathname.new(__FILE__).basename.sub_ext("")

# add lib directory to ruby path
$: << SCRIPTDIR + "lib" # will be scriptdir/lib

require 'colorize'        # allows adding color to output
require 'for_commands.rb' # provides various function such as 'run'
require 'erb'             # for interpreting erb to create report pages
require 'kramdown'        # for interpreting markdown to create report pages

# Usage
if ARGV.length == 0
  puts "usage: #{$0} subject1 subject2 ... subjectN".light_blue
  exit 1
end

# Gather scans by subjects and runs to process
subjects  = ARGV
runs      = 1..2


# Set Paths
# => note: prefix of 't_' is for string variables that have element(s) requiring 
# =>       subtitution/interpolation.
## general
ENV['BASEDIR']  ||= "/home/data/Projects/emotional-bs"
basedir           = ENV['BASEDIR']
qadir             = "#{basedir}/00_QA"
origdir           = "#{basedir}/01_Originals"
preprocdir        = "#{basedir}/02_PreProcessed"
freesurferdir     = "#{basedir}/02_Freesurfer"
## inputs
t_in_subdir       = "#{origdir}/%{subject}"
t_original        = "#{t_in_subdir}/anat%{run}/mprage.nii.gz"
## outputs        
t_out_subdir      = "#{preprocdir}/%{subject}"
t_anatdir         = "#{t_out_subdir}/anat"
t_head            = "#{t_anatdir}/head.nii.gz"
t_brain           = "#{t_anatdir}/brain.nii.gz"
t_brain_mask      = "#{t_anatdir}/brain_mask.nii.gz"
## html output    
layout_file       = SCRIPTDIR + "etc/layout.html.erb"
body_file         = SCRIPTDIR + "etc/01_preprocessing/#{SCRIPTNAME}.md.erb"
report_file       = "#{qadir}/02_PreProcessed_#{SCRIPTNAME}.html"
@body             = ""

exit 2 if any_inputs_dont_exist_including qadir, origdir, preprocdir, freesurferdir

# Loop through each subject
subjects.each do |subject|
  puts "= Subject: #{subject} \n".white.on_blue
  
  in_subdir       = t_in_subdir % {:subject => subject}
  originals       = runs.collect{|run| t_original % {:subject => subject, :run => run}}
  fixed_originals = originals.collect{|orig| "#{orig.rmext}_tmpfix.nii.gz" }
  
  svars = {:subject => subject}
  out_subdir  = t_out_subdir % svars
  anatdir     = t_anatdir % svars
  mridir      = "#{freesurferdir}/#{subject}/mri"
  head        = t_head % svars
  brain       = t_brain % svars
  brain_mask  = t_brain_mask % svars
  head_pic                = "#{head.rmext}_axial_pic.png"
  brain_mask_axial_pic    = "#{brain_mask.rmext}_axial_pic.png"
  brain_mask_sagittal_pic = "#{brain_mask.rmext}_sagittal_pic.png"
  
  puts "\n== Updating report page".magenta
  text      = File.open(body_file).read
  erbified  = ERB.new(text).result(binding)
  markified = Kramdown::Document.new(erbified).to_html
  @body    += "\n #{markified} \n"
  
  next if any_inputs_dont_exist_including freesurferdir, *originals
  next if all_outputs_exist_including head, brain, brain_mask
  
  Dir.mkdir out_subdir if not File.directory? out_subdir
  Dir.mkdir anatdir if not File.directory? anatdir
  
  begin
    
    if File.exists? "#{mridir}/T1.mgz" and File.exists? "#{mridir}/brainmask.mgz"
      puts "\n== Freesurfer output already exists, skipping recon-all".red
    else
      puts "\n== Ghetto fix to T1 headers".magenta
      puts "== this deals with unrecognized slice time info that spooks Freesurfer".magenta
      runs.each_with_index do |run,i|
        puts "=== Fixing run ##{run}".light_magenta
        run "fslmaths #{originals[i]} #{fixed_originals[i]}"
      end
      
      puts "\n== Using freesurfer for intensity normalization and skull stripping".magenta
      run "recon-all -i %s -autorecon1 -s #{subject} -sd #{freesurferdir}" % fixed_originals.join(" -i ")
    end
    
    puts "\n== Converting freesurfer output to nifti format".magenta
    run "mri_convert #{mridir}/T1.mgz #{anatdir}/tmp_head.nii.gz"
    run "mri_convert #{mridir}/brainmask.mgz #{anatdir}/tmp_brain.nii.gz"
    
    puts "\n== Reorienting head and brain to be FSL friendly".magenta
    run "3dresample -orient RPI -inset #{anatdir}/tmp_head.nii.gz -prefix #{head}"
    run "3dresample -orient RPI -inset #{anatdir}/tmp_brain.nii.gz -prefix #{brain}"
    
    puts "\n== Generating brain mask".magenta
    run "3dcalc -a #{brain} -expr 'step(a)' -prefix #{brain_mask}"
    
    puts "\n== Creating pretty pictures".magenta    
    run "slicer.py -w 4 -l 3 -s axial #{head} #{head_pic}"
    run "slicer.py -w 4 -l 3 -s axial --overlay #{brain_mask} 1 1 -t #{head} #{brain_mask_axial_pic}"
    run "slicer.py -w 4 -l 3 -s sagittal --overlay #{brain_mask} 1 1 -t #{head} #{brain_mask_sagittal_pic}"
        
  ensure
    
    puts "\n== Removing intermediate files"
    run "rm -f %s #{anatdir}/tmp_*.nii.gz" % fixed_originals.join(" ")
    
  end
  
end


@title          = "Anatomical Preprocessing"
@nav_title      = @title
@dropdown_title = "Subjects"
@dropdown_elems = subjects
@foundation     = SCRIPTDIR + "lib/foundation"

puts "\n= Compiling and writing report page to %s".magenta % report_file
text      = File.open(layout_file).read
erbified  = ERB.new(text).result(binding)
File.open(report_file, 'w') { |file| file.write(erbified) }

puts ""
