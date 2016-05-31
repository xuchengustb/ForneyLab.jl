export GaussianMixtureNodePar

"""
Description:

    Univariate and multivariate gaussian mixture model for data with two clusters:
    f(m1,m2,w1,w2,pi,x,z) = N(x|m1,1/w1)^z[1] * N(x|m2,1/w2)^z[2] * pi[1]^z[1] * pi[2]^z[2]


                  | pi
                  |
          ________|________
      m   |               |  x
     -----|               |----
          |               |  z
          |       GM      |----
          |               |
          |               |
      w   |               |
     -----|               |
          |_______________|


Interfaces:

    1 i[:pi]
    2 i[:m]
    3 i[:w]
    4 i[:x]
    5 i[:z]


Construction:

    GaussianMixtureNodePar(id=:my_node)
"""
type GaussianMixtureNodePar <: Node
    id::Symbol
    interfaces::Array{Interface,1}
    i::Dict{Symbol,Interface}

    function GaussianMixtureNodePar(; id=generateNodeId(GaussianMixtureNodePar))
        self = new(id, Array(Interface, 5), Dict{Symbol,Interface}())
        #self = new(id, Array(Interface, 7), Dict{Symbol,Interface}())
        addNode!(currentGraph(), self)

        for (iface_index, iface_handle) in enumerate([:pi, :m, :w, :x, :z])
        #for (iface_index, iface_handle) in enumerate([:pi, :m1, :w1, :m2, :w2, :x, :z])
            self.i[iface_handle] = self.interfaces[iface_index] = Interface(self)
        end

        return self
    end
end

isDeterministic(::GaussianMixtureNodePar) = false

#Sum product rule
#Predictive distribution towards x

#Univariate case with 2 clusters
function sumProductRule!(   node::GaussianMixtureNodePar,
                            outbound_interface_index::Type{Val{4}},
                            outbound_dist::Mixture{Gaussian},
                            msg_pi::Message{Beta},
                            msg_m::Message{PartitionedDistribution{Gaussian,2}},
                            msg_w::Message{PartitionedDistribution{Gamma,2}},
                            msg_x::Any,
                            msg_z::Message{Bernoulli})

          ensureParameters!(msg_m.payload.factors[1], (:m, :V))
          ensureParameters!(msg_m.payload.factors[2], (:m, :V))
          resize!(outbound_dist, 2)

          #for the first component
          outbound_dist.components[1].m = msg_m.payload.factors[1].m
          outbound_dist.components[1].V = (msg_w.payload.factors[1].b/(msg_w.payload.factors[1].a-1)+msg_m.payload.factors[1].V)
          outbound_dist.components[1].xi=NaN
          outbound_dist.components[1].W=NaN

          w1     = msg_z.payload.p*msg_pi.payload.a/(msg_pi.payload.a+msg_pi.payload.b)

          #for the second component
          outbound_dist.components[2].m = msg_m.payload.factors[2].m
          outbound_dist.components[2].V = (msg_w.payload.factors[2].b/(msg_w.payload.factors[2].a-1)+msg_m.payload.factors[2].V)
          outbound_dist.components[2].xi=NaN
          outbound_dist.components[2].W=NaN

          w2      = (1-msg_z.payload.p)*msg_pi.payload.b/(msg_pi.payload.a+msg_pi.payload.b)

          outbound_dist.weights[1]=w1/(w1+w2)
          outbound_dist.weights[2]=w2/(w1+w2)

    return outbound_dist
end

#Sum product predictive distribution
#Univariate case with k clusters
function sumProductRule!{n_factors}(   node::GaussianMixtureNodePar,
                            outbound_interface_index::Type{Val{4}},
                            outbound_dist::Mixture{Gaussian},
                            msg_pi::Message{Dirichlet{n_factors}},
                            msg_m::Message{PartitionedDistribution{Gaussian,n_factors}},
                            msg_w::Message{PartitionedDistribution{Gamma,n_factors}},
                            msg_x::Any,
                            msg_z::Message{Categorical{n_factors}})

          resize!(outbound_dist, n_factors)
          w=ones(n_factors)

          k=collect(1:n_factors)
          sum_a=sum(msg_pi.payload.alpha[k])

          for k=1:n_factors
            ensureParameters!(msg_m.payload.factors[k], (:m, :V))
            outbound_dist.components[k].m = msg_m.payload.factors[k].m
            outbound_dist.components[k].V = (msg_w.payload.factors[k].b/(msg_w.payload.factors[k].a-1)+msg_m.payload.factors[k].V)
            outbound_dist.components[k].xi=NaN
            outbound_dist.components[k].W=NaN

            w[k]     = msg_z.payload.p[k]*msg_pi.payload.alpha[k]/(sum_a)
          end

          sum_w=sum(w)
          for k=1:n_factors
            outbound_dist.weights[k]=w[k]/(sum_w)
          end


    return outbound_dist
end

#Sum product predictive distribution
#Multivariate case with 2 clusters
function sumProductRule!{n_factors,dims}(   node::GaussianMixtureNodePar,
                            outbound_interface_index::Type{Val{4}},
                            outbound_dist::Mixture{MvGaussian{dims}},
                            msg_pi::Message{Beta},
                            msg_m::Message{PartitionedDistribution{MvGaussian{dims},n_factors}},
                            msg_w::Message{PartitionedDistribution{Wishart{dims},n_factors}},
                            msg_x::Any,
                            msg_z::Message{Bernoulli})

      resize!(outbound_dist, 2)
      ensureParameters!(msg_m.payload.factors[1], (:m, :V))
      ensureParameters!(msg_m.payload.factors[2], (:m, :V))
      w=ones(2)

      outbound_dist.components[1].m = msg_m.payload.factors[1].m
      outbound_dist.components[1].V = inv(msg_w.payload.factors[1].V)/(msg_w.payload.factors[1].nu-dims-1.)+msg_m.payload.factors[1].V
      invalidate!(outbound_dist.components[1].xi)
      invalidate!(outbound_dist.components[1].W)

      outbound_dist.components[2].m = msg_m.payload.factors[2].m
      outbound_dist.components[2].V = inv(msg_w.payload.factors[2].V)/(msg_w.payload.factors[2].nu-dims-1.)+msg_m.payload.factors[2].V
      invalidate!(outbound_dist.components[2].xi)
      invalidate!(outbound_dist.components[2].W)

      w[1]     = msg_z.payload.p*msg_pi.payload.a/(msg_pi.payload.a+msg_pi.payload.b)
      w[2]     = (1-msg_z.payload.p)*msg_pi.payload.b/(msg_pi.payload.a+msg_pi.payload.b)


      #Normalize weight
      outbound_dist.weights[1]=w[1]/(w[1]+w[2])
      outbound_dist.weights[2]=w[2]/(w[1]+w[2])


    return outbound_dist
end

