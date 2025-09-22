

"""
   consumemouse(scene, area; priority = 60, button = true, position = false) 

Consume all mouse button or position events of `scene` in the rectangle `area`
below a given `priority`.
"""
function consumemouse(
  scene,
  area;
  priority = 60,
  button = true,
  position = false,
)
  area = area isa Observable ? area : Observable(area)
  events = scene.events
  obsfs = []
  if button
    f = on(events.mousebutton; priority) do event
      mouseposition(scene) in area[] ? Consume(true) : Consume(false)
    end
    push!(obsfs, f)
  end
  if position
    f = on(events.mouseposition; priority) do event
      mouseposition(scene) in area[] ? Consume(true) : Consume(false)
    end
    push!(obsfs, f)
  end

  return obsfs
end
