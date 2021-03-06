export freeEnergyAlgorithm

"""
The `freeEnergyAlgorithm` function accepts an `Algorithm` and populates
required fields for computing the variational free energy.
"""
function freeEnergyAlgorithm(algo=currentInferenceAlgorithm())
    average_energies_vect = Vector{Dict{Symbol, Any}}()
    entropies_vect = Vector{Dict{Symbol, Any}}()
    free_energy_dict = Dict{Symbol, Any}(:average_energies => average_energies_vect,
                                         :entropies => entropies_vect)

    for pf in values(algo.posterior_factorization)
        hasCollider(pf) && error("Cannot construct localized free energy algorithm. Posterior distribution for factor with id :$(pf.id) does not factor according to local graph structure. This is likely due to a conditional dependence in the posterior distribution (see Bishop p.485). Consider wrapping conditionally dependent variables in a composite node.")
    end

    for node in sort(collect(values(algo.graph.nodes)))
        if !isa(node, DeltaFactor) # Non-deterministic factor, add to free energy functional
            # Include average energy term
            average_energy = Dict{Symbol, Any}(:node => typeof(node),
                                               :inbounds => collectAverageEnergyInbounds(node, algo.target_to_marginal_entry))
            push!(average_energies_vect, average_energy)

            # Construct differential entropy term
            outbound_interface = node.interfaces[1]
            outbound_partner = ultimatePartner(outbound_interface)
            if !(outbound_partner == nothing) && !isa(outbound_partner.node, Clamp) # Differential entropy is required
                dict = algo.posterior_factorization.node_edge_to_cluster
                if haskey(dict, (node, outbound_interface.edge)) # Outbound edge is part of a cluster
                    inbounds = collectConditionalDifferentialEntropyInbounds(node, algo.target_to_marginal_entry)
                    entropy = Dict{Symbol, Any}(:conditional => true,
                                                :inbounds => inbounds)
                else
                    inbound = algo.target_to_marginal_entry[outbound_interface.edge.variable]
                    entropy = Dict{Symbol, Any}(:conditional => false,
                                                :inbounds => [inbound])
                end
                push!(entropies_vect, entropy)
            end        
        end
    end
    
    algo.average_energies = average_energies_vect
    algo.entropies = entropies_vect
    
    return algo
end

function collectAverageEnergyInbounds(node::FactorNode, target_to_marginal_entry::Dict)
    inbounds = Any[]
    local_clusters = localPosteriorFactorization(node)

    posterior_factors = Union{PosteriorFactor, Edge}[] # Keep track of encountered posterior factors
    for node_interface in node.interfaces
        inbound_interface = ultimatePartner(node_interface)
        node_interface_posterior_factor = PosteriorFactor(node_interface.edge)

        if (inbound_interface != nothing) && isa(inbound_interface.node, Clamp)
            # Hard-code marginal of constant node in schedule
            push!(inbounds, assembleClamp!(inbound_interface.node, ProbabilityDistribution))
        elseif !(node_interface_posterior_factor in posterior_factors)
            # Collect marginal entry from marginal dictionary (if marginal entry is not already accepted)
            target = local_clusters[node_interface_posterior_factor]
            push!(inbounds, target_to_marginal_entry[target])
        end

        push!(posterior_factors, node_interface_posterior_factor)
    end

    return inbounds
end

function collectConditionalDifferentialEntropyInbounds(node::FactorNode, target_to_marginal_entry::Dict)
    inbounds = Any[]
    outbound_edge = node.interfaces[1].edge
    dict = current_posterior_factorization.node_edge_to_cluster
    cluster = dict[(node, outbound_edge)]

    push!(inbounds, target_to_marginal_entry[cluster]) # Add joint term to inbounds

    # Add conditioning terms to inbounds
    for node_interface in node.interfaces
        inbound_interface = ultimatePartner(node_interface)

        if !(node_interface.edge in cluster.edges)
            # Only collect conditioning variables that are part of the cluster
            continue
        elseif (node_interface.edge === outbound_edge)
            # Skip the outbound edge, whose variable is not part of the conditioning term
            continue
        elseif (inbound_interface != nothing) && isa(inbound_interface.node, Clamp)
            # Hard-code marginal of constant node in schedule
            push!(inbounds, assembleClamp!(inbound_interface.node, ProbabilityDistribution))
        else
            target = node_interface.edge.variable
            push!(inbounds, target_to_marginal_entry[target])
        end
    end

    return inbounds
end