#Sum product predictive distribution
#Multivariate case with k clusters
function sumProductRule!{n_factors,dims}(   node::GaussianMixtureNodePar,
                            outbound_interface_index::Type{Val{4}},
                            outbound_dist::Mixture{MvGaussian{dims}},
                            msg_pi::Message{Dirichlet{n_factors}},
                            msg_m::Message{PartitionedDistribution{MvGaussian{dims},n_factors}},
                            msg_w::Message{PartitionedDistribution{Wishart{dims},n_factors}},
                            msg_x::Any,
                            msg_z::Message{Categorical{n_factors}})

          resize!(outbound_dist, n_factors)
          w=ones(n_factors)

          k=collect(1:n_factors)
          sum_a=sum(msg_pi.payload.alpha[k])

          for k=1:n_factors
            ensureParameters!(msg_m.payload.factors[k], (:m, :V))
            outbound_dist.components[k].m = msg_m.payload.factors[k].m
            outbound_dist.components[k].V = inv(msg_w.payload.factors[k].V)/(msg_w.payload.factors[k].nu-dims-1.)+msg_m.payload.factors[k].V
            invalidate!(outbound_dist.components[k].xi)
            invalidate!(outbound_dist.components[k].W)

            w[k]     = msg_z.payload.p[k]*msg_pi.payload.alpha[k]/(sum_a)
          end

          sum_w=sum(w)
          for k=1:n_factors
            outbound_dist.weights[k]=w[k]/(sum_w)
          end


    return outbound_dist
end

# VMP message towards i[:pi]
# Univariate gaussian with two clusters
function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{1}},
                            outbound_dist::Beta,
                            ::Any,
                            q_m::PartitionedDistribution{Gaussian,n_factors},
                            q_w::PartitionedDistribution{Gamma,n_factors},
                            q_x::Gaussian,
                            q_z::Bernoulli)



    outbound_dist.a   =   q_z.p+1.
    outbound_dist.b   =   2.-q_z.p

    return outbound_dist
end

# # VMP message towards i[:pi]
# # Univariate gaussian with two clusters with gaussian mixture on x
# function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
#                             ::Type{Val{1}},
#                             outbound_dist::Beta,
#                             ::Any,
#                             q_m::PartitionedDistribution{Gaussian,n_factors},
#                             q_w::PartitionedDistribution{Gamma,n_factors},
#                             q_x::Mixture{Gaussian},
#                             q_z::Bernoulli)
#
#
#
#     outbound_dist.a   =   q_z.p+1.
#     outbound_dist.b   =   2.-q_z.p
#
#     return outbound_dist
# end

# VMP message towards i[:pi]
# Multivariate gaussian with two clusters
function variationalRule!{dims,n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{1}},
                            outbound_dist::Beta,
                            ::Any,
                            q_m::PartitionedDistribution{MvGaussian{dims},n_factors},
                            q_w::PartitionedDistribution{Wishart{dims},n_factors},
                            q_x::MvGaussian{dims},
                            q_z::Bernoulli)



     outbound_dist.a   =   q_z.p+1.
     outbound_dist.b   =   2.-q_z.p

    return outbound_dist
end

# # VMP message towards i[:pi]
# # Multivariate gaussian with two clusters with mixture on x
# function variationalRule!{dims,n_factors}(  node::GaussianMixtureNodePar,
#                             ::Type{Val{1}},
#                             outbound_dist::Beta,
#                             ::Any,
#                             q_m::PartitionedDistribution{MvGaussian{dims},n_factors},
#                             q_w::PartitionedDistribution{Wishart{dims},n_factors},
#                             q_x::Mixture{MvGaussian{dims}},
#                             q_z::Bernoulli)
#
#     println("start pi")
#
#      outbound_dist.a   =   q_z.p+1.
#      outbound_dist.b   =   2.-q_z.p
#      println("end pi")
#
#     return outbound_dist
# end

# VMP message towards i[:pi]
# Multivariate gaussian with multiple clusters
function variationalRule!{dims,n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{1}},
                            outbound_dist::Dirichlet{n_factors},
                            ::Any,
                            q_m::PartitionedDistribution{MvGaussian{dims},n_factors},
                            q_w::PartitionedDistribution{Wishart{dims},n_factors},
                            q_x::MvGaussian{dims},
                            q_z::Categorical{n_factors})

     a=zeros(n_factors)

     for k=1:n_factors
       a[k]=q_z.p[k]+1
     end

     outbound_dist.alpha   =   a

    return outbound_dist
end

# VMP message towards i[:pi]
# Univariate gaussian with multiple clusters
function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{1}},
                            outbound_dist::Dirichlet{n_factors},
                            ::Any,
                            q_m::PartitionedDistribution{Gaussian,n_factors},
                            q_w::PartitionedDistribution{Gamma,n_factors},
                            q_x::Gaussian,
                            q_z::Categorical{n_factors})

     a=zeros(n_factors)

     for k=1:n_factors
       a[k]=q_z.p[k]+1
     end

     outbound_dist.alpha   =   a

    return outbound_dist
end

# # VMP message towards i[:pi]
# # Univariate gaussian with multiple clusters with Gaussian Mixture on x
# function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
#                             ::Type{Val{1}},
#                             outbound_dist::Dirichlet{n_factors},
#                             ::Any,
#                             q_m::PartitionedDistribution{Gaussian,n_factors},
#                             q_w::PartitionedDistribution{Gamma,n_factors},
#                             q_x::Mixture{Gaussian},
#                             q_z::Categorical{n_factors})
#
#      a=zeros(n_factors)
#
#      for k=1:n_factors
#        a[k]=q_z.p[k]+1
#      end
#
#      outbound_dist.alpha   =   a
#
#     return outbound_dist
# end

# VMP message towards i[:m]
# Univariate gaussian with two clusters
function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{2}},
                            outbound_dist::PartitionedDistribution{Gaussian,n_factors},
                            q_pi::Beta,
                            ::Any,
                            q_w::PartitionedDistribution{Gamma,n_factors},
                            q_x::Gaussian,
                            q_z::Bernoulli)
        ensureParameters!(q_x, (:m,:V))

        outbound_dist.factors[1].m   =   q_x.m
        outbound_dist.factors[2].m   =   q_x.m
        outbound_dist.factors[1].V   =   NaN
        outbound_dist.factors[1].xi  =   NaN
        outbound_dist.factors[2].V   =   NaN
        outbound_dist.factors[2].xi  =   NaN
        outbound_dist.factors[1].W   =   q_z.p*q_w.factors[1].a/q_w.factors[1].b
        outbound_dist.factors[2].W   =   (1.-q_z.p)*q_w.factors[2].a/q_w.factors[2].b

    return outbound_dist
end

