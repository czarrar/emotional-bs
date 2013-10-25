#!/usr/bin/env bash

njobs=5

cd /home/data/Projects/Emotional-BS/share/01_preprocessing

# Preprocess Anatomical
cat ../subject_list.txt | parallel -j $njobs --eta './01_preprocess_anat.rb -r 1 2 -s {}'

# Segment Anatomical
cat ../subject_list.txt | parallel -j $njobs --eta './02_segment_anat.rb -s {}'

# Register Anatomical
cat ../subject_list.txt | parallel -j $njobs --eta './02_register_anat.rb -s {}'
