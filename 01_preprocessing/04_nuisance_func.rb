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

require 'config.rb'       # globalish variables
require 'for_commands.rb' # provides various function such as 'run'
require 'colorize'        # allows adding color to output
require 'erb'             # for interpreting erb to create report pages
require 'reg_help.rb'     # provides 'create_reg_pics' function
require 'trollop'         # command-line option parser

# Process command-line inputs
p = Trollop::Parser.new do
  banner "Usage: #{File.basename($0)} (-e 2) -n scan -r 1 .. N -s sub1 ... subN\n"
  opt :name, "Name of scan (movie or rest)", :type => :string, :required => true
  opt :runs, "Which runs to process", :type => :ints, :required => true
  opt :subjects, "Which subjects to process", :type => :strings, :required => true
  opt :low_band, "Low end of band-pass filter", :type => :float, 
    :default => 0
  opt :high_band, "High end of band-pass filter", :type => :float, :default => 999
  opt :fwhm, "FWHM for spatial smoothing", :type => :int, :default => 6
  opt :wm_radius, "Radius for detecting WM voxels when doing anaticor", 
    :type => :int, :default => 30
end
opts = Trollop::with_standard_exception_handling p do
  raise Trollop::HelpNeeded if ARGV.empty? # show help screen
  p.parse ARGV
end

# Gather inputs
scan        = opts[:name]
runs        = opts[:runs]
subjects    = opts[:subjects]
low_bad     = opts[:low_band]
high_band   = opts[:high_band]
fwhm        = opts[:fwhm]
wm_radius   = opts[:wm_radius]