# # VMP message towards i[:m]
# # Univariate gaussian with two clusters with mixture on x
# function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
#                             ::Type{Val{2}},
#                             outbound_dist::PartitionedDistribution{Gaussian,n_factors},
#                             q_pi::Beta,
#                             ::Any,
#                             q_w::PartitionedDistribution{Gamma,n_factors},
#                             q_x::Mixture{Gaussian},
#                             q_z::Bernoulli)
#         resize!(q_x, 2)
#         ensureParameters!(q_x.components[1], (:m,:V))
#         ensureParameters!(q_x.components[2], (:m,:V))
#
#
#
#         outbound_dist.factors[1].m   =   q_x.weights[1]*q_x.components[1].m+q_x.weights[2]*q_x.components[2].m
#         outbound_dist.factors[2].m   =   q_x.weights[1]*q_x.components[1].m+q_x.weights[2]*q_x.components[2].m
#         outbound_dist.factors[1].V   =   NaN
#         outbound_dist.factors[1].xi  =   NaN
#         outbound_dist.factors[2].V   =   NaN
#         outbound_dist.factors[2].xi  =   NaN
#         outbound_dist.factors[1].W   =   q_z.p*q_w.factors[1].a/q_w.factors[1].b
#         outbound_dist.factors[2].W   =   (1.-q_z.p)*q_w.factors[2].a/q_w.factors[2].b
#
#     return outbound_dist
# end

# VMP message towards i[:m]
# Multivariate Gaussian with two clusters
function variationalRule!{dims,n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{2}},
                            outbound_dist::PartitionedDistribution{MvGaussian{dims},n_factors},
                            q_pi::Beta,
                            ::Any,
                            q_w::PartitionedDistribution{Wishart{dims},n_factors},
                            q_x::MvGaussian{dims},
                            q_z::Bernoulli)
    ensureParameters!(q_x, (:m, :V))

     outbound_dist.factors[1].m    =   deepcopy(q_x.m)
     outbound_dist.factors[2].m    =   deepcopy(q_x.m)
     invalidate!(outbound_dist.factors[1].V)
     invalidate!(outbound_dist.factors[2].V)
     invalidate!(outbound_dist.factors[1].xi)
     invalidate!(outbound_dist.factors[2].xi)
     outbound_dist.factors[1].W    =   q_z.p*q_w.factors[1].nu*q_w.factors[1].V
     outbound_dist.factors[2].W    =   (1.-q_z.p)*q_w.factors[2].nu*q_w.factors[2].V

    return outbound_dist
end

# VMP message towards i[:m]
# # Multivariate Gaussian with two clusters with mixture on x
# function variationalRule!{dims,n_factors}(  node::GaussianMixtureNodePar,
#                             ::Type{Val{2}},
#                             outbound_dist::PartitionedDistribution{MvGaussian{dims},n_factors},
#                             q_pi::Beta,
#                             ::Any,
#                             q_w::PartitionedDistribution{Wishart{dims},n_factors},
#                             q_x::Mixture{MvGaussian{dims}},
#                             q_z::Bernoulli)
#     println("start m")
#     resize!(q_x, 2)
#     ensureParameters!(q_x.components[1], (:m, :V))
#     ensureParameters!(q_x.components[2], (:m, :V))
#
#      e_x= q_x.weights[1]*q_x.components[1].m+q_x.weights[2]*q_x.components[2].m
#      outbound_dist.factors[1].m    =   e_x
#      outbound_dist.factors[2].m    =   e_x
#      invalidate!(outbound_dist.factors[1].V)
#      invalidate!(outbound_dist.factors[2].V)
#      invalidate!(outbound_dist.factors[1].xi)
#      invalidate!(outbound_dist.factors[2].xi)
#      outbound_dist.factors[1].W    =   q_z.p*q_w.factors[1].nu*q_w.factors[1].V
#      outbound_dist.factors[2].W    =   (1.-q_z.p)*q_w.factors[2].nu*q_w.factors[2].V
#      println("end m")
#
#     return outbound_dist
# end

# VMP message towards i[:m]
# Multivariate Gaussian with multiple clusters
function variationalRule!{dims,n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{2}},
                            outbound_dist::PartitionedDistribution{MvGaussian{dims},n_factors},
                            q_pi::Dirichlet{n_factors},
                            ::Any,
                            q_w::PartitionedDistribution{Wishart{dims},n_factors},
                            q_x::MvGaussian{dims},
                            q_z::Categorical{n_factors})
    ensureParameters!(q_x, (:m, :V))


    for k=1:n_factors
      outbound_dist.factors[k].m  = deepcopy(q_x.m)
       invalidate!(outbound_dist.factors[k].V)
       invalidate!(outbound_dist.factors[k].xi)
      outbound_dist.factors[k].W  = q_z.p[k]*q_w.factors[k].nu*q_w.factors[k].V
    end

    return outbound_dist
end

# VMP message towards i[:m]
# Univariate Gaussian with multiple clusters
function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{2}},
                            outbound_dist::PartitionedDistribution{Gaussian,n_factors},
                            q_pi::Dirichlet{n_factors},
                            ::Any,
                            q_w::PartitionedDistribution{Gamma,n_factors},
                            q_x::Gaussian,
                            q_z::Categorical{n_factors})
    ensureParameters!(q_x, (:m, :V))


    for k=1:n_factors
      outbound_dist.factors[k].m  = deepcopy(q_x.m)
       outbound_dist.factors[k].V = NaN
       outbound_dist.factors[k].xi= NaN
      outbound_dist.factors[k].W  = q_z.p[k]*q_w.factors[k].a/q_w.factors[k].b
    end

    return outbound_dist
end

# # VMP message towards i[:m]
# # Univariate Gaussian with multiple clusters with Gaussian mixture on x
# function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
#                             ::Type{Val{2}},
#                             outbound_dist::PartitionedDistribution{Gaussian,n_factors},
#                             q_pi::Dirichlet{n_factors},
#                             ::Any,
#                             q_w::PartitionedDistribution{Gamma,n_factors},
#                             q_x::Mixture{Gaussian},
#                             q_z::Categorical{n_factors})
#     resize!(q_x, n_factors)
#     e_x=0.
#     for k=1:n_factors
#       ensureParameters!(q_x.components[k], (:m, :V))
#       e_x=e_x+q_x.weights[k]*q_x.components[k].m
#     end
#
#
#     for k=1:n_factors
#       outbound_dist.factors[k].m  = e_x
#       outbound_dist.factors[k].V = NaN
#       outbound_dist.factors[k].xi= NaN
#       outbound_dist.factors[k].W  = q_z.p[k]*q_w.factors[k].a/q_w.factors[k].b
#     end
#
#     return outbound_dist
# end

# VMP message towards i[:w]
# Univariate gaussian with two clusters
function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{3}},
                            outbound_dist::PartitionedDistribution{Gamma,n_factors},
                            q_pi::Beta,
                            q_m::PartitionedDistribution{Gaussian,n_factors},
                            ::Any,
                            q_x::Gaussian,
                            q_z::Bernoulli)

      ensureParameters!(q_m.factors[1], (:m, :V))
      ensureParameters!(q_m.factors[2], (:m, :V))
      ensureParameters!(q_x, (:m, :V))

      outbound_dist.factors[1].a   =   1.+0.5*q_z.p
      e_m1_square                  =   q_m.factors[1].V+q_m.factors[1].m^2+q_x.V
      outbound_dist.factors[1].b   =   0.5*q_z.p*(q_x.m^2-2.*q_x.m*q_m.factors[1].m+e_m1_square)

      outbound_dist.factors[2].a   =   1.+0.5*(1.-q_z.p)
      e_m2_square                  =   q_m.factors[2].V+q_m.factors[2].m^2+q_x.V
      outbound_dist.factors[2].b   =   0.5*(1.-q_z.p)*(q_x.m^2-2.*q_x.m*q_m.factors[2].m+e_m2_square)

    return outbound_dist
