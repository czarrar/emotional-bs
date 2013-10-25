#!/usr/bin/env bash

njobs=5

cd /home/data/Projects/Emotional-BS/share/01_preprocessing

# Preprocess Functional
# cat ../subject_list.txt | parallel -j $njobs --eta './01_preprocess_func.rb -n movie -r 1 2 3 -s {}'

# Register Functional
# cat ../subject_list.txt | parallel -j $njobs --eta './03_register_func.rb -n movie -r 1 2 3 -s {}'

# Regress Nuisance
cat ../subject_list.txt | parallel -j $njobs --eta './04_nuisance_func.rb -n movie -r 1 2 3 -s {}'

# Apply Registration
cat ../subject_list.txt | parallel -j $njobs --eta './05_applyreg_func.rb -n movie -r 1 2 3 -s {}'
