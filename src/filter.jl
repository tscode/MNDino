
abstract type Filter end

@pack {<: Filter} in TypedFormat{StructFormat}

struct GaussFilter <: Filter
  radius::Int
end

function (filter::GaussFilter)(mat)
  kernel = ImageFiltering.Kernel.gaussian(filter.radius)
  return ImageFiltering.imfilter(mat, kernel)
end

struct MedianFilter <: Filter
  radius::Int
end

struct LaplaceFilter <: Filter end

function (filter::LaplaceFilter)(mat)
  kernel = ImageFiltering.Kernel.Laplacian()
  return ImageFiltering.imfilter(mat, kernel)
end

function (filter::MedianFilter)(mat)
  d = 2filter.radius + 1
  return ImageFiltering.mapwindow(median!, mat, (d, d))
end

struct NoFilter <: Filter end
(::NoFilter)(mat) = mat