end

# # VMP message towards i[:w]
# # Univariate gaussian with two clusters with mixture on x
# function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
#                             ::Type{Val{3}},
#                             outbound_dist::PartitionedDistribution{Gamma,n_factors},
#                             q_pi::Beta,
#                             q_m::PartitionedDistribution{Gaussian,n_factors},
#                             ::Any,
#                             q_x::Mixture{Gaussian},
#                             q_z::Bernoulli)
#
#       ensureParameters!(q_m.factors[1], (:m, :V))
#       ensureParameters!(q_m.factors[2], (:m, :V))
#       ensureParameters!(q_x.components[1], (:m, :V))
#       ensureParameters!(q_x.components[2], (:m, :V))
#
#       outbound_dist.factors[1].a   =   1.+0.5*q_z.p
#       e_m1_square                  =   q_m.factors[1].V+q_m.factors[1].m^2#+q_x.V
#       e_x                          =   q_x.weights[1]*q_x.components[1].m+q_x.weights[2]*q_x.components[2].m
#       cov_x                        =   q_x.weights[1]*(q_x.components[1].m^2+q_x.components[1].V)+q_x.weights[2]*(q_x.components[2].m^2+q_x.components[2].V)-e_x^2
#       outbound_dist.factors[1].b   =   0.5*q_z.p*(e_x^2-2.*e_x*q_m.factors[1].m+cov_x+e_m1_square)
#
#       outbound_dist.factors[2].a   =   1.+0.5*(1.-q_z.p)
#       e_m2_square                  =   q_m.factors[2].V+q_m.factors[2].m^2#+q_x.V
#       outbound_dist.factors[2].b   =   0.5*(1.-q_z.p)*(e_x^2-2.*e_x*q_m.factors[2].m+cov_x+e_m2_square)
#
#     return outbound_dist
# end


# VMP message towards i[:w]
# Multivariate Gaussian with two clusters
function variationalRule!{dims,n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{3}},
                            outbound_dist::PartitionedDistribution{Wishart{dims},n_factors},
                            q_pi::Beta,
                            q_m::PartitionedDistribution{MvGaussian{dims},n_factors},
                            ::Any,
                            q_x::MvGaussian{dims},
                            q_z::Bernoulli)

    ensureParameters!(q_m.factors[1], (:m, :V))
    ensureParameters!(q_x, (:m, :V))
    ensureParameters!(q_m.factors[2], (:m, :V))

    outbound_dist.factors[1].nu    =   1.+q_z.p+dims
    gausterm1           =   (deepcopy(q_x.m)-q_m.factors[1].m)*transpose(deepcopy(q_x.m)-q_m.factors[1].m)+q_m.factors[1].V+q_x.V

    #if statement to prevent multiplication with zero
    if det((q_z.p)*gausterm1)<tiny
      outbound_dist.factors[1].V     =   pinv((q_z.p)*gausterm1+eye(dims)*tiny)
    else
      outbound_dist.factors[1].V     =   pinv(q_z.p*gausterm1)
    end



    outbound_dist.factors[2].nu    =   1.+(1.-q_z.p)+dims
    gausterm2           =   (deepcopy(q_x.m)-q_m.factors[2].m)*transpose(deepcopy(q_x.m)-q_m.factors[2].m)+q_m.factors[2].V+q_x.V

    #if statement to prevent multiplication by zero

    if det((1.-q_z.p)*gausterm2)<tiny
      outbound_dist.factors[2].V     =   pinv((1.-q_z.p)*gausterm2+eye(dims)*tiny)

    else
      outbound_dist.factors[2].V     =   pinv((1.-q_z.p)*gausterm2)

    end

    return outbound_dist
end

# # VMP message towards i[:w]
# # Multivariate Gaussian with two clusters with mixture on x
# function variationalRule!{dims,n_factors}(  node::GaussianMixtureNodePar,
#                             ::Type{Val{3}},
#                             outbound_dist::PartitionedDistribution{Wishart{dims},n_factors},
#                             q_pi::Beta,
#                             q_m::PartitionedDistribution{MvGaussian{dims},n_factors},
#                             ::Any,
#                             q_x::Mixture{MvGaussian{dims}},
#                             q_z::Bernoulli)
#     println("start w")
#     ensureParameters!(q_m.factors[1], (:m, :V))
#     ensureParameters!(q_x.components[1], (:m, :V))
#     ensureParameters!(q_m.factors[2], (:m, :V))
#     ensureParameters!(q_x.components[2], (:m, :V))
#
#     e_x= q_x.weights[1]*q_x.components[1].m+q_x.weights[2]*q_x.components[2].m
#     cov_x                        =   q_x.weights[1]*(q_x.components[1].m*q_x.components[1].m'+q_x.components[1].V)+q_x.weights[2]*(q_x.components[2].m*q_x.components[2].m'+q_x.components[2].V)-e_x*e_x'
#     outbound_dist.factors[1].nu    =   1.+q_z.p+dims
#     gausterm1           =   (e_x-q_m.factors[1].m)*transpose(e_x-q_m.factors[1].m)+q_m.factors[1].V+cov_x
#
#     #if statement to prevent multiplication with zero
#     if det((q_z.p)*gausterm1)<tiny
#       outbound_dist.factors[1].V     =   pinv((q_z.p)*gausterm1+eye(dims)*tiny)
#     else
#       outbound_dist.factors[1].V     =   pinv(q_z.p*gausterm1)
#     end
#
#
#
#     outbound_dist.factors[2].nu    =   1.+(1.-q_z.p)+dims
#     gausterm2           =   (e_x-q_m.factors[2].m)*transpose(e_x-q_m.factors[2].m)+q_m.factors[2].V+cov_x
#
#     #if statement to prevent multiplication by zero
#
#     if det((1.-q_z.p)*gausterm2)<tiny
#       outbound_dist.factors[2].V     =   pinv((1.-q_z.p)*gausterm2+eye(dims)*tiny)
#
#     else
#       outbound_dist.factors[2].V     =   pinv((1.-q_z.p)*gausterm2)
#
#     end
#     println("end w")
#     return outbound_dist
# end

