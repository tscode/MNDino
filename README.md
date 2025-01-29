
# MNDino

This repository contains a julia package called MNDino. MNDino aspires to become a modular toolkit for building graphical user interfaces (GUIs) that facilitate image segmentation and analysis.

As a library, MNDino aims to provide a number of general purpose widgets that can conveniently be combined to fit a range of different workflows. For now,  the development focus will be a specific GUI layout that targets multi-channel microscopy images.

## Installation
The package is not yet officially registered. Use the following commands within a julia shell to install the latest stable version of the package.
```julia
using Pkg
Pkg.add(url="https://gitlab.gwdg.de/staudt1/mndino.git")
```
A julia version of 1.9 or higher is strongly recommended. You can get julia from [here](https://julialang.org/downloads/).

## Running and Updating
At the moment (version 0.2), only one GUI layout is included in MNDino.
This layout can be accessed via
```julia
using MNDino
MNDino.main()
```
A window will ask for image files (e.g., *.ims*) or an MNDino project file (*.dino*).
Ideally, you start a julia environment with at least two threads (i.e., run `julia -t2`).

If you have problems due to compability errors, it might help to use the same package environment that is used to develop MNDino.
You can achieve this via
```julia
using Pkg
Pkg.activate("MNDino")
Pkg.instantiate()

using MNDino
MNDino.main()
```

In order to update your current MNDino installation, run
```julia
using Pkg
Pkg.update("MNDino")
```

## Usage
After picking some files and configuring the channel order, you will be greeted by a user interface with several widgets.
The following hints might help navigate the interaction options.
They apply to version v0.2 and are subject to future change.

#### Generic navigation
* The *left* / *right* keyboard arrow keys can be used to switch images.
* The *up* / *down* keyboard arrow keys can be used to change the Z-index.
* *Double clicking* the *left mouse button* restores the zoom level in the channel view.
* *Double clicking* the *right mouse button* clears the segment of the channel the mouse hovers over.

#### Pencil tool
* In the channel view, pressing *shift* temporarily enables the **pencil tool**. With the pencil tool, you can draw masks that describe the geometry of regions you are interested in.
* Left-clicking adds to the mask, while right-clicking removes from the mask.
* Scrolling while the pencil tool is enabled changes the pencil radius.

#### Segmentation tool
* In the channel view, pressing *ctrl* temporarily enables the **segmentation tool**.
* When this tool is activated, drag-and-dropping from a start point A to an end point B will create an automatic segmentation that seperates A from B. 
* The region corresponding to the A-segment will be added to the current mask.
* Typically, A will therefore be placed on a feature while B will be placed on the background you want to seperate the feature from.
* Scrolling while in the segmentation tool will grow or shrink the masks in the image under the mouse cursor. 

#### Variables
* Different widgets can load different quantities in a variable store that operates in the background.
* For example, the channel view widget registers variables `:C1`, `:C2`, ... These variables can be accessed by analysis scripts (see below).
* Similarly, the segment widget registers masks `:S1`, `:S2`, ...

#### Analyzing and scripts
* In order to quantitatively analyze your images, you can load scripts into MNDino. 
* A script is a julia file that defines a set of *input variables*, a set of *output variables*, and an *evaluation function*. The input variables have to be made accessible by other widgets.

The following is a simple example:
```julia
# We request access to the channel data C1, C2 and the segment S1.
inputs = (:C1, :C2, :S1)

# We declare the following outputs from our script.
outputs = (
  :meanC1,
  :meanC1S1,
  :meanC2S1,
)

# Here, we implement the actual computations that generate our outputs
function evaluate(data)
  c1 = data[:C1]
  c2 = data[:C2]
  s1 = data[:S1]

  return (
    :meanC1 => mean(c1),
    :meanC1S1 => mean(c1[s1]),
    :meanC2S1 => sum(c1[s1] .* c2[s1]) / sum(c1[s1]),
  )
end
```

## Limitations
Currently, images in the [Imaris file format](https://imaris.oxinst.com/support/imaris-file-format) and the [OME-TIFF format](https://docs.openmicroscopy.org/ome-model/5.6.3/ome-tiff/) are supported.
Such images are typically produced by (fluorescent) microscopes.
Feel free to submit an issue if you have issues with these file types or would like to see support for other formats.

## Acknowledgements
MNDino is powered by the plotting library [GLMakie](https://docs.makie.org/stable/).
The development also profits greatly from the image analysis tools in [Images](https://github.com/JuliaImages/Images.jl).

