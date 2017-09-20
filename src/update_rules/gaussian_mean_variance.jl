@sumProductRule(:node_type     => GaussianMeanVariance,
                :outbound_type => Message{Gaussian},
                :inbound_types => (Message{PointMass}, Message{PointMass}, Void),
                :name          => SPGaussianMeanVariancePPV)

@sumProductRule(:node_type     => GaussianMeanVariance,
                :outbound_type => Message{Gaussian},
                :inbound_types => (Void, Message{PointMass}, Message{PointMass}),
                :name          => SPGaussianMeanVarianceVPP)