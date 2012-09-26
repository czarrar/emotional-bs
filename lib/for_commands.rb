#!/usr/bin/env ruby

require 'colorize'
require 'pathname'

def input_doesnt_exist(path)
  retval = !File.exists?(path)
  puts "Input '#{path}' doesn't exist!".light_red if retval
  return retval
end

def output_exists(path)
  retval = File.exists?(path)
  puts "Output '#{path}' already exists.".red if retval
  return retval
end

def any_inputs_dont_exist_including(*paths)
  paths.reduce(false) {|retval,path| input_doesnt_exist(path) or retval }
end

def all_outputs_exist_including(*paths)
  paths.reduce(true) {|retval,path| output_exists(path) and retval }
end

# Light wrapper around system
# prints command and any error messages if command fails
def run(command, error_message=nil)
  # print command
  l = command.split
  prog = l[0].light_blue
  args = l[1..-1].join(' ').green
  puts "%s %s" % [prog, args]
  
  # execute command
  retval = system "time #{command}"
  
  # show error message
  if not retval
    error_message ||= "Error: execution of ".light_red + prog + " failed".light_red
    puts error_message
    raise "program cannot proceed"
  end
  
  return retval
end

# Method to remove file extension including '.tar.gz' or '.nii.gz'
class String
  def rmext
    Pathname.new(self.chomp('.gz')).sub_ext("")
  end
end
