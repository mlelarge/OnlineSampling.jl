function realize!(gm::GraphicalModel, node::Marginalized, val::AbstractArray)
    # Does renew node
    @chain node begin
        @aside @assert is_terminal(gm, _)

        @aside rm_marginalized_child!(gm, _)

        Realized(_, val)

        detach!(gm, _)
        condition!(gm, _)

        @aside update!(gm, _)
    end
end

function detach!(gm::GraphicalModel, node::Realized)
    # Does enew node
    for child_id in node.children
        # Transform of child
        @chain gm.nodes[child_id] begin
            marginalize!(gm, _)
            # Remove edge node -> child
            @set _.parent_id = nothing
            @set _.parent_child_ref = nothing
            update!(gm, _)
        end
    end
    # Remove all children (in O(1))
    empty!(node.children)
    return node
end

function condition!(gm::GraphicalModel, node::Realized)
    # Does renew node
    if !has_parent(gm, node)
        return node
    end

    # Transform of parent
    @chain get_parent(gm, node) begin
        # Marginalize parent
        primitive_marginalize_parent(node, _)
        @aside add_marginalized_child!(gm, _)
        # Delete edge parent -> node 
        @aside deleteat!(_.children, node.parent_child_ref)
        update!(gm, _)
    end

    # Delete edge parent -> node
    @chain node begin
        @set _.parent_id = nothing
        @set _.parent_child_ref = nothing
    end
end

function marginalize!(gm::GraphicalModel, node::Initialized)
    # Does renew node
    @assert has_parent(gm, node)

    parent = get_parent(gm, node)
    @assert parent isa Marginalized || parent isa Realized

    @chain node begin
        primitive_marginalize_child(_, parent)
        # WARNING parent not valied anymore after next line
        @aside add_marginalized_child!(gm, _)
        # Should not be needed
        # update!(gm, _)
    end
end

function sample!(gm::GraphicalModel, node::Marginalized)
    # Does renew node
    @assert is_terminal(gm, node)
    val = rand(node.d)
    return realize!(gm, node, val), val
end

function value!(gm::GraphicalModel, node::Realized)
    # Does renew node
    return node, node.val
end

function value!(gm::GraphicalModel, node::AbstractNode)
    # Does renew node
    @chain node begin
        dist!(gm, _)
        sample!(gm, _)
        @aside update!(gm, _[1])
    end
end

function dist!(gm::GraphicalModel, node::Initialized)
    # Does renew node
    @assert has_parent(gm, node)
    parent = get_parent(gm, node)
    _ = dist!(gm, parent)

    @chain node begin
        marginalize!(gm, _)
        @aside @assert is_terminal(gm, _)
        @aside update!(gm, _)
    end
end

function dist!(gm::GraphicalModel, node::Marginalized)
    # Does renew node
    @chain node begin
        retract!(gm, _)
        @aside @assert is_terminal(gm, _)
    end
end

function retract!(gm::GraphicalModel, node::Marginalized)
    # Does not renew node
    if isnothing(node.marginalized_child)
        return node
    end

    child = gm.nodes[node.marginalized_child]
    _, _ = value!(gm, child)
    return node
end

function observe!(gm::GraphicalModel, node::AbstractNode, value::AbstractArray)
    # Unused for now
    # ll = logpdf(node.d, value)
    # update_loglikelihood!(gm, ll)
    @chain node begin
        dist!(gm, _)
        realize!(gm, _, value) 
    end
end

# Exposed interface
function initialize!(gm::GraphicalModel{I}, d::Distribution) where {I}
    new_gm, id = new_id(gm)
    node = Marginalized(id, d)
    set!(new_gm, node)
    return new_gm, id
end

function initialize!(gm::GraphicalModel{I}, cd::ConditionalDistribution, parent_id::I) where {I}
    new_gm, id = new_id(gm)
    parent = new_gm.nodes[parent_id]
    parent_child_ref = push!(parent.children, id)
    node = Initialized(id, parent_id, parent_child_ref, cd)
    set!(new_gm, node)
    return new_gm, id
end

function value!(gm::GraphicalModel{I}, id::I) where {I}
    _, val = value!(gm, gm.nodes[id])
    return val
end

function observe!(gm::GraphicalModel{I}, id::I, value::AbstractArray) where {I}
    _ = observe!(gm, gm.nodes[id], value)
end

function dist!(gm::GraphicalModel{I}, id::I) where {I}
    node = dist!(gm, gm.nodes[id])
    return node.d
end

