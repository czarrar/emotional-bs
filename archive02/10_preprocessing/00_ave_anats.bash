#!/usr/bin/env bash

# Loops through each subject
# Gets the two anats
# Averages them
# Registers to the average
# Averages the registered brains
# Redoes the registration

base="/home2/data/Originals/Emotional-BS"

# Get the subjects
subjects=$( ls ${base} )

# Loop
for subject in ${subjects}; do
    echo $subject
    
    # Inputs
    subdir="${base}/${subject}"
    anat1="${subdir}/anat1/mprage.nii.gz"
    anat2="${subdir}/anat2/mprage.nii.gz"
    
    # Outputs
    outdir="${subdir}/anat"
    cmd="mkdir ${outdir} 2> /dev/null"
    echo $cmd
    eval $cmd
    
    tmpdir="${subdir}/anat/tmp"
    cmd="mkdir ${tmpdir} 2> /dev/null"
    echo $cmd
    eval $cmd
    
    
    ###
    # First Run
    ###
    
    # Average
    cmd="3dcalc -a '${anat1}' -b '${anat2}' -expr '(a+b)/2' -prefix ${tmpdir}/init_ref.nii.gz"
    echo $cmd
    eval $cmd
    
    # Register 1
    cmd="flirt -in ${anat1} -ref ${tmpdir}/init_ref.nii.gz -dof 6 -out ${tmpdir}/init_anat1.nii.gz -omat ${tmpdir}/init_anat1.mat"
    echo $cmd
    eval $cmd
    
    # Register 2
    cmd="flirt -in ${anat2} -ref ${tmpdir}/init_ref.nii.gz -dof 6 -out ${tmpdir}/init_anat2.nii.gz -omat ${tmpdir}/init_anat2.mat"
    echo $cmd
    eval $cmd
    
    
    ###
    # Second Run
    ###
    
    # Average
    cmd="3dcalc -a '${tmpdir}/init_anat1.nii.gz' -b '${tmpdir}/init_anat2.nii.gz' -expr '(a+b)/2' -prefix ${tmpdir}/next_ref.nii.gz"
    echo $cmd
    eval $cmd
    
    # Register 1
    cmd="flirt -in ${anat1} -ref ${tmpdir}/next_ref.nii.gz -dof 6 -applyxfm -init ${tmpdir}/init_anat1.mat -out ${tmpdir}/next_anat1.nii.gz -omat ${tmpdir}/next_anat1.mat"
    echo $cmd
    eval $cmd
    
    # Register 2
    cmd="flirt -in ${anat2} -ref ${tmpdir}/next_ref.nii.gz -dof 6 -applyxfm -init ${tmpdir}/init_anat2.mat -out ${tmpdir}/next_anat2.nii.gz -omat ${tmpdir}/next_anat2.mat"
    echo $cmd
    eval $cmd
    
    
    ###
    # Final Image
    ###
    
    cmd="3dcalc -a '${tmpdir}/next_anat1.nii.gz' -b '${tmpdir}/next_anat2.nii.gz' -expr '(a+b)/2' -prefix ${outdir}/mprage.nii.gz"
    echo $cmd
    eval $cmd
    
done