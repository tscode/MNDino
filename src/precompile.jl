

@setup_workload begin
  # generate image file
  path = tempname() * ".png"
  data = [RGBf(0., 0., 0.) for _ in 1:10, _ in 1:10]
  FileIO.save(path, data)

  @compile_workload begin
    project = newproject(paths = [path, path])
    ctx = runproject(project, display = false)

    # Change image
    notify(ctx[:providers][:images][:select_next])
    notify(ctx[:providers][:images][:select_prev])
    notify(ctx[:update])

    # Packing and unpacking
    bytes = StructPack.pack(project)
    # TODO: This does currently not work since Main.MNDino is needed by Pack
    # but is not defined at this point
    # Pack.unpack(bytes, Project)
  end

  rm(path)
end

# Image Operations
@compile_workload begin
  mat = rand(Float32, 10, 10)
  for filter in [GaussFilter(3), MedianFilter(3), LaplaceFilter()]
    filter(mat)
  end
  ImageSegmentation.seeded_region_growing(
    mat,
    [CartesianIndex(1, 1) => 1, CartesianIndex(5, 5) => 2],
  )
  mask = Matrix{Bool}(undef, 10, 10)
  ImageMorphology.erode!(mask; r = 1)
  ImageMorphology.dilate!(mask; r = 1)
  ImageTransformations.imresize(mask, (20, 20))
end