# VMP message towards i[:w]
# Multivariate Gaussian with multiple clusters
function variationalRule!{dims,n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{3}},
                            outbound_dist::PartitionedDistribution{Wishart{dims},n_factors},
                            q_pi::Dirichlet{n_factors},
                            q_m::PartitionedDistribution{MvGaussian{dims},n_factors},
                            ::Any,
                            q_x::MvGaussian{dims},
                            q_z::Categorical{n_factors})

    ensureParameters!(q_x,(:m,:V))

    for k=1:n_factors
      ensureParameters!(q_m.factors[k], (:m, :V))

      outbound_dist.factors[k].nu=1.+q_z.p[k]+dims
      gausterm           =   (deepcopy(q_x.m)-q_m.factors[k].m)*transpose(deepcopy(q_x.m)-q_m.factors[k].m)+q_m.factors[k].V+q_x.V

      #if statement to prevent multiplication with zero
      if det((q_z.p[k])*gausterm)<tiny
        outbound_dist.factors[k].V     =   pinv((q_z.p[k])*gausterm+eye(dims)*tiny)
      else
        outbound_dist.factors[k].V     =   pinv(q_z.p[k]*gausterm)
      end

    end

    return outbound_dist
end

# VMP message towards i[:w]
# Univariate Gaussian with multiple clusters
function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{3}},
                            outbound_dist::PartitionedDistribution{Gamma,n_factors},
                            q_pi::Dirichlet{n_factors},
                            q_m::PartitionedDistribution{Gaussian,n_factors},
                            ::Any,
                            q_x::Gaussian,
                            q_z::Categorical{n_factors})

    ensureParameters!(q_x, (:m, :V))

    for k=1:n_factors
      ensureParameters!(q_m.factors[k], (:m, :V))

      outbound_dist.factors[k].a  = 1.+0.5*q_z.p[k]
      e_m1_square                 = q_m.factors[k].V+q_m.factors[k].m^2+q_x.V
      outbound_dist.factors[k].b  = 0.5*q_z.p[k]*(q_x.m^2-2.*q_x.m*q_m.factors[k].m+e_m1_square)
      if outbound_dist.factors[k].b<tiny
        outbound_dist.factors[k].b =100*tiny+0.5*q_z.p[k]*(q_x.m^2-2.*q_x.m*q_m.factors[k].m+e_m1_square)
      end

    end


    return outbound_dist
end

# # VMP message towards i[:w]
# # Univariate Gaussian with multiple clusters with mixture on x
# function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
#                             ::Type{Val{3}},
#                             outbound_dist::PartitionedDistribution{Gamma,n_factors},
#                             q_pi::Dirichlet{n_factors},
#                             q_m::PartitionedDistribution{Gaussian,n_factors},
#                             ::Any,
#                             q_x::Mixture{Gaussian},
#                             q_z::Categorical{n_factors})
#
#     resize!(q_x, n_factors)
#     e_x=0.
#     cov_x=0.
#     for k=1:n_factors
#       ensureParameters!(q_x.components[k], (:m, :V))
#       e_x=e_x+q_x.weights[k]*q_x.components[k].m
#       cov_x=cov_x+q_x.weights[k]*(q_x.components[k].m^2+q_x.components[k].V)
#     end
#
#
#     cov_x                        =   cov_x-e_x^2
#
#     for k=1:n_factors
#       ensureParameters!(q_m.factors[k], (:m, :V))
#
#       outbound_dist.factors[k].a  = 1.+0.5*q_z.p[k]
#       e_m1_square                 = q_m.factors[k].V+q_m.factors[k].m^2
#       outbound_dist.factors[k].b  = 0.5*q_z.p[k]*(e_x^2-2.*e_x*q_m.factors[k].m+e_m1_square+cov_x)
#       if outbound_dist.factors[k].b<tiny
#         outbound_dist.factors[k].b =100*tiny+0.5*q_z.p[k]*(e_x^2-2.*e_x*q_m.factors[k].m+e_m1_square+cov_x)
#       end
#
#     end
#
#
#     return outbound_dist
# end


# VMP message towards i[:z]
# Univariate gaussian with two clusters
function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{5}},
                            outbound_dist::Bernoulli,
                            q_pi::Beta,
                            q_m::PartitionedDistribution{Gaussian,n_factors},
                            q_w::PartitionedDistribution{Gamma,n_factors},
                            q_x::Gaussian,
                            ::Any)

      ensureParameters!(q_m.factors[1], (:m, :V))
      ensureParameters!(q_x, (:m, :V))
      ensureParameters!(q_m.factors[2], (:m, :V))

      #calculating ln(ro1)
      e_ln_pi1    =   digamma(q_pi.a)-digamma(q_pi.a+q_pi.b)
      e_ln_w1     =   digamma(q_w.factors[1].a)-log(q_w.factors[1].b)
      e_m1_square =   q_x.m^2-2.0*q_x.m*q_m.factors[1].m+q_m.factors[1].V+q_m.factors[1].m^2+q_x.V
      ln_ro1      =   e_ln_pi1+0.5*e_ln_w1-0.5*log(2pi)-0.5*q_w.factors[1].a/q_w.factors[1].b*e_m1_square

      #calculating ln(ro2) for normalization

      e_ln_pi2    =   digamma(q_pi.b)-digamma(q_pi.b+q_pi.a)
      e_ln_w2     =   digamma(q_w.factors[2].a)-log(q_w.factors[2].b)
      e_m2_square =   q_x.m^2-2.0*q_x.m*q_m.factors[2].m+q_m.factors[2].V+q_m.factors[2].m^2+q_x.V
      ln_ro2      =   e_ln_pi2+0.5*e_ln_w2-0.5*log(2pi)-0.5*q_w.factors[2].a/q_w.factors[2].b*e_m2_square

      if (exp(ln_ro1)+exp(ln_ro2))>tiny
          outbound_dist.p = exp(ln_ro1)/(exp(ln_ro1)+exp(ln_ro2))
      else
          outbound_dist.p=1/2
      end


    return outbound_dist
end

