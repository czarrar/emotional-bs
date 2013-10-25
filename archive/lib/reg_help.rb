require 'colorize'
require 'pathname'
require 'tmpdir'
require 'for_commands.rb'

def create_reg_pics(in_file, ref_file, out_file)
  
  return if any_inputs_dont_exist_including in_file, ref_file  
  
  in_file   = Pathname(in_file).realpath
  ref_file  = Pathname(ref_file).realpath
  out_file  = out_file
  
  Dir.mktmpdir do |tmpdir|
    puts "=== Running commands in #{tmpdir}".magenta
    
    Dir.chdir(tmpdir) do
      run "slicer #{in_file} #{ref_file} -s 2 -x 0.35 sla.png -x 0.45 slb.png -x 0.55 slc.png -x 0.65 sld.png -y 0.35 sle.png -y 0.45 slf.png -y 0.55 slg.png -y 0.65 slh.png -z 0.35 sli.png -z 0.45 slj.png -z 0.55 slk.png -z 0.65 sll.png"
      run "pngappend sla.png + slb.png + slc.png + sld.png + sle.png + slf.png + slg.png + slh.png + sli.png + slj.png + slk.png + sll.png pic1.png"
      
      run "slicer #{ref_file} #{in_file} -s 2 -x 0.35 sla.png -x 0.45 slb.png -x 0.55 slc.png -x 0.65 sld.png -y 0.35 sle.png -y 0.45 slf.png -y 0.55 slg.png -y 0.65 slh.png -z 0.35 sli.png -z 0.45 slj.png -z 0.55 slk.png -z 0.65 sll.png"
      run "pngappend sla.png + slb.png + slc.png + sld.png + sle.png + slf.png + slg.png + slh.png + sli.png + slj.png + slk.png + sll.png pic2.png"
      
      run "pngappend pic1.png - pic2.png #{out_file}"
    end
    
  end
    
end
