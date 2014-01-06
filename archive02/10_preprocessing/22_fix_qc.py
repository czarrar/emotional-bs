#!/usr/bin/env python

import sys
sys.path.insert(0, '/home2/data/Projects/CPAC_Regression_Test/nipype-installs/fcp-indi-nipype/running-install/lib/python2.7/site-packages')
sys.path.insert(1, "/home/milham/Downloads/cpac_master")

import CPAC
CPAC.utils.create_all_qc.run('/home2/data/Projects/Emotional-BS/processed_data')
