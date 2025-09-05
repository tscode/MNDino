
function export_analysis(project::Project, output::String; script = nothing)
  if isnothing(script)
    path = project.providers[:analysis].script_path
    if isempty(path)
      @info """
      The given project has no associated script. \
      Please select a valid script file.
      """
      path = NativeFileDialog.pick_file()
      isempty(path) && error("No script file has been selected")
    end
    script = DinoScript(path)
  end
  names, data = runscript(
    script,
    project;
    image_store = :images,
    variable_store = :variables,
    variables = [:zindex],
  )
  open(output, "w") do io
    @info "Writing results to $output"
    println(io, join(names, ","))
    return writedlm(io, data, ',')
  end
end

function export_analysis(; script = nothing)
  @info "Select the project file to be analysed..."
  path = NativeFileDialog.pick_file(; filterlist = "dino;*")
  @info "Select analysis export file..."
  output = NativeFileDialog.save_file(; filterlist = "csv")
  if isnothing(path)
    @info "No file selected."
  else
    project = loadproject(path)
    export_analysis(project, output; script)
  end
end

