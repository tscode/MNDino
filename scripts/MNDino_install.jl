
using Pkg

try
  Pkg.update("MNDino")
catch _
  Pkg.add("https://gitlab.gwdg.de/staudt1/mndino.git")
end
