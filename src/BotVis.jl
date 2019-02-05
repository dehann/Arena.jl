#FIXME move graff functions to under requires
using GraffSDK

abstract type AbsractVarsVis end

abstract type AbstractPointPose end

#NOTE names should match soft type names Pose2 and Point2 but may cause conflict with Caesar
mutable struct Pose2{T<:AbstractFloat} <: AbstractPointPose
	x::T
	y::T
	θ::T
end

function visPose!(vis::Visualizer,
				  tform::CoordinateTransformations.Transformation,
				  updateonly::Bool=false;
				  scale::Float64=0.2)
	if !updateonly
		setobject!(vis, Triad(scale))
	end
	settransform!(vis, tform)
	nothing
end


mutable struct Point2{T<:AbstractFloat} <: AbstractPointPose
	x::T
	y::T
end

function visPoint!(vis::Visualizer,
				   tform::CoordinateTransformations.Transformation,
				   updateonly::Bool=false;
				   scale::Float64=0.1,
				   color=RGBA(0., 1, 0, 0.5))

	if !updateonly
		sphere = HyperSphere(Point(0., 0, 0), scale)
        matcolor = MeshPhongMaterial(color=color)
        setobject!(vis, sphere, matcolor)
	end
	settransform!(vis, tform)
	nothing
end

function visNode!(vis::Visualizer,
	              pose::Pose2,
				  updateonly::Bool=false;
	              scale::Float64=0.2, #TODO move keyword params to params dict or named tuple?
	              zoffset::Float64=0.0)::Nothing

	tf = drawtransform ∘ Translation(pose.x, pose.y, zoffset) ∘ LinearMap(CTs.RotZ(pose.θ))
	visPose!(vis, tf, updateonly, scale=scale)
end

function visNode!(vis::Visualizer,
            	  point::Point2,
				  updateonly::Bool=false;
                  scale::Float64=0.1,
                  zoffset::Float64=0.0)::Nothing

	tf = drawtransform ∘ Translation(point.x, point.y, zoffset)
	visPoint!(vis, tf, updateonly, scale=scale)

end



struct BasicFactorGraphPose <: AbsractVarsVis
	robotId::String
	sessionId::String
	fg::FactorGraph
	nodes::Dict{Symbol, AbstractPointPose} #poseId, Softtype
	meanmax::Symbol
	poseScale::Float64
	zoffset::Float64
	pointScale::Float64
end
#
# BasicFactorGraphPose(robotId::String, sessionId::String) =
# 	BasicFactorGraphPose(robotId,sessionId, Dict{Symbol,AbstractPointPose}(),
# 					:max, 0.2, 0.0, 0.1)

BasicFactorGraphPose(robotId::String, sessionId::String, fg::FactorGraph) =
	BasicFactorGraphPose(robotId,sessionId, fg, Dict{Symbol,AbstractPointPose}(),
					:max, 0.2, 0.0, 0.1)


function visualize!(vis::Visualizer, bfg::BasicFactorGraphPose)::Nothing
	#TODO maybe improve this function to lower memmory allocations


	# get the local factor graph object
	# TODO add getlocalfg function or local fg object to the struct
	# tested defined in main
	# fgl = Main.getlocalfg(bfg.sessionId)
	fgl = bfg.fg

	robotId = bfg.robotId
	sessionId = bfg.sessionId


	# get all variables
    xx, ll = IIF.ls(fgl)
    vars = union(xx, ll)

    # update the variable point-estimate cache
    for vsym in vars

        # get vertex and estimate from the factor graph object
        vert = getVert(fgl, vsym)
        X = getKDE(vert)

        xmx = bfg.meanmax == :max ? getKDEMax(X) : getKDEMean(X)

        # get the variable type
        typesym = Caesar.getData(vert).softtype |> typeof |> Symbol

		nodef = getfield(Arena, typesym)

		#NOTE make sure storage order and softtypes are always the same
		@show nodestruct = nodef(xmx...)

		# TODO Can we alwyas assume labels are correct? If so, this will work nicely
		# nodelabels = Caesar.getData(vert).softtype.labels
		# if length(nodelabels) > 0
		# 	groupsym = Symbol(nodelabels[1])
		# else
		# 	groupsym = :group
		# end

		if string(vsym)[1] == 'l'
			groupsym = :landmarks
		elseif string(vsym)[1] == 'x'
			groupsym = :poses
		else
			@warn "Unknown symbol encountered $vsym"
			groupsym = :unknown
		end

		isnewnode = !haskey(bfg.nodes, vsym)
		if isnewnode
			push!(bfg.nodes, vsym=>nodestruct)
		else
			bfg.nodes[vsym] = nodestruct
		end

		visNode!(vis[robotId][sessionId][groupsym][vsym], nodestruct, isnewnode)

    end

    return nothing
