
#
# Copied and adapted from Makie.jl
#

struct DragPan
    reset_timer::Makie.RefValue{Union{Nothing, Timer}}
    prev_xticklabelspace::Makie.RefValue{Union{Makie.Automatic, Float64}}
    prev_yticklabelspace::Makie.RefValue{Union{Makie.Automatic, Float64}}
    reset_delay::Float32
end

function DragPan(reset_delay)
    return DragPan(Makie.RefValue{Union{Nothing, Timer}}(nothing), Makie.RefValue{Union{Makie.Automatic, Float64}}(0.0), Makie.RefValue{Union{Makie.Automatic, Float64}}(0.0), reset_delay)
end

function Makie.process_interaction(dp::DragPan, event::MouseEvent, ax)
    if event.type !== MouseEventTypes.leftdrag
        return Consume(false)
    end

    tlimits = ax.targetlimits
    xpanlock = ax.xpanlock
    ypanlock = ax.ypanlock
    xpankey = ax.xpankey
    ypankey = ax.ypankey

    scene = ax.scene
    cam = Makie.camera(scene)
    pa = Makie.viewport(scene)[]

    mp_axscene = Vec4f((event.px .- pa.origin)..., 0, 1)
    mp_axscene_prev = Vec4f((event.prev_px .- pa.origin)..., 0, 1)

    mp_axfraction, mp_axfraction_prev = map((mp_axscene, mp_axscene_prev)) do mp
        # first to normal -1..1 space
        (cam.pixel_space[] * mp)[Vec(1, 2)] .*
        # now to 1..-1 if an axis is reversed to correct zoom point
        (-2 .* ((ax.xreversed[], ax.yreversed[])) .+ 1) .*
        # now to 0..1
        0.5 .+ 0.5
    end

    xscale = ax.xscale[]
    yscale = ax.yscale[]

    transf = (xscale, yscale)
    tlimits_trans = Makie.apply_transform(transf, tlimits[])

    movement_frac = mp_axfraction .- mp_axfraction_prev

    xscale = ax.xscale[]
    yscale = ax.yscale[]

    transf = (xscale, yscale)
    tlimits_trans = Makie.apply_transform(transf, tlimits[])

    xori, yori = tlimits_trans.origin .- movement_frac .* Makie.widths(tlimits_trans)

    if xpanlock[] || Makie.ispressed(scene, ypankey[])
        xori = tlimits_trans.origin[1]
    end

    if ypanlock[] || Makie.ispressed(scene, xpankey[])
        yori = tlimits_trans.origin[2]
    end

    Makie.timed_ticklabelspace_reset(ax, dp.reset_timer, dp.prev_xticklabelspace, dp.prev_yticklabelspace, dp.reset_delay)

    inv_transf = Makie.inverse_transform(transf)
    newrect_trans = Makie.Rectd(Vec2(xori, yori), Makie.widths(tlimits_trans))
    tlimits[] = Makie.apply_transform(inv_transf, newrect_trans)

    return Consume(true)
end


