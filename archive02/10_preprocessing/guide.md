The data will be preprocessed with CPAC. We will want to have a data-config file as well as a config file. These can be generated via the GUI.

# First

First, we setup the `data_config.yaml` file. One issue is that some of the paths might have too many files associated with them? Not sure.

As part of this step, I need to make a slice paramters file. Note that the parameters for all functional files is a TR of 2.01, a reference slice of 15 (total of 30 slices), and an acquisition in afni lingo of alt+z2.


# Second

Second, I need to extract the subject list from this file so I create a short script `10_setup.py`

# Third

I am now generating the config file with setting on pre-processing and post-processing.

I'm wondering about the strategies that should be run right now? For now I have:

1. compcor+motion+linear+quadratic
2. compcor+global+motion+linear+quadratic

-  compcor :  1
   wm :  0
   csf :  0
   global :  0
   pc1 :  0
   motion :  1
   linear :  1
   quadratic :  1
   gm :  0
-  compcor :  1
   wm :  0
   csf :  0
   global :  1
   pc1 :  0
   motion :  1
   linear :  1
   quadratic :  1
   gm :  0

Should I be doing some ROI extraction? Maybe copying over the ROIs from: `/home2/data/Projects/ABIDE_Initiative/CPAC/abide/tse/ROI_list_timeseriesExtraction.txt` to the Emotional-BS directory. Same thing goes for spatial regression, copy files? `/home2/data/Projects/ABIDE_Initiative/CPAC/abide/tse/spatial_maps_list_DualRegression.txt`.

VMHC has been turned on but right now it won't really run.

Centrality is turned off because the group mask needs to be generated.

What smoothing should be used?

