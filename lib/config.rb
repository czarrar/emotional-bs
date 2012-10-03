require 'for_commands.rb'

# Set paths
ENV['BASEDIR']  ||= "/home2/data"
@basedir          = ENV['BASEDIR']
@study            = "Emotional-BS"
@origdir          = "#{@basedir}/Originals/#{@study}"
@qadir            = "#{@basedir}/QC/#{@study}"
@preprocdir       = "#{@basedir}/PreProc/#{@study}"
@freesurferdir    = "#{@basedir}/Freesurfer/#{@study}"
@priordir         = "/home2/data/PublicProgram/C-PAC/tissuepriors/2mm"

@TR               = 2.01
@nslices          = 15
@slice_pattern    = "alt+z2"

exit 2 if any_inputs_dont_exist_including @origdir, @qadir, @preprocdir, 
                                          @freesurferdir
