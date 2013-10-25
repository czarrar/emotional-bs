#!/usr/bin/env ruby
# 
#  preproc01.rb
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

# Gather scans by subjects and runs to process
subjects  = ARGV
runs      = 1..2


# Set Paths
# => note: prefix of 't_' is for string variables that have element(s) requiring 
# =>       subtitution/interpolation.
## general
ENV['BASEDIR'] ||= "/home/data/Projects/emotional-bs"
basedir         = ENV['BASEDIR']
origdir         = "#{basedir}/01_Originals"
preprocdir      = "#{basedir}/02_PreProcessed"
Process.exit if input_doesnt_exist(origdir) or input_doesnt_exist(preprocdir)
## inputs
t_in_subdir     = "#{origdir}/%{subject}"
t_in_anatdir    = "#{t_in_subdir}/anat%{run}"
t_in_t1         = "#{t_in_anatdir}/mprage.nii.gz"
## outputs
t_out_subdir    = "#{preprocdir}/%{subject}"
t_out_anatdir   = "#{t_out_subdir}/anat"
t_out_rundir    = "#{t_out_anatdir}/run%{run}"
t_out_runhead   = "#{t_out_rundir}/head.nii.gz"
t_out_runbrain  = "#{t_out_rundir}/brain.nii.gz"
t_out_head      = "#{t_out_anatdir}/anat/head.nii.gz"
t_out_brain     = "#{t_out_anatdir}/anat/brain.nii.gz"


# Loop through each subject
subjects.each do |subject|
  puts "= Subject: #{subject} \n".white.on_blue
  
  svars = {:subject => subject}
  out_subdir  = t_out_subdir % svars
  out_anatdir = t_out_anatdir % svars
  out_head    = t_out_head % svars
  out_brain   = t_out_brain % svars
  
  next if output_exists(out_head) and output_exists(out_brain)
  
  Dir.mkdir out_subdir  if not File.directory? out_subdir
  Dir.mkdir out_anatdir if not File.directory? out_anatdir
  
  begin
    
    runs.each do |run|
      puts "== Run %i".white.on_blue % run
    
      rvars = {:subject => subject, :run => run}  
      in_t1       = t_in_t1 % rvars
      out_rundir  = t_out_rundir % rvars
      deoblique   = "#{out_rundir}/deoblique.nii.gz"
      reorient    = t_out_runhead % rvars
      skullstrip  = t_out_runbrain % rvars
    
      next if input_doesnt_exist(in_t1)
    
      Dir.mkdir out_rundir if not File.directory? out_rundir
    
      puts "\n=== Deobliquing to be AFNI friendly".magenta
      run "3dcopy #{in_t1} #{deoblique}"
      run "3drefit -deoblique #{deoblique}"
    
      puts "\n=== Re-orienting to be FSL friendly".magenta
      fname[/.*(?=.nii.gz$)/]
      run "3dresample -orient RPI -prefix #{deoblique} -inset #{reorient}"
    
      puts "\n=== Skullstripping".magenta
      run "3dSkullStrip -orig_vol -input #{reorient} -prefix #{skullstrip}"    
    end
  
    head1, head2    = runs.collect{|run| t_out_runhead % {:subject => subject, :run => run}}
    brain1, brain2  = runs.collect{|run| t_out_runbrain % {:subject => subject, :run => run}}
  
    puts "\n== Registering run-1 brain to run-2 brain"
    run "flirt -in #{brain1} -ref #{brain2} -dof 6 -omat #{brain1.rmext}2run2.mat -out #{brain1.rmext}2run2.nii.gz"

    puts "\n== Applying transformation for run-1's head to be like run-2's head"
    run "flirt -in #{head1} -ref #{head2} -applyxfm -init #{brain1.rmext}2run2.nii.gz -out #{head1.rmext}2run2.nii.gz"
  
    puts "\n== Averaging the two brains"
    run "3dcalc -a #{brain1.rmext}2run2.nii.gz -b #{brain2} -expr '(a+b)/2' -prefix #{t_out_brain % svars}"
      
    puts "\n== Averaging the two heads"
    run "3dcalc -a #{head1.rmext}2run2.nii.gz -b #{head2} -expr '(a+b)/2' -prefix #{t_out_head % svars}"
    
  ensure
    
    puts "\n== Removing individual run directories"
    run1, run2 = runs.collect{|run| t_out_rundir % {:subject => subject, :run => run}}
    run "rm -f -r %s %s" % [run1, run2]
    
  end
end

