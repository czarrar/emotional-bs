#!/usr/bin/env ruby
# 
#  preproc01.rb
#  
#  This script preprocessing rest and task-based fMRI data
#
#  Created by Zarrar Shehzad on 2012-09-24.
# 

# allows adding color to output
require 'colorize'

# Light wrapper around system
# prints command and any error messages if command fails
def run(command, error_message=nil)
  # print command
  l = command.split
  print l[0].light_blue.underline, l[1..-1].light_green, '\n'
  # execute command
  retval = system "time #{command}"
  # show error message
  if not retval:
    puts error_message.light_red if not error_message.nil?
    raise "command: #{command} failed"
  return retval
end

# Method to remove file extension including '.tar.gz' or '.nii.gz'
class String
  def rmext
    File.basename(self.chomp('.gz'), '.*')
  end
end

# Set Paths
# => note: prefix of 't_' is for string variables that have element(s) requiring 
# =>       subtitution/interpolation.
## general
basedir         = "/home/data/Projects/emotional-bs"
origdir         = "#{basedir}/01_Originals"
preprocdir      = "#{basedir}/02_PreProcessed"
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


# Usage
if ARGV.length == 0
  puts "usage: #{$0} subject1 subject2 ... subjectN".light_blue
  exit 1
end

# Gather scans by subjects and runs to process
subjects  = ARGV
runs      = 1..2

# Loop through each subject
subjects.each do |subject|
  puts "= Subject: #{subject} ".white.on_blue
  
  svars = {:subject => subject}
  out_subdir  = t_out_subdir % svars
  out_anatdir = t_out_anatdir % svars
  
  Dir.mkdir out_subdir  if not File.directory? out_subdir
  Dir.mkdir out_anatdir if not File.directory? out_anatdir
  
  runs.each do |run|
    puts "== Run".light_magenta
    
    rvars = {:subject => subject, :run => run}  
    in_t1       = t_in_t1 % rvars
    out_rundir  = t_out_rundir % rvars
    deoblique   = "#{out_rundir}/deoblique.nii.gz"
    reorient    = t_out_runhead % rvars
    skullstrip  = t_out_runbrain % rvars
    
    Dir.mkdir out_rundir if not File.directory? out_rundir
    
    puts "=== Deobliquing to be AFNI friendly".cyan
    run "3dcopy #{in_t1} #{deoblique}"
    run "3drefit -deoblique #{deoblique}"
    
    puts "=== Re-orienting to be FSL friendly".cyan
    fname[/.*(?=.nii.gz$)/]
    run "3dresample -orient RPI -prefix #{deoblique} -inset #{reorient}"
    
    puts "=== Skullstripping".cyan
    run "3dSkullStrip -orig_vol -input #{reorient} -prefix #{skullstrip}"    
  end
  
  run1, run2      = runs.collect{|run| t_out_rundir % {:subject => subject, :run => run}}
  head1, head2    = runs.collect{|run| t_out_runhead % {:subject => subject, :run => run}}
  brain1, brain2  = runs.collect{|run| t_out_runbrain % {:subject => subject, :run => run}}
  
  puts "== Registering run-1 brain to run-2 brain"
  run "flirt -in #{brain1} -ref #{brain2} -dof 6 -omat #{brain1.rmext}2run2.mat -out #{brain1.rmext}2run2.nii.gz"

  puts "== Applying transformation for run-1's head to be like run-2's head"
  run "flirt -in #{head1} -ref #{head2} -applyxfm -init #{brain1.rmext}2run2.nii.gz -out #{head1.rmext}2run2.nii.gz"
  
  puts "== Averaging the two brains"
  run "3dcalc -a #{brain1.rmext}2run2.nii.gz -b #{brain2} -expr '(a+b)/2' -prefix #{t_out_brain % svars}"
      
  puts "== Averaging the two heads"
  run "3dcalc -a #{head1.rmext}2run2.nii.gz -b #{head2} -expr '(a+b)/2' -prefix #{t_out_head % svars}"
  
  puts "== Removing individual run directories"
  run "rm -r %s %s" % [run1, run2]
end

