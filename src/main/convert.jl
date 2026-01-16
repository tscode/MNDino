
"""
Helper to convert image files to ome-tiff
"""
function convert_images()
  println("mndino> Hello!")
  println("mndino> My mission is to guide you to convert microscopy files to the OME-TIFF format.")
  println("mndino> For this purpose, you have to download and unzip the bioformat tools.")
  println("mndino> You can find them here:")
  println()
  println("    https://downloads.openmicroscopy.org/bio-formats/8.3.0/artifacts/bftools.zip")
  println()
  sleep(1)
  println("mndino> Now, pick the folder that you have just created.")
  println("mndino> It must contain the converter bfconvert.")
  sleep(1)

  bftools_path = NativeFileDialog.pick_folder()
  if Sys.iswindows()
    converter_path = joinpath(bftools_path, "bfconvert.bat")
  else
    converter_path = joinpath(bftools_path, "bfconvert")
  end

  if !isfile(converter_path)
    println("mndino> Sorry, I could not find the bfconvert tool in the folder $bftools_path...")
    return
  end
  
  println("mndino> Well done! I found the bfconvert tool at $bftools_path.\n")
  println("mndino> Next, pick the image files you want to convert to OME-TIFF.")
  println("mndino> For the output, I will change the file extension to .ome.tiff.")
  println("mndino> And don't worry: Your original files will be left untouched :)")
  sleep(1)

  source_files = NativeFileDialog.pick_multi_file()

  if isempty(source_files)
    println("mndino> Hmmm, you have not selected any files? Bye-bye!")
    return
  end

  println("mndino> Woohoo! Found $(length(source_files)) source files.")
  println("mndino> Trying to convert them...")
  sleep(1)
  
  for source in source_files
    convert_to_ometiff(converter_path, source)
  end
  println("mndino> Hope I could be of help! Bye-bye!")
end

function convert_to_ometiff(bfconvert, source)
  path, ext = splitext(source)
  target = path * ".ome.tiff"
  print("mndino> Converting $source -> $target... ")
  if isfile(target)
    println("ah, the target file already exists. Remove or rename it!")
  else
    cmd = `$bfconvert $source $target`
    try
      process = run(cmd, wait = false)
      success(process)
    catch err
      println("\nmndino> Sorry, something went wrong: $err")
      return
    end
    println("done!")
  end
end