# # VMP message towards i[:z]
# # Univariate gaussian with two clusters with mixture on x
# function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
#                             ::Type{Val{5}},
#                             outbound_dist::Bernoulli,
#                             q_pi::Beta,
#                             q_m::PartitionedDistribution{Gaussian,n_factors},
#                             q_w::PartitionedDistribution{Gamma,n_factors},
#                             q_x::Mixture{Gaussian},
#                             ::Any)
#
#       ensureParameters!(q_m.factors[1], (:m, :V))
#       ensureParameters!(q_x.components[1], (:m, :V))
#       ensureParameters!(q_x.components[2], (:m, :V))
#       ensureParameters!(q_m.factors[2], (:m, :V))
#
#       #calculating ln(ro1)
#       e_x                          =   q_x.weights[1]*q_x.components[1].m+q_x.weights[2]*q_x.components[2].m
#       cov_x                        =   q_x.weights[1]*(q_x.components[1].m^2+q_x.components[1].V)+q_x.weights[2]*(q_x.components[2].m^2+q_x.components[2].V)-e_x^2
#       e_ln_pi1    =   digamma(q_pi.a)-digamma(q_pi.a+q_pi.b)
#       e_ln_w1     =   digamma(q_w.factors[1].a)-log(q_w.factors[1].b)
#       e_m1_square =   e_x^2-2.0*e_x*q_m.factors[1].m+q_m.factors[1].V+q_m.factors[1].m^2+cov_x
#       ln_ro1      =   e_ln_pi1+0.5*e_ln_w1-0.5*log(2pi)-0.5*q_w.factors[1].a/q_w.factors[1].b*e_m1_square
#
#       #calculating ln(ro2) for normalization
#
#       e_ln_pi2    =   digamma(q_pi.b)-digamma(q_pi.b+q_pi.a)
#       e_ln_w2     =   digamma(q_w.factors[2].a)-log(q_w.factors[2].b)
#       e_m2_square =   e_x^2-2.0*e_x*q_m.factors[2].m+q_m.factors[2].V+q_m.factors[2].m^2+cov_x
#       ln_ro2      =   e_ln_pi2+0.5*e_ln_w2-0.5*log(2pi)-0.5*q_w.factors[2].a/q_w.factors[2].b*e_m2_square
#
#       if (exp(ln_ro1)+exp(ln_ro2))>tiny
#           outbound_dist.p = exp(ln_ro1)/(exp(ln_ro1)+exp(ln_ro2))
#       else
#           outbound_dist.p=1/2
#       end
#
#
#     return outbound_dist
# end

# VMP message towards i[:z]
# Multivariate Gaussian with two clusters
function variationalRule!{dims,n_factors}(node::GaussianMixtureNodePar,
                            ::Type{Val{5}},
                            outbound_dist::Bernoulli,
                            q_pi::Beta,
                            q_m::PartitionedDistribution{MvGaussian{dims},n_factors},
                            q_w::PartitionedDistribution{Wishart{dims}, n_factors},
                            q_x::MvGaussian{dims},
                            ::Any)

    ensureParameters!(q_m.factors[1], (:m, :V))
    ensureParameters!(q_x, (:m, :V))
    ensureParameters!(q_m.factors[2], (:m, :V))

    e_ln_pi1      =   digamma(q_pi.a)-digamma(q_pi.a+q_pi.b)

    #multivariate digamma
    i = collect(1:dims)
    multidi1=sum(digamma((q_w.factors[1].nu+1-i)/2))

    e_ln_w1       =   deepcopy(multidi1)+dims*log(2.0)+log(det(q_w.factors[1].V))
    e_w1          =   q_w.factors[1].nu*q_w.factors[1].V
    gausterm1 = (transpose(q_x.m-q_m.factors[1].m)*e_w1*(q_x.m-q_m.factors[1].m))[1] + trace((q_x.V+q_m.factors[1].V)*e_w1)

    ln_ro1        =   e_ln_pi1+0.5*e_ln_w1-dims/2.0*log(2.0*pi)-0.5*gausterm1


    #calculating ln(ro2) for normalization

    e_ln_pi2      =   digamma(q_pi.b)-digamma(q_pi.b+q_pi.a)

    #multivariate digamma
    i = collect(1:dims)
    multidi2= sum(digamma((q_w.factors[2].nu+1-i)/2))

    e_ln_w2       =  multidi2+dims*log(2.0)+log(det(q_w.factors[2].V))
    e_w2          =   q_w.factors[2].nu*q_w.factors[2].V
    gausterm2     =  (transpose(q_x.m-q_m.factors[2].m)*e_w2*(q_x.m-q_m.factors[2].m))[1] + trace((q_x.V+q_m.factors[2].V)*e_w2)


    ln_ro2        =   e_ln_pi2+0.5*e_ln_w2-dims/2.0*log(2.0*pi)-0.5*gausterm2

    #Normalize message
    #if statement to prevent division by zero
    if exp(ln_ro1)+exp(ln_ro2)>tiny
      outbound_dist.p = exp(ln_ro1)/(exp(ln_ro1)+exp(ln_ro2))
    else
      outbound_dist.p=0.5
    end
    return outbound_dist
end


# # VMP message towards i[:z]
# # Multivariate Gaussian with two clusters with mixture on x
# function variationalRule!{dims,n_factors}(node::GaussianMixtureNodePar,
#                             ::Type{Val{5}},
#                             outbound_dist::Bernoulli,
#                             q_pi::Beta,
#                             q_m::PartitionedDistribution{MvGaussian{dims},n_factors},
#                             q_w::PartitionedDistribution{Wishart{dims}, n_factors},
#                             q_x::Mixture{MvGaussian{dims}},
#                             ::Any)
#     println("start z")
#     ensureParameters!(q_m.factors[1], (:m, :V))
#     ensureParameters!(q_x.components[1], (:m, :V))
#     ensureParameters!(q_m.factors[2], (:m, :V))
#     ensureParameters!(q_x.components[2], (:m, :V))
#
#     e_x= q_x.weights[1]*q_x.components[1].m+q_x.weights[2]*q_x.components[2].m
#     cov_x                        =   q_x.weights[1]*(q_x.components[1].m*q_x.components[1].m'+q_x.components[1].V)+q_x.weights[2]*(q_x.components[2].m*q_x.components[2].m'+q_x.components[2].V)-e_x*e_x'
#
#
#     e_ln_pi1      =   digamma(q_pi.a)-digamma(q_pi.a+q_pi.b)
#
#     #multivariate digamma
#     i = collect(1:dims)
#     multidi1=sum(digamma((q_w.factors[1].nu+1-i)/2))
#
#     e_ln_w1       =   deepcopy(multidi1)+dims*log(2.0)+log(det(q_w.factors[1].V))
#     e_w1          =   q_w.factors[1].nu*q_w.factors[1].V
#     gausterm1 = (transpose(e_x-q_m.factors[1].m)*e_w1*(e_x-q_m.factors[1].m))[1] + trace((cov_x+q_m.factors[1].V)*e_w1)
#
#     ln_ro1        =   e_ln_pi1+0.5*e_ln_w1-dims/2.0*log(2.0*pi)-0.5*gausterm1
#
#
#     #calculating ln(ro2) for normalization
#
#     e_ln_pi2      =   digamma(q_pi.b)-digamma(q_pi.b+q_pi.a)
#
#     #multivariate digamma
#     i = collect(1:dims)
#     multidi2= sum(digamma((q_w.factors[2].nu+1-i)/2))
#
#     e_ln_w2       =  multidi2+dims*log(2.0)+log(det(q_w.factors[2].V))
#     e_w2          =   q_w.factors[2].nu*q_w.factors[2].V
#     gausterm2     =  (transpose(e_x-q_m.factors[2].m)*e_w2*(e_x-q_m.factors[2].m))[1] + trace((cov_x+q_m.factors[2].V)*e_w2)
#
#
#     ln_ro2        =   e_ln_pi2+0.5*e_ln_w2-dims/2.0*log(2.0*pi)-0.5*gausterm2
#
#     #Normalize message
#     #if statement to prevent division by zero
#     if exp(ln_ro1)+exp(ln_ro2)>tiny
#       outbound_dist.p = exp(ln_ro1)/(exp(ln_ro1)+exp(ln_ro2))
#     else
#       outbound_dist.p=0.5
#     end
#     println("end z")
#     return outbound_dist
# end

