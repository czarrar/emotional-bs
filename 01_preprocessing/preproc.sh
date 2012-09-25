#!/bin/bash

################################################################################
###  Most excellent resting state preprocessing script, written by:          ###
###                          Cameron Craddock                                ###
###  Includes:                                                               ###
###     1. Non-linear registration of subject space to MNI152 using fNIRT    ###
###     2. Super duper coregistration between EPI and T1 using flirt bbreg   ###
###     3. Anat-ICORR for removing physiological noise measured in WM and CSF###
################################################################################
argc=$#
argv=("$@")

echo "$argc ${argv[0]}"

# PNAS TEMPLATES
PNAS_TEMPLATES=${FSLDIR}/data/standard/PNAS_Smith09_rsn10_4mm.nii.gz

# to make debugging more bearable
CC_DEBUG=1

MY_NAME=`basename $0`

DBG_CONTINUE ()
{
    if [ "$CC_DEBUG" -eq "1" ]
    then
        echo "ERROR @ [${MY_NAME}:${1}]"
        exit 1
    fi 
}

wm_radius=30

for (( i=0; i<argc; i++ ))
do
    dir=${argv[$i]}
    # verify that the file exists, is appropriate, and parse out 
    # relevant information
    if [ -d ${dir} ]; then
        if [[ ${dir} =~ '[0-9]+_[a-zA-Z]*' ]]; then
            if [[ ${#BASH_REMATCH[*]} -eq 1 ]]; then
                subjid=${BASH_REMATCH[0]}
                echo "$subjid"
            else
                echo "$dir could not be parsed"
                continue    
            fi
            echo "$dir parsed into $subjid"
        else
            echo "$dir does not match"
            continue
        fi
    else 
        echo "$dir does not exist" 
        continue
    fi

    # move into the directory for further processing
    cd ${dir}
 
    t1_file=d${subjid}_t1.nii.gz
    if [ -f $t1_file ]
    then
        echo "=== T1 is ready to go"
    else
        echo "=== Preparing T1 file"

        # de-obliqued T1
        echo "= 3dcopy"
        time 3dcopy  ${dir}/anat/mprage.nii.gz rm_${t1_file} 

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
             echo "Error copying T1 ${dir}/anat/mprage.nii.gz to rm_${t1_file}"
             DBG_CONTINUE $LINENO; continue;
        fi

        echo "= 3drefit"
        time 3drefit -deoblique rm_${t1_file} 

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
             echo "Error deobliquing T1 rm_${t1_file}"
             DBG_CONTINUE $LINENO; continue;
        fi

        echo "= 3dresample"
        time 3dresample -orient RPI -prefix ${t1_file} -inset rm_${t1_file}

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
             echo "Error reorienting T1 to RPI"
             DBG_CONTINUE $LINENO; continue;
        fi
    fi

    ss_t1_file=ss${t1_file}
    if [ -f $ss_t1_file ]
    then
        echo "=== Skullstripped T1 already exists"
    else
        # skullstrip image
        echo "=== Skullstripping T1"
        time 3dSkullStrip -orig_vol -input ${t1_file} -prefix ss${t1_file}

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
             echo "Error skullstripping T1"
             DBG_CONTINUE $LINENO; continue;
        fi
    fi

    ### make the various masks that we need for bbreg and ANATICORR, they
    ### require slightly different processing
    csf_mask=${ss_t1_file%%.nii.gz}_csf.nii.gz
    bbreg_target=${ss_t1_file%%.nii.gz}_wmseg.nii.gz
    bbreg_edge=${ss_t1_file%%.nii.gz}_wmedge.nii.gz

    if [ -f ${csf_mask} -a -f ${bbreg_target} -a -f ${bbreg_edge} ]
    then
        echo "=== Segmentation masks all exist"
    else

        if [ -f rm_${ss_t1_file%%.nii.gz}_pve_0.nii.gz -a \
             -f rm_${ss_t1_file%%.nii.gz}_pve_1.nii.gz -a \
             -f rm_${ss_t1_file%%.nii.gz}_pve_2.nii.gz ]
        then
            echo "=== Segmentation results already exist"
        else

            echo "=== Segmenting skullstripped T1 ${ss_t1_file}"

             # use FAST to segment the T1
            time fast --channels=1 --type=1 --class=3 \
                 --out=rm_${ss_t1_file} ${ss_t1_file}

            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error segmenting skullstripped T1"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi

        # if we got this far, might as well recalculate the 
        # masks, delete anything that was hanging around
        rm -f ${csf_mask} rm_${csf_mask} rm_frac_${csf_mask} 
        rm -f rm_frac_clean_${csf_mask} ${lv_mask}
        rm -f ${wm_mask} rm_${wm_mask} rm_frac_${wm_mask} 
        rm -f rm_frac_clean_${wm_mask} ${bbreg_target}
        rm -f ${bbreg_edge}
         
        # create wm and csf masks from results of segmentation
        in_csf_file=rm_${ss_t1_file%%.nii.gz}_pve_0.nii.gz

        echo "= 3dcalc thresh csf file"
        # threshold csf file
        time 3dcalc -a ${in_csf_file} -expr 'step(a-.5)' \
            -prefix ${csf_mask} -datum short

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error thresholding ${in_csf_file}"
            DBG_CONTINUE $LINENO; continue;
        fi

        # now do all of that again for white matter
        in_wm_file=rm_${ss_t1_file%%.nii.gz}_pve_2.nii.gz
 
        echo "= 3dcalc thresh wm file"
        # threshold wm file, the result is the bbreg target
        time 3dcalc -a ${in_wm_file} -expr 'step(a-.5)' \
            -prefix ${bbreg_target} -datum short

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error thresholding ${in_wm_file}"
            DBG_CONTINUE $LINENO; continue;
        fi

        # also construct a WM "edge" mask for evaluating
        # segmentation and later bbreg results
        echo "= fslmaths make wm edge"
        time fslmaths ${bbreg_target} -edge -bin \
             -mas ${bbreg_target} ${bbreg_edge}

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error creating edge from ${bbreg_target}"
            DBG_CONTINUE $LINENO; continue;
        fi

    fi

    ## now calculate T1 - MNI transformation using flirt+fnirt
    warp_file=${subjid}_T1_2_MNI152_2mm.nii.gz
    if [ -f ${warp_file} ]
    then
        echo "=== T1->MNI Warp already exists"
    else
        echo "=== Calculating T1->MNI Warp"

        # delete rm_affine_transf.mat to make sure it doesn't 
        # conflict with anything
        rm -f rm_affine_transf.mat

        echo "= flirt"
        # use flirt + fnirt to normalize T1 to MNI152 template
        time flirt -ref ${FSLDIR}/data/standard/MNI152_T1_2mm_brain.nii.gz \
             -in ${ss_t1_file} -omat rm_affine_transf.mat

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error flirting ${ss_t1_file}"
            DBG_CONTINUE $LINENO; continue;
        fi

        echo "= fnirt"
        time fnirt --in=${t1_file} --aff=rm_affine_transf.mat \
            --cout=${warp_file}  \
            --config=T1_2_MNI152_2mm

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error fnirting ${t1_file}"
            DBG_CONTINUE $LINENO; continue;
        fi
    fi

    # write the T1 into MNI space at 1mm
    norm_t1_file=w${t1_file}
    if [ -f ${norm_t1_file} ]
    then 
        echo "=== T1 is already in T1 space ($norm_t1_file)"
    else
        echo "=== Copying T1 in to MNI space at 1mm" 
        time applywarp --ref=${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz \
            --in=${t1_file} --warp=${warp_file} \
            --out=${norm_t1_file}
        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error copying ${t1_file} into MNI space"
            DBG_CONTINUE $LINENO; continue;
        fi
    fi

    norm_ss_t1_file=w${ss_t1_file}
    if [ -f ${norm_ss_t1_file} ]
    then
        echo "=== SkullStripped T1 is already in MNI space"
    else 
        echo "=== Copying ${ss_t1_file} into MNI space"
        time applywarp --ref=${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz \
                  --in=${ss_t1_file} --warp=${warp_file} \
                  --out=${norm_ss_t1_file}

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error copying ${ss_t1_file} into MNI space"
            DBG_CONTINUE $LINENO; continue;
        fi
    fi

    # now make the grey matter mask in normal space
    gm_mask=sw${ss_t1_file%%.nii.gz}_gm.nii.gz
    in_gm_file=rm_${ss_t1_file%%.nii.gz}_pve_1.nii.gz
    # write gray matter mask into norm space
    if [ -f ${gm_mask} ]
    then
        echo "=== GM mask ($gm_mask) already in MNI space"
    else
        echo "=== Writing $in_gm_file into MNI space"
        # create gm 
        time applywarp --ref=${FSLDIR}/data/standard/MNI152_T1_1mm.nii.gz \
                  --in=${in_gm_file} --warp=${warp_file} \
                  --out=rm_${gm_mask##s}

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error copying ${in_gm_file} into MNI space"
            DBG_CONTINUE $LINENO; continue;
        fi

        echo "=== Smoothing GM mask"
        time 3dmerge -1blur_fwhm 6 -doall -prefix ${gm_mask} rm_${gm_mask##s}
        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error smoothing rm_${gm_mask##s}"
            DBG_CONTINUE $LINENO; continue;
        fi
    fi


    #----- BASIC fMRI preprocessing
    bold_file=${subjid}_rest.nii.gz
    nvr_bold=snmrda${bold_file}
    filtered_nvr_bold=sfnmrda${bold_file}
    mni_nvr_bold=swnmrda${bold_file}
    mni_filtered_nvr_bold=swfnmrda${bold_file}
    mni_mean_file=wmean_mrda${bold_file}
    mni_mask_file=wmask_mrda${bold_file}

    if [ -f ${mni_nvr_bold} -a  \
         -f ${mni_filtered_nvr_bold} -a \
         -f ${nvr_bold} -a \
         -f ${filtered_nvr_bold} -a \
         -f ${mni_mean_file} -a \
         -f ${mni_mask_file} ] 
    then
        echo "All preprocess data already exist"
    else

        #make sure the file is there
        if [ -f ${dir}/func/rest.nii.gz ]; then
            echo "preprocessing ${bold_file}"
        else
            echo "${bold_file} does not exist"
            continue
        fi

        # exclude the first 4 time points
        if [ -f rm_${bold_file} ]
        then
            echo "=== Trucated ${bold_file} already exists"
        else
            echo "=== Removing first 4 TRs from ${bold_file}"
            time 3dcalc -prefix rm_${bold_file} \
                   -a ${dir}/func/rest.nii.gz'[4..$]' \
                   -expr 'a'
            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error removing first 4 TRS from ${bold_file}"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi
        prev_step=rm_${bold_file}

        # time shift
        if [ -f rm_a${prev_step##rm_} ]
        then
            echo "=== Time shifted dataset already exists"
        else
            echo "=== Time shifting dataset" 
            # time shift dataset
            time 3dTshift -TR 2.1s -slice 18 -tpattern alt+z \
                 -prefix rm_a${prev_step##rm_} ${prev_step}
            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error time shifting ${prev_step}"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi
        prev_step=rm_a${prev_step##rm_}

        # now deoblique the dataset and copy it to RPI
        if [ -f rm_d${prev_step##rm_} ]
        then
            echo "=== BOLD data already in correct orientation"
        else
            echo "=== Reorienting BOLD data"

            echo "= Deoblique"
            time 3drefit -deoblique ${prev_step}

            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error deobliquing ${prev_step}"
                DBG_CONTINUE $LINENO; continue;
            fi

            echo "= Resample to RPI"
            time 3dresample -orient RPI -prefix rm_d${prev_step##rm_} \
                -inset ${prev_step}

            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error resampling ${prev_step}"
                DBG_CONTINUE $LINENO; continue;
            fi

        fi
        prev_step=rm_d${prev_step##rm_}
    
        # coregister all EPI data to the first image of REST1
        coreg_base=rm_da${bold_file}'[0]'
        motion_file=rp_${bold_file%%.nii.gz}.1D

        if [ -f rm_r${prev_step##rm_} -a -f ${motion_file} ]
        then
            echo "=== Both rm_r${prev_step##rm_} and ${motion_file} exist"
        else
            echo "=== Motion correcting ${prev_step}"
            # motion correct data
            time 3dvolreg -Fourier -prefix rm_r${prev_step##rm_} \
                 -base ${coreg_base} -1Dfile ${motion_file} ${prev_step}

            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error motion correcting ${prev_step}"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi
        prev_step=rm_r${prev_step##rm_}
    
        # create a mask for the dataset
        mask_file=mask_${prev_step##rm_}
        if [ -f ${mask_file} ]
        then
            echo "=== Mask already exists"
        else
            echo "=== Calculating mask from ${prev_step}"
            time 3dAutomask -dilate 1 -prefix ${mask_file} ${prev_step}
            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error creating mask from  ${prev_step}"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi
    
        if [ -f rm_m${prev_step##rm_} ]
        then
            echo "=== Data already masked"
        else
            echo "=== Masking ${prev_step}"
            # mask the dataset
            time 3dcalc -a ${prev_step} -b ${mask_file} \
                 -expr 'ispositive(b)*a' -prefix rm_m${prev_step##rm_}
            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error masking ${prev_step}"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi
        prev_step=rm_m${prev_step##rm_}
         
        # create an average of this file to use for coregistering 
        # to T1 at later stage
        epi_mean_template=mean_${prev_step##rm_}
        if [ -f ${epi_mean_template} ]
        then
            echo "=== ${epi_mean_template} already exists"
        else
            echo "=== Calculating ${epi_mean_template}"
            time 3dTstat -prefix ${epi_mean_template} ${prev_step}
            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error calculating ${epi_mean_template}"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi
 
        #----- Do a bunch of silly stuff to calculate DVARS, just
        #      so we can deal with comments from WUSTL chronies
        #      when we write the paper
        ggm=$( 3dROIstats -quiet -mask ${mask_file} ${epi_mean_template} \
               | sed 's/\s*//g' )
        if [ "$?" -ne "0" ]
        then
            echo "Error calculating global global mean"
            DBG_CONTINUE $LINENO; continue;
        fi
        echo "=== Global Global Mean is ${ggm}"

        # scale the mean image intensity to 1000
        scaled_data=rm_scaled_${prev_step##rm_}
        if [ -f ${scaled_data} ]
        then
            echo "=== Scaled data already exists"
        else
            echo "=== Scaling data with ${ggm}"
            time 3dcalc -a ${prev_step} -b ${mask_file} \
                 -expr "(b*(a/${ggm}))*1000" -prefix ${scaled_data} \
                 -datum float
            if [ "$?" -ne "0" ]
            then
                echo "Error scaling data"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi

       # compute temporal of scaled data
        derivative=rm_derivative_${scaled_data##rm_}
        if [  -f ${derivative} ]
        then
            echo "=== Temporal derivative of scaled data already exists"
        else
            # first we need to know the number of TRs
            #TRend=$(3dinfo -nt ${scaled_data})
            TRend=$(fslnvols ${scaled_data})
            if [ "$?" -ne "0" ]
            then
                echo "Error getting num TRs from ${scaled_data}"
                DBG_CONTINUE $LINENO; continue;
            fi
            (( TRend-- ))
            TRendminus1=$TRend
            (( TRendminus1-- ))

            echo "=== Calculating temporal derivative for $TRend $TRendminus1"
            time 3dcalc -a "${scaled_data}[1..$TRend]" \
                        -b "${scaled_data}[0..$TRendminus1]" \
                        -expr '(a-b)' -prefix ${derivative} -datum float

            # make sure that happened
            if [ $? -ne 0 ]
            then
                echo "Error calculating temporal derivative of ${scaled_data}!"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi

        # Get square of temporal derivative
        derivative_sq=rm_square_${derivative##rm_}
        if [ -f ${derivative_sq} ]
        then
            echo "=== Squared Temporal Derivative already exists"
        else
            echo "=== Calculating Squared Temporal Derivative"
           
            3dcalc -a ${derivative} -expr 'a*a' \
                -prefix ${derivative_sq} -datum float

            # make sure that happened
            if [ $? -ne 0 ]
            then
                echo "Error calculating square of ${derivative}!"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi
 
        # 6. get mean of squared temporal derivative 
        mean_sq_temp_deriv=${derivative_sq%%.nii.gz}.1D
        if [ -f ${mean_sq_temp_deriv} ]
        then
            echo "=== Mean Squared Temporal Derivative already exists"
        else
            echo "=== Calculating Mean Squared Temporal Derivative"
            3dROIstats -quiet -mask ${mask_file} ${derivative_sq} \
                > ${mean_sq_temp_deriv}
            # make sure that happened
            if [ $? -ne 0 ]
            then
                echo "Error calculating MSTD for ${prefix}!"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi

        # 7. get square root of mean squared temporal derivative
        if [ -f ${subjid}_DVARS.1D ]
        then
            echo "=== DVARS file already exists"
        else
            echo "=== Making final DVARS calculation for ${subjid}"       
            cat ${mean_sq_temp_deriv} | \
                perl -e '@v=<>; foreach (@v){ $s=sqrt($_)/1000;\
                     print "$s\n"; }' > ${subjid}_DVARS.1D
            # make sure that happened
            if [ $? -ne 0 ]
            then
                echo "Error calculating square root for ${mean_sq_temp_deriv}!"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi

        # since we went through that whole process, we might as well
        # calculate FD as well
        if [ -f ${subjid}_FD.1D ]
        then 
            echo "=== FD file already exists"
        else
            echo "=== Calculating FD "
            time calc_FD.py ${motion_file} > ${subjid}_FD.1D
            # make sure that happened
            if [ $? -ne 0 ]
            then
                echo "Error calculating FD!"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi
  
        #----- Transfrom BOLD data to MNI space
        # if it does not already exist, calculate transform from 
        # coreg_base to ANAT
        epi_mni_xform=${subjid}_epi_2_MNI152_4mm
        T1_epi_xform=${subjid}_T1_2_epi.mat
        epi_T1_xform=${subjid}_epi_2_T1.mat
    
        # calculate the EPI-MNI transform
        if [ -f ${epi_mni_xform}.nii.gz -a \
             -f ${T1_epi_xform} -a \
             -f ${epi_T1_xform} -a \
             -f ${mni_mean_file} -a \
             -f ${mni_mask_file} ] 
        then
             echo "${epi_mni_xform}, ${T1_epi_xform}, and \
                   ${epi_T1_xform} already exists"
        else
          
            # if any of them are missing, we recalculate all of them
            rm -f ${epi_mni_xform} ${T1_epi_xform} ${epi_T1_xform} 
            rm -f rm_${subjid}_init.mat t1_${epi_mean_template}
            rm -f ${mni_mean_file} ${mni_mask_file}
 
            echo "=== Initial coregistration using flirt" 
            # register coreg_base to anatomical
            time flirt -ref ${ss_t1_file} -in ${epi_mean_template} -dof 6 \
                 -omat rm_${subjid}_init.mat
            if [ $? -ne 0 ]
            then
                echo "Error calculating initial flirt!"
                DBG_CONTINUE $LINENO; continue;
            fi
   
            echo "=== BBreg coregistration using flirt" 
            # perform bbreg
            time flirt -ref ${t1_file} -in ${epi_mean_template} -dof 6 \
                -cost bbr -wmseg ${bbreg_target} -init rm_${subjid}_init.mat \
                -omat ${epi_T1_xform} -out ${epi_T1_xform%%.mat} \
                -schedule ${FSLDIR}/etc/flirtsch/bbr.sch

            if [ $? -ne 0 ]
            then
                echo "Error calculating BBREG!"
                DBG_CONTINUE $LINENO; continue;
            fi
 
            # copy mean template into T1 space for debugging
            echo "=== Copy mean template to T1 space"
            time flirt -in ${epi_mean_template} -ref ${ss_t1_file} \
                -out t1_${epi_mean_template} \
                -init ${epi_T1_xform} -applyxfm 

            if [ $? -ne 0 ]
            then
                echo "Error calculating copying ${epi_mean_template} \
                      to T1 space!"
                DBG_CONTINUE $LINENO; continue;
            fi
   
            # calculate the inforse (T1->EPI) warp
            echo "=== Invert transform to get T1->EPI"
            time convert_xfm -omat ${T1_epi_xform} -inverse ${epi_T1_xform} 
            if [ $? -ne 0 ]
            then
                echo "Error inverting ${epi_T1_xform}!"
                DBG_CONTINUE $LINENO; continue;
            fi

            # combine xforms
            echo "=== Combining warps to get EPI->MNI"
            time convertwarp \
                --ref=${FSLDIR}/data/standard/MNI152_T1_4mm.nii.gz \
                --warp1=${warp_file} --premat=${epi_T1_xform} \
                --out=${epi_mni_xform} --relout 
            if [ $? -ne 0 ]
            then
                echo "Error combining warps!"
                DBG_CONTINUE $LINENO; continue;
            fi
    
            # copy mean template into MNI space for debugging
            echo "=== Writing mean image into MNI space"
            time applywarp --ref=${FSLDIR}/data/standard/MNI152_T1_4mm.nii.gz \
                --in=${epi_mean_template} --warp=${epi_mni_xform} --rel \
                --out=${mni_mean_file}
            if [ $? -ne 0 ]
            then
                echo "Error writing ${epi_mean_template} to MNI space!"
                DBG_CONTINUE $LINENO; continue;
            fi

            # Mask in MNI space for debugging
            echo "=== Creating MNI mask"
            time 3dAutomask -dilate 1 -prefix ${mni_mask_file} \
                ${mni_mean_file}
            if [ $? -ne 0 ]
            then
                echo "Error creating mask in MNI space!"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi


        # if we fractionize the CSF mask and then dilate, there is
        # nothing left in the mask, instead we do the extremely painful
        # thing of fractionating the CSF mask to 2mmm space and then 
        # copying the EPI data to 2mm just long enough to extract the CSF
        # signal

        # copy EPI to 2mm T1 space
        nvr_data=${prev_step%%.nii.gz}_T1_2mm.nii.gz
        if [ -f ${nvr_data} ]
        then
            echo "=== EPI data already in T1 space at 2mm"
        else
            echo "=== Copying EPI data to T1 space at 2mm"
            echo "_${prev_step} _${ss_t1_file} _${nvr_data} _${epi_T1_xform}"
            time flirt -in ${prev_step} -ref ${ss_t1_file} \
                 -out ${nvr_data} -init ${epi_T1_xform} -applyisoxfm 2

            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error copying ${prev_step} into T1 space at 2mm"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi

        csf_mask_frac=${csf_mask%%.nii.gz}_frac.nii.gz

        if [ -f ${csf_mask_frac} ]
        then
            echo "CSF mask already in EPI space"
        else
      
            echo "=== Fractionizng ${csf_mask} into EPI space"

            # remove some files to make sure they are out of the way
            rm -f rm_frac_${csf_mask} rm_frac_clean_${csf_mask}
  
            # fractionize CSF mask to 2mm resolution
            echo "=  Fractionize"
            time 3dresample -input ${csf_mask} -master ${nvr_data} \
                  -prefix rm_frac_${csf_mask} -overwrite -rmode NN 

            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error fractionizing ${csf_mask}}"
                DBG_CONTINUE $LINENO; continue;
            fi
    
            # threshold once again to clean up fractionization
            echo "= 3dcalc thresh frac csf file"
            time 3dcalc -a rm_frac_${csf_mask} -expr 'step(a-.5)' \
                -prefix rm_frac_clean_${csf_mask} -datum short
    
            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error cleaning fractionized rm_frac_${csf_mask}}"
                DBG_CONTINUE $LINENO; continue;
            fi

            # erode fractionated file by one voxel to minimize PVE
            echo "= 3dcalc erode frac csf file"
            time 3dcalc -a rm_frac_clean_${csf_mask} -b a+i -c a-i -d a+j \
                 -e a-j -f a+k -g a-k \
                 -expr 'a*(1-amongst(0,b,c,d,e,f,g))' \
                 -prefix ${csf_mask_frac} -datum short
    
            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error eroding fractionized rm_frac_clean_${csf_mask}}"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi


        # extract csf timecourses
        csf_tc_file=rm_csf_${prev_step##rm_}
        csf_tc_file=${csf_tc_file%%.nii.gz}.1D
        echo "=== Extracting CSF nuisance"
        3dmaskave -q -mask ${csf_mask_frac} ${prev_step%%.nii.gz}_T1_2mm.nii.gz \
            > ${csf_tc_file}
        if [ $? -ne 0 ]
        then
            echo "Error extracting CSF nuisance!"
            DBG_CONTINUE $LINENO; continue;
        fi


        # now we handle the WM file to get regressor for anaticorr
        # fractionize image to EPI space
        wm_mask_frac=${ss_t1_file%%.nii.gz}_wm_frac.nii.gz
    
        if [ -f ${wm_mask_frac} ]
        then
            echo "=== WM already fractionized"
        else

            echo "= flirt copy WM mask to EPI space"
            time flirt -in ${bbreg_target} -ref ${epi_mean_template} \
                 -out rm_frac_${wm_mask_frac} \
                 -init ${T1_epi_xform} -applyxfm 
    
            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error fractionizing rm_${wm_mask}}"
                DBG_CONTINUE $LINENO; continue;
            fi
    
            # threshold once again to clean up fractionization
            echo "= 3dcalc thresh frac wm file"
            time 3dcalc -a rm_frac_${wm_mask_frac} -expr 'step(a-.5)' \
                -prefix rm_frac_clean_${wm_mask_frac} -datum short
    
            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error cleaning fractionized rm_frac_${wm_mask_frac}}"
                DBG_CONTINUE $LINENO; continue;
            fi
    
            # erode fractionated file by one voxel to minimize PVE
            echo "= 3dcalc erode frac wm file"
            time 3dcalc -a rm_frac_clean_${wm_mask_frac} -b a+i -c a-i -d a+j \
                 -e a-j -f a+k -g a-k \
                 -expr 'a*(1-amongst(0,b,c,d,e,f,g))' \
                 -prefix ${wm_mask_frac} -datum short
    
            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error eroding fractionized rm_frac_clean_${wm_mask_frac}}"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi

        # the wm nuisance is a 3d volume
        wm_tc_file=rm_wm_${prev_step##rm_}
        if [ -f ${wm_tc_file} ] 
        then
            echo "=== WM TC file already exists"
        else
            echo "=== Extracting WM TC file"
            time 3dLocalstat -prefix ${wm_tc_file} -nbhd "SPHERE(${wm_radius})" \
                    -stat mean -mask ${mask_file} -use_nonmask ${prev_step}
            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error extracting WM TC"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi

        # detrend wm nuisance
        det_wm_tc_file=rm_det_${wm_tc_file##rm_}
        if [ -f ${det_wm_tc_file} ]
        then
            echo "=== Detrended WM TC file already exists"
        else
            echo "=== Detrending WM TC file"
            time 3dDetrend -normalize -prefix ${det_wm_tc_file} \
                   -polort A ${wm_tc_file}
            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error detrending WM TC"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi
   
        # construct ort file
        echo "=== Calculating Friston Motion Model "
        time ~/netspace/bin/make_friston_motion.pl ${motion_file} \
             > ${subjid}_friston_motion.1D

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error calculating friston motion model"
            DBG_CONTINUE $LINENO; continue;
        fi

        echo "=== Calculating Nuisance ORT file"
        1dcat ${csf_tc_file} ${subjid}_friston_motion.1D \
            > ${subjid}_nuisance_ort_file.1D 

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error concatenating nuisance"
            DBG_CONTINUE $LINENO; continue;
        fi

        echo "=== Detrending Nuisance ORT file"
        time 3dDetrend -DAFNI_1D_TRANOUT=YES -normalize \
            -prefix ${subjid}_nuisance_ort_det.1D \
            -polort A ${subjid}_nuisance_ort_file.1D\' \
            -overwrite

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error detrending nuisance"
            DBG_CONTINUE $LINENO; continue;
        fi

        if [ -f rm_n${prev_step##rm_} ]
        then
            echo "=== NVR already applied to data"
        else
            echo "=== Performing NVR - 3dTfitter"
            # perform nuisance variable regression
            time 3dTfitter -polort A \
                      -RHS ${prev_step} \
                      -LHS ${subjid}_nuisance_ort_det.1D ${det_wm_tc_file} \
                      -prefix rm_nvr_beta \
                      -fitts rm_nvr_fitts \
                      -errsum rm_nvr_errsum \
                      
            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error 3dTfitter NVR"
                DBG_CONTINUE $LINENO; continue;
            fi

            echo "=== Performing NVR - 3dcalc"
            time 3dcalc -float -a ${prev_step} -b rm_nvr_fitts+orig \
                    -expr 'a-b' -prefix rm_n${prev_step##rm_}

            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error 3dcalc NVR"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi
        prev_step=rm_n${prev_step##rm_}
    
        # make sure that the TR is correct
        3drefit -TR 2.1s ${prev_step}

        # filter the nvr data
        if [ -f rm_f${prev_step##rm_} ]
        then 
            echo "=== NVR data already filtered"
        else
            echo "=== Filtering NVR data"
            time 3dBandpass -nodetrend -mask ${mask_file} \
                    -band .009 .09 -prefix rm_f${prev_step##rm_} \
                    ${prev_step}

            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error Filtering NVR"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi

        # smooth the nvr non-filtered data in original space
        if [ -f ${nvr_bold} ]
        then
            echo "=== NVR data already smoothed in orig space"
        else
            echo "=== Smoothing NVR data in orig space"
            time 3dmerge -1blur_fwhm 6 -doall -prefix ${nvr_bold} \
                ${prev_step}

            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error smoothing data in orig space"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi

        # smooth the nvr filtered data in original space
        if [ -f ${filtered_nvr_bold} ]
        then
            echo "=== Filtered NVR data already smoothed in orig space"
        else
            echo "=== Smoothing filtered NVR data in orig space"
            time 3dmerge -1blur_fwhm 6 -doall -prefix ${filtered_nvr_bold} \
                rm_f${prev_step##rm_}

            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error smoothing filtered data in orig space"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi
            
        # write unfiltered NVR data into MNI space
        if [ -f rm_w${prev_step##rm_} ]
        then
            echo "=== Data already in MNI space"
        else
            echo "=== writing data into MNI space"
            time applywarp --ref=${FSLDIR}/data/standard/MNI152_T1_4mm.nii.gz \
                --in=${prev_step} --warp=${epi_mni_xform} --rel \
                --out=rm_w${prev_step##rm_}

            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error writing data into mni space"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi
    
        if [ -f ${mni_nvr_bold} ]
        then
            echo "=== Smoothed data in MNI space already exists"
        else
            echo "=== Smoothing data in MNI space"
            time 3dmerge -1blur_fwhm 6 -doall -prefix ${mni_nvr_bold} \
                rm_w${prev_step##rm_}
            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error smoothing NVR data in  mni space"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi

        # write filtered NVR data into MNI space
        if [ -f rm_wf${prev_step##rm_} ]
        then
            echo "=== Filtered NVR Data already in MNI space"
        else
            echo "=== Writing filtred nvr data into MNI space"
            time applywarp --ref=${FSLDIR}/data/standard/MNI152_T1_4mm.nii.gz \
                --in=rm_f${prev_step##rm_} --warp=${epi_mni_xform} --rel \
                --out=rm_wf${prev_step##rm_}

            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error writing filtered nvr data into mni space"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi
    
        if [ -f ${mni_filtered_nvr_bold} ]
        then
            echo "=== Smoothed filtered NVR data in MNI space already exists"
        else
            echo "=== Smoothing filtered NVR data in MNI space"
            time 3dmerge -1blur_fwhm 6 -doall -prefix ${mni_filtered_nvr_bold} \
                rm_wf${prev_step##rm_}
            # make sure that happened
            if [ "$?" -ne "0" ]
            then
                echo "Error smoothing filtered NVR data in  mni space"
                DBG_CONTINUE $LINENO; continue;
            fi
        fi
    fi # test for the different outputs

    ##### now calculate all of the features of interest, including
    #  1. DR FC for PNAS templates
    #  2. fALFF
    #  3. ReHo

    # 1. DR FC for PNAS templates
    if [ -f ${mni_nvr_bold%%.nii.gz}_PNAS_TCs.1D ]
    then
        echo "=== PNAS TCs already extracted"
    else 
        echo "=== Extracting PNAS TCs"
        time fsl_glm -i ${mni_nvr_bold} -d ${PNAS_TEMPLATES} \
                -o ${mni_nvr_bold%%.nii.gz}_PNAS_TCs.1D \
                --demean -m ${mni_mask_file}

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error extracting PNAS time courses"
            DBG_CONTINUE $LINENO; continue;
        fi
    fi

    if [ -f ${mni_nvr_bold%%.nii.gz}_PNAS_FC.nii.gz ]
    then
        echo "=== PNAS FC maps already extracted"
    else 
        echo "=== Extracting PNAS FC maps"
        time fsl_glm -i ${mni_nvr_bold} \
                -d ${mni_nvr_bold%%.nii.gz}_PNAS_TCs.1D \
                -o ${mni_nvr_bold%%.nii.gz}_PNAS_FC \
                --demean \
                --out_z=${mni_nvr_bold%%.nii.gz}_PNAS_FC_z \
                --des_norm -m ${mni_mask_file}
                

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error calculating PNAS FC maps"
            DBG_CONTINUE $LINENO; continue;
        fi
    fi


    # 2. Caculate fALFF
    if [ -f falff_${bold_file} ]
    then
        echo "=== Already computed fALFF";
    else
        echo "=== Calculating FALFF"
        
        echo "= Calc numerator"
        time 3dTstat -stdev -mask ${mni_mask_file} \
                -prefix rm_falff_num_${bold_file} \
                ${mni_filtered_nvr_bold}

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error calculating fALFF numerator"
            DBG_CONTINUE $LINENO; continue;
        fi

        echo "= Calc denominator"
        time 3dTstat -stdev -mask ${mni_mask_file} \
                -prefix rm_falff_denom_${bold_file} \
                ${mni_nvr_bold}

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error calculating fALFF denominator"
            DBG_CONTINUE $LINENO; continue;
        fi

        echo "= Calc fALFF"
        time 3dcalc -prefix falff_${bold_file} -a ${mni_mask_file} \
               -b rm_falff_num_${bold_file} \
               -c rm_falff_denom_${bold_file} -expr 'bool(a)*b/c'

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error calculating fALFF denominator"
            DBG_CONTINUE $LINENO; continue;
        fi
    fi

    # 3. Calculate REHO
    if [ -f reho_${bold_file} ]
    then
        echo "=== Already Computed REHO ==="
    else
        echo "=== Calculating REHO ==="
        
        echo "= Computing ranks"
        time 3dTsort -prefix rm_ranks_${mni_filtered_nvr_bold} \
               -rank ${mni_filtered_nvr_bold}

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error calculating ranks"
            DBG_CONTINUE $LINENO; continue;
        fi

        echo "= Computing mean ranks"
        time fslmaths rm_ranks_${mni_filtered_nvr_bold} -kernel 3D \
               -fmean rm_mean_ranks_${mni_filtered_nvr_bold}

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error calculating mean ranks"
            DBG_CONTINUE $LINENO; continue;
        fi

        echo "= Computing constants"
        nt=`fslnvols ${mni_filtered_nvr_bold}`;
        echo -n "There are ${nt} volumes ..."
        n1_const=$(echo "scale=20; ${nt}*${nt}*${nt}-${nt}"|bc); 
        echo -n " ${n1_const}..."
        n2_const=$(echo "scale=20; 3*(${nt}+1)/(${nt}-1)"|bc); 
        echo  " ${n2_const}"

        echo "= Computing KCC"
        time fslmaths rm_mean_ranks_${mni_filtered_nvr_bold} -sqr \
              -Tmean -mul ${nt} -mul 12 -div ${n1_const} -sub ${n2_const} \
              -mas ${mni_mask_file} reho_${bold_file}

        # make sure that happened
        if [ "$?" -ne "0" ]
        then
            echo "Error calculating KCC"
            DBG_CONTINUE $LINENO; continue;
        fi
    fi

# for loop
done

# delete intermediate files