subjects.each do |subject|
  puts "\n= Subject #{subject}".white.on_blue
    
  puts "\n== Setting input variables".magenta
  subdir        = "#{@preprocdir}/#{subject}"
  anatdir       = "#{subdir}/anat"
  funcdir       = "#{subdir}/#{scan}"
  regdir        = "#{funcdir}/reg"
  csf_mask      = "#{anatdir}/csf_mask.nii.gz"
  wm_mask       = "#{anatdir}/wm_mask.nii.gz"
  func_mean     = "#{funcdir}/func_mean.nii.gz"
  func_mask     = "#{funcdir}/func_mask.nii.gz"
  highres2func  = "#{regdir}/highres2example_func"
      
  puts "\n== Checking inputs".magenta
  next if any_inputs_dont_exist_including csf_mask, wm_mask, func_mean, 
                                          func_mask, "#{highres2func}.mat"
    
  puts "\n== Setting output variables".magenta
  segdir        = "#{funcdir}/segment"
  csf           = "#{segdir}/csf_mask.nii.gz"
  wm            = "#{segdir}/wm_mask.nii.gz"
  func2highres  = "#{regdir}/example_func2highres"
      
  puts "\n=== Checking outputs".magenta
  next if all_outputs_exist_including csf, wm, func2highres
  
  puts "\n=== Creating output directories (if necessary)".magenta
  Dir.mkdir segdir if not File.directory? segdir
  
  # if we fractionize the CSF mask and then dilate, there is
  # nothing left in the mask, instead we do the extremely painful
  # thing of fractionating the CSF mask to 2mmm space and then 
  # copying the EPI data to 2mm just long enough to extract the CSF
  # signal
  
  puts "\n== Fractionizing CSF mask to T1 space at 2mm".magenta
  run "3dresample -input #{csf_mask} -dxyz 2 2 2 -rmode NN \
        -prefix #{segdir}/csf_01_mask_unthr.nii.gz -overwrite"
  run "3dcalc -a #{segdir}/csf_01_mask_unthr.nii.gz -expr 'step(a-0.5)' \
        -prefix #{segdir}/csf_02_mask_thr+bin.nii.gz -datum short"
  
  puts "\n== Eroding CSF mask to minize PVE".magenta
  run "3dcalc -a #{segdir}/csf_02_mask_thr+bin.nii.gz -b a+i -c a-i -d a+j \
        -e a-j -f a+k -g a-k -expr 'a*(1-amongst(0,b,c,d,e,f,g))' \
        -prefix #{segdir}/csf_03_mask_erode.nii.gz"
  
  puts "\n== Transforming CSF prior to T1 space at 2mm".magenta
  run "flirt -in #{@priordir}/avg152T1_csf_bin.nii.gz \
        -ref #{segdir}/csf_01_mask_unthr.nii.gz \
        -out #{segdir}/csfprior_mask_unthr.nii.gz \
        -applyxfm -init #{anatdir}/reg/standard2highres.mat"
  run "3dcalc -a #{segdir}/csfprior_mask_unthr.nii.gz -expr 'step(a-0.5)' \
        -prefix #{segdir}/csfprior_mask.nii.gz"
  
  puts "\n== Masking CSF mask by prior mask".magenta
  run "3dcalc -a #{segdir}/csf_03_mask_erode.nii.gz \
        -b #{segdir}/csfprior_mask.nii.gz -expr 'step(a)*step(b)' \
        -prefix #{segdir}/csf_04_mask_prior.nii.gz"
  
  run "ln -s #{segdir}/csf_04_mask_prior.nii.gz #{csf}"
  
  # now we handle the WM file to get regressor for anaticorr
  # fractionize image to EPI space
  
  puts "\n== Transforming WM mask to EPI space".magenta
  run "flirt -in #{wm_mask} -ref #{func_mean} \
        -out #{segdir}/wm_01_mask2func.nii.gz -init #{highres2func}.mat \
        -applyxfm"
  run "3dcalc -a #{segdir}/wm_01_mask2func.nii.gz -expr 'step(a-.5)' \
        -prefix #{segdir}/wm_02_mask2func_thr.nii.gz -datum short"
  
  puts "\n== Erode WM mask by one voxel to minimize PVE".magenta
  run "3dcalc -a #{segdir}/wm_02_mask_thr.nii.gz -b a+i -c a-i -d a+j \
        -e a-j -f a+k -g a-k -expr 'a*(1-amongst(0,b,c,d,e,f,g))' \
        -prefix #{segdir}/wm_03_mask_erode.nii.gz"
  run "ln -s #{segdir}/wm_03_mask_erode.nii.gz #{wm}"
  
  runs.each do |run|
    
    puts "\n== Run #{run}".white.on_blue
    
    puts "\n=== Setting input variables".magenta
    rundir          = "#{funcdir}/run_%02d" % run
    func            = "#{rundir}/func_brain.nii.gz"
    motion          = "#{rundir}/motion.1D"
    
    puts "\nChecking inputs".magenta
    next if any_inputs_dont_exist_including func, motion
    
    puts "\n=== Setting output variables".magenta
    nvrdir          = "#{rundir}/02_nuisance"
    csf_ts          = "#{nvrdir}/ts_csf.1D"
    wm_ts           = "#{nvrdir}/ts_wm.nii.gz"
    motion_friston  = "#{nvrdir}/ts_motion_friston.1D"
    func_denoise    = "#{rundir}/func_denoise.nii.gz"
    func_smoothed   = "#{rundir}/func_denoise+smooth.nii.gz"
    
    puts "\n=== Checking outputs".magenta
    next if all_outputs_exist_including csf_ts, wm_ts, motion_friston, 
                                        func_denoise, func_filtered, 
                                        func_smoothed, func_filtered_smoothed
    
    puts "\n=== Creating output directories (if necessary)".magenta
    Dir.mkdir nvrdir if not File.directory? nvrdir
    
    # if we fractionize the CSF mask and then dilate, there is
    # nothing left in the mask, instead we do the extremely painful
    # thing of fractionating the CSF mask to 2mmm space and then 
    # copying the EPI data to 2mm just long enough to extract the CSF
    # signal
  
    puts "\n== Transforming EPI data to T1 space at 2mm".magenta
    run "flirt -in #{func} -ref #{csf} -out #{nvrdir}/func2highres_2mm.nii.gz \
          -init #{func2highres}.mat -applyisoxfm 2"
    
    puts "\n== Extract CSF time-series".magenta
    run "3dmaskave -q -mask #{nvrdir}/csf_03_mask_erode.nii.gz \
          #{nvrdir}/func2highres_2mm.nii.gz > #{csf_ts}"
  
    # now we handle the WM file to get regressor for anaticorr
    # fractionize image to EPI space
  
    puts "\n== Extracting WM 4D time-series".magenta
    puts "== each voxel will have a unique timecourse".magenta
    puts "== based on the average of the nearest WM voxel".magenta
    run "3dLocalstat -prefix #{nvrdir}/wm_04_local_ts.nii.gz \
          -nbhd 'SPHERE(#{wm_radius})' \
          -stat mean -mask #{func_mask} -use_nonmask #{func}"
    
    puts "\n== Detrending WM time-series".magenta
    run "3dDetrend -normalize -prefix #{wm_ts} \
          -polort A #{nvrdir}/wm_04_local_ts.nii.gz"
    
    # motion
    
    puts "\n== Calculating Friston Motion Model".magenta
    run ".#{SCRIPTDIR}/bin/mask_friston_motion.pl #{motion} \
          > #{motion_friston}"
    
    # nuisance
    
    puts "\n== Combining CSF and Motion into one Nuisance ORT file".magenta
    run "1dcat #{csf_ts} #{motion_friston} > #{nvrdir}/csf+motion.1D"
  
    puts "\n== Detrending Nuisance ORT file".magenta
    run "3dDetrend -DAFNI_1D_TRANOUT=YES -normalize \
          -prefix #{nvrdir}/csf_motion_detrend.1D \
          -polort A #{nvrdir}/csf+motion.1D\' \
          -overwrite"
    
    # nuisance regression
    
    puts "\n== Performing nuisance variable regression".magenta
    run "3dTfitter -polort A \
          -RHS #{func} \
          -LHS #{nvrdir}/csf+motion_detrend.1D \
          -prefix #{nvrdir}/nvr_beta.nii.gz \
          -fitts #{nvrdir}/nvr_fitts.nii.gz \
          -errsum #{nvrdir}/nvr_errsum.nii.gz"
    run "3dcalc -float -a #{func} -b #{nvrdir}/nvr_fitts.nii.gz -expr 'a-b' \
          -prefix #{func_denoise}"
  
    puts "\n== Make sure the TR is correct".magenta
    run "3drefit -TR #{TR} #{func_denoise}"
    
    # smooth
      
    puts "\n== Smoothing data".magenta
    run "3dBlurInMask -input #{func_denoise} -FWHM #{fwhm} \
          -mask #{func_mask} -prefix #{func_smoothed}"
    
  end
end