# VMP message towards i[:z]
# Multivariate Gaussian with multiple clusters
function variationalRule!{dims,n_factors}(node::GaussianMixtureNodePar,
                            ::Type{Val{5}},
                            outbound_dist::Categorical{n_factors},
                            q_pi::Dirichlet{n_factors},
                            q_m::PartitionedDistribution{MvGaussian{dims},n_factors},
                            q_w::PartitionedDistribution{Wishart{dims}, n_factors},
                            q_x::MvGaussian{dims},
                            ::Any)

    ensureParameters!(q_x, (:m, :V))

    a=zeros(n_factors)
    ln_ro=zeros(n_factors)

    k=collect(1:n_factors)
    sum_a=sum(q_pi.alpha[k])

    i=collect(1:dims)

    for k=1:n_factors
      ensureParameters!(q_m.factors[k], (:m, :V))

      e_ln_pi=digamma(q_pi.alpha[k])-digamma(sum_a)

      multidi=sum(digamma((q_w.factors[k].nu+1-i)/2))

      e_ln_w=  multidi+dims*log(2.0) +log(det(q_w.factors[k].V))

      e_w = q_w.factors[k].nu*q_w.factors[k].V

      gausterm = (transpose(q_x.m-q_m.factors[k].m)*e_w*(q_x.m-q_m.factors[k].m))[1] + trace((q_x.V+q_m.factors[k].V)*e_w)
      ln_ro[k]        =   e_ln_pi+0.5*e_ln_w-dims/2.0*log(2.0*pi)-0.5*gausterm

    end

    sum_ro=sum(exp(ln_ro))

    if sum_ro>tiny
      for k=1:n_factors
        outbound_dist.p[k]=exp(ln_ro[k])/sum_ro
      end
    else
      for k=1:n_factors
        outbound_dist.p[k]=1/n_factors
      end
    end

    return outbound_dist
end

# VMP message towards i[:z]
# Univariate gaussian with multiple clusters
function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{5}},
                            outbound_dist::Categorical{n_factors},
                            q_pi::Dirichlet{n_factors},
                            q_m::PartitionedDistribution{Gaussian,n_factors},
                            q_w::PartitionedDistribution{Gamma,n_factors},
                            q_x::Gaussian,
                            ::Any)


      ensureParameters!(q_x, (:m, :V))

      a=zeros(n_factors)
      ln_ro=zeros(n_factors)

      k=collect(1:n_factors)
      sum_a=sum(q_pi.alpha[k])



      for k=1:n_factors
        ensureParameters!(q_m.factors[k], (:m, :V))

        #calculating ln(ro1)
        e_ln_pi    =   digamma(q_pi.alpha[k])-digamma(sum_a)
        e_ln_w     =   digamma(q_w.factors[k].a)-log(q_w.factors[k].b)
        e_m_square =   q_x.m^2-2.0*q_x.m*q_m.factors[k].m+q_m.factors[k].V+q_m.factors[k].m^2+q_x.V
        ln_ro[k]      =   e_ln_pi+0.5*e_ln_w-0.5*log(2pi)-0.5*q_w.factors[k].a/q_w.factors[k].b*e_m_square

      end

      sum_ro=sum(exp(ln_ro))

      for k=1:n_factors
          if sum_ro> tiny
            outbound_dist.p[k]=exp(ln_ro[k])/sum_ro
          else
            outbound_dist.p[k]=1/n_factors
          end
      end



    return outbound_dist
end

# # VMP message towards i[:z]
# # Univariate gaussian with multiple clusters with mixture on x
# function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
#                             ::Type{Val{5}},
#                             outbound_dist::Categorical{n_factors},
#                             q_pi::Dirichlet{n_factors},
#                             q_m::PartitionedDistribution{Gaussian,n_factors},
#                             q_w::PartitionedDistribution{Gamma,n_factors},
#                             q_x::Mixture{Gaussian},
#                             ::Any)
#       e_x=0.
#       cov_x=0.
#       for k=1:n_factors
#         ensureParameters!(q_x.components[k], (:m, :V))
#         e_x=e_x+q_x.weights[k]*q_x.components[k].m
#         cov_x=cov_x+q_x.weights[k]*(q_x.components[k].m^2+q_x.components[k].V)
#       end
#       cov_x=cov_x-e_x^2
#
#       a=zeros(n_factors)
#       ln_ro=zeros(n_factors)
#
#       k=collect(1:n_factors)
#       sum_a=sum(q_pi.alpha[k])
#
#
#       for k=1:n_factors
#         ensureParameters!(q_m.factors[k], (:m, :V))
#
#         #calculating ln(ro1)
#         e_ln_pi    =   digamma(q_pi.alpha[k])-digamma(sum_a)
#         e_ln_w     =   digamma(q_w.factors[k].a)-log(q_w.factors[k].b)
#         e_m_square =   e_x^2-2.0*e_x*q_m.factors[k].m+q_m.factors[k].V+q_m.factors[k].m^2+cov_x
#         ln_ro[k]      =   e_ln_pi+0.5*e_ln_w-0.5*log(2pi)-0.5*q_w.factors[k].a/q_w.factors[k].b*e_m_square
#
#       end
#
#       sum_ro=sum(exp(ln_ro))
#
#       for k=1:n_factors
#           if sum_ro> tiny
#             outbound_dist.p[k]=exp(ln_ro[k])/sum_ro
#           else
#             outbound_dist.p[k]=1/n_factors
#           end
#       end
#
#
#
#     return outbound_dist
# end

# VMP message towards i[:x]
function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{4}},
                            outbound_dist::Gaussian,
                            q_pi::Beta,
                            q_m::PartitionedDistribution{Gaussian,n_factors},
                            q_w::PartitionedDistribution{Gamma,n_factors},
                            ::Any,
                            q_z::Bernoulli)



    V=pinv(q_z.p*q_w.factors[1].a/q_w.factors[1].b+(1.-q_z.p)*q_w.factors[2].a/q_w.factors[2].b)
    outbound_dist.m=(q_z.p*q_m.factors[1].m*q_w.factors[1].a/q_w.factors[1].b+(1.-q_z.p)*q_m.factors[2].m*q_w.factors[2].a/q_w.factors[2].b)*V
    outbound_dist.V=V
    outbound_dist.W=NaN
    outbound_dist.xi=NaN


    return outbound_dist
end

