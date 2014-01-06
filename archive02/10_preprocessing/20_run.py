#!/usr/bin/env python

import CPAC
config_file         = "20_run/run_config.yaml"
subject_list_file   = "20_run/CPAC_subject_list.yml"
CPAC.pipeline.cpac_runner.run(config_file, subject_list_file)