end

struct BasicGraffPose <: AbsractVarsVis
	robotId::String
	sessionId::String
	config::GraffConfig
	nodes::Dict{Symbol, AbstractPointPose} #poseId, Softtype
	meanmax::Symbol
	poseScale::Float64
	zoffset::Float64
	pointScale::Float64
end

BasicGraffPose(config::GraffConfig) =
	BasicGraffPose(config.robotId, config.sessionId, config, Dict{Symbol,AbstractPointPose}(),
				   :max, 0.2, 0.0, 0.1)



function visualize(visdatasets::Vector{AbsractVarsVis};
                   show::Bool=true)::Nothing
    #
    global loopvis
    global drawtransform

    loopvis = true

    # the visualizer object itself
    vis = startDefaultVisualization(show=show)

    # run the visualization loop
    while loopvis
        # iterate through all datasets #vir wat staan rose_fgl?
		for rose_fgl in visdatasets
        	# each dataset should provide an visualize function
			visualize!(vis, rose_fgl)
		end
        # take a break and repeat
        sleep(1)
    end

    @info "visualize is finalizing."
    nothing
end



"""
    $(SIGNATURES)
Initialize empty visualizer
"""
function initVis(;showLocal::Bool = true)
    vis = Visualizer()
    showLocal && open(vis)
    return vis
end



"""
    $(SIGNATURES)
Initialize empty visualizer
"""
function initBotVis2(;showLocal::Bool = true)::BotVis2
    vis = Visualizer()
    showLocal && open(vis)
    return BotVis2(vis,
                   # Dict{Symbol, NTuple{3,Float64}}(),
                   # Dict{Symbol, NTuple{3,Float64}}(),
                   Dict{Symbol, Tuple{Symbol, Vector{Bool}, Vector{Float64}}}() )
end


"""
    $(SIGNATURES)
Draw all poses in an 2d factor graph, use meanmax = :max or :mean for distribution max or mean, respectively.
"""
function drawPoses2!(botvis::BotVis2,
                     fgl::FactorGraph;
                     meanmax::Symbol=:max,
                     triadLength=0.25,
                     sessionId::String="Session" )::Nothing
    #
    xx, ll = Caesar.ls(fgl)

    for x in xx
        X = getKDE(fgl, x)
        xmx = meanmax == :max ? getKDEMax(X) : getKDEMean(X)
        trans = Translation(xmx[1:2]..., 0.0) ∘ LinearMap(RotZ(xmx[3]))
        if !haskey(botvis.cachevars, x)
            triad = Triad(triadLength)
            setobject!(botvis.vis[Symbol(sessionId)][:poses][x], triad)
            botvis.cachevars[x] = (:Pose2, [true;], xmx)
        else
            botvis.cachevars[x][3][:] = xmx
        end
        settransform!(botvis.vis[Symbol(sessionId)][:poses][x], drawtransform ∘ trans)
    end
	return nothing
end

"""
    $(SIGNATURES)
Draw all landmarks in an 2d factor graph, use meanmax = :max or :mean for distribution max or mean, respectively.
"""
function drawLandmarks2!(botvis::BotVis2,
                         fgl::FactorGraph;
                         meanmax::Symbol=:max,
                         sessionId::String="Session"  )::Nothing
    #
    xx, ll = Caesar.ls(fgl)

    for x in ll
        X = getKDE(fgl, x)
        xmx = meanmax == :max ? getKDEMax(X) : getKDEMean(X)
        trans = Translation(xmx[1:2]..., 0.0)
        if !haskey(botvis.cachevars, x)
            setobject!(botvis.vis[Symbol(sessionId)][:landmarks][x], lmpoint, greenMat)
            botvis.cachevars[x] = (:Point2, [true;], [xmx[1]; xmx[2]; 0.0 ] )
        else
            botvis.cachevars[x][3][1:2] = xmx[1:2]
        end
        settransform!(botvis.vis[Symbol(sessionId)][:landmarks][x], drawtransform ∘ trans)
    end
	return nothing
end





#