# # VMP message towards i[:x]
# function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
#                             ::Type{Val{4}},
#                             outbound_dist::Mixture{Gaussian},
#                             q_pi::Beta,
#                             q_m::PartitionedDistribution{Gaussian,n_factors},
#                             q_w::PartitionedDistribution{Gamma,n_factors},
#                             ::Any,
#                             q_z::Bernoulli)
#
#     ensureParameters!(q_m.factors[1],(:m,:V))
#     ensureParameters!(q_m.factors[2],(:m,:V))
#     resize!(outbound_dist, 2)
#
#     outbound_dist.weights[1]=exp(q_z.p*q_pi.a/(q_pi.a+q_pi.b))
#     outbound_dist.components[1].m=q_m.factors[1].m
#     outbound_dist.components[1].W=q_w.factors[1].a/q_w.factors[1].b*q_z.p
#     outbound_dist.components[1].xi=NaN
#     outbound_dist.components[1].V=NaN
#
#     outbound_dist.weights[2]=exp((1.-q_z.p)*q_pi.b/(q_pi.a+q_pi.b))
#     outbound_dist.components[2].m=q_m.factors[2].m
#     outbound_dist.components[2].W=q_w.factors[2].a/q_w.factors[2].b*(1.-q_z.p)
#     outbound_dist.components[2].xi=NaN
#     outbound_dist.components[2].V=NaN
#
#     return outbound_dist
# end



#
# VMP message towards i[:x]
function variationalRule!{dims,n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{4}},
                            outbound_dist::MvGaussian{dims},
                            q_pi::Beta,
                            q_m::PartitionedDistribution{MvGaussian{dims}, n_factors},
                            q_w::PartitionedDistribution{Wishart{dims},n_factors},
                            q_x::Any,
                            q_z::Bernoulli)

    lambda=(q_z.p*q_w.factors[1].nu*q_w.factors[1].V+(1.-q_z.p)*q_w.factors[2].nu*q_w.factors[2].V)
    outbound_dist.xi=(q_z.p*q_w.factors[1].nu*q_w.factors[1].V*q_m.factors[1].m+(1.-q_z.p)*q_w.factors[2].nu*q_w.factors[2].V*q_m.factors[2].m)
    outbound_dist.W=lambda
    invalidate!(outbound_dist.m)
    invalidate!(outbound_dist.V)

    return outbound_dist
end

# #
# # VMP message towards i[:x] with mixture on x
# function variationalRule!{dims,n_factors}(  node::GaussianMixtureNodePar,
#                             ::Type{Val{4}},
#                             outbound_dist::Mixture{MvGaussian{dims}},
#                             q_pi::Beta,
#                             q_m::PartitionedDistribution{MvGaussian{dims}, n_factors},
#                             q_w::PartitionedDistribution{Wishart{dims},n_factors},
#                             q_x::Any,
#                             q_z::Bernoulli)
#     println("start x")
#     ensureParameters!(q_m.factors[1],(:m,:V))
#     ensureParameters!(q_m.factors[2],(:m,:V))
#     resize!(outbound_dist, 2)
#     println("z ",q_z.p)
#     println("pi a ", q_pi.a)
#     println("pi b ", q_pi.b)
#     w1=exp(q_z.p*q_pi.a/(q_pi.a+q_pi.b))
#     outbound_dist.components[1].m=q_m.factors[1].m
#     outbound_dist.components[1].W=q_w.factors[1].V*q_w.factors[1].nu*q_z.p
#     invalidate!(outbound_dist.components[1].xi)
#     invalidate!(outbound_dist.components[1].V)
#
#     w2=exp((1.-q_z.p)*q_pi.b/(q_pi.a+q_pi.b))
#     outbound_dist.components[2].m=q_m.factors[2].m
#     outbound_dist.components[2].W=q_w.factors[1].V*q_w.factors[1].nu*(1.-q_z.p)
#     invalidate!(outbound_dist.components[2].xi)
#     invalidate!(outbound_dist.components[2].V)
#
#     outbound_dist.weights[1]=w1/(w1+w2)[1]
#     outbound_dist.weights[2]=w2/(w1+w2)[1]
#     println("weight 1 ", outbound_dist.weights[1])
#     println("weight 2 ", outbound_dist.weights[2])
#     println("end x")
#     return outbound_dist
# end


#
# VMP message towards i[:x]
function variationalRule!{dims,n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{4}},
                            outbound_dist::MvGaussian{dims},
                            q_pi::Dirichlet{n_factors},
                            q_m::PartitionedDistribution{MvGaussian{dims}, n_factors},
                            q_w::PartitionedDistribution{Wishart{dims},n_factors},
                            q_x::Any,
                            q_z::Categorical{n_factors})

    lambda=0.0
    xi=0.0
    for k=1:n_factors
        lambda=lambda+q_z.p[k]*q_w.factors[k].nu*q_w.factors[k].V
        xi=xi+q_z.p[k]*q_w.factors[k].nu*q_w.factors[k].V*q_m.factors[k].m
    end

    outbound_dist.xi=xi
    outbound_dist.W=lambda
    invalidate!(outbound_dist.m)
    invalidate!(outbound_dist.V)

    return outbound_dist
end

# VMP message towards i[:x]
function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
                            ::Type{Val{4}},
                            outbound_dist::Gaussian,
                            q_pi::Dirichlet{n_factors},
                            q_m::PartitionedDistribution{Gaussian,n_factors},
                            q_w::PartitionedDistribution{Gamma,n_factors},
                            ::Any,
                            q_z::Categorical{n_factors})

    lambda=0.0
    m=0.0
    for k=1:n_factors
        lambda=lambda+q_z.p[k]*q_w.factors[k].a/q_w.factors[k].b
        m=m+q_z.p[k]*q_m.factors[k].m*q_w.factors[k].a/q_w.factors[k].b

    end

    outbound_dist.V=pinv(lambda)
    outbound_dist.m=m*outbound_dist.V
    outbound_dist.W=NaN
    outbound_dist.xi=NaN

    return outbound_dist
end

# # VMP message towards i[:x] with mixture on x
# function variationalRule!{n_factors}(  node::GaussianMixtureNodePar,
#                             ::Type{Val{4}},
#                             outbound_dist::Mixture{Gaussian},
#                             q_pi::Dirichlet{n_factors},
#                             q_m::PartitionedDistribution{Gaussian,n_factors},
#                             q_w::PartitionedDistribution{Gamma,n_factors},
#                             ::Any,
#                             q_z::Categorical{n_factors})
#
#     ensureParameters!(q_m.factors[1],(:m,:V))
#
#     resize!(outbound_dist, n_factors)
#     k=collect(1:n_factors)
#     sum_a=sum(q_pi.alpha[k])
#     w=zeros(n_factors)
#
#     for k=1:n_factors
#       w[k]=exp(q_z.p[k]*q_pi.alpha[k]/(sum_a))
#       outbound_dist.components[k].m=q_m.factors[k].m
#       outbound_dist.components[k].W=q_w.factors[k].a/q_w.factors[k].b*q_z.p[k]
#       outbound_dist.components[k].xi=NaN
#       outbound_dist.components[k].V=NaN
#     end
#
#     sum_w=sum(w)
#     for k=1:n_factors
#       outbound_dist.weights[k]=w[k]/sum_w
#     end
#
#     return outbound_dist
# end
