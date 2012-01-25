


module SuperService
  
  def self.split_params(params)
    res = {}
    params.split(";").each do |alg_params|
      alg_param = alg_params.split("=",2)
      raise OpenTox::BadRequestError.new "invalid algorithm param: '"+alg_params.to_s+"'" unless alg_param.size==2 or alg_param[0].to_s.size<1 or alg_param[1].to_s.size<1
      LOGGER.warn "algorihtm param contains empty space, encode? "+alg_param[1].to_s if alg_param[1] =~ /\s/
      res[alg_param[0].to_sym] = alg_param[1]
    end
    res
  end
  
  
  class SuperModel < Ohm::Model 
    
    attribute :date
    attribute :creator
    attribute :prediction_algorithm
    attribute :prediction_algorithm_params
    attribute :prediction_model
    attribute :ad_algorithm
    attribute :ad_algorithm_params
    attribute :ad_model
    attribute :training_dataset_uri
    attribute :prediction_feature
    
    attribute :orig_training_dataset_uri
    attribute :feature_dataset_uri
    
    @@create_features_with_fminer = true
    
    attr_accessor :subjectid
    
    def date
      return @created_at.to_s
    end
    
    def uri
      raise "no id" if self.id==nil
      $url_provider.url_for("/"+self.id.to_s, :full)
    end
    
    def save
      super
      OpenTox::Authorization.check_policy(uri, subjectid)
    end
    
    def self.create(params={}, subjectid=nil)
      params[:date] = Time.new
      params[:creator] = AA_SERVER ? OpenTox::Authorization.get_user(subjectid) : "unknown"
      model = super params
      model.subjectid = subjectid
      model
    end
    
    def prediction_value_feature
      model = OpenTox::Model::Generic.find(self.prediction_model, subjectid)
      predicted_variable =  model.predicted_variable(@subjectid)
      feature = OpenTox::Feature.new File.join( uri, "predicted", "value")
      feature.add_metadata( {
        RDF.type => OT.ModelPrediction,
        OT.hasSource => uri,
        DC.creator => uri,
        DC.title => "#{URI.decode(File.basename( prediction_feature ))} prediction",
        OWL.sameAs => predicted_variable
      })
      feature
    end

    def prediction_confidence_feature
      a_model = OpenTox::Model::Generic.find(self.ad_model, subjectid)
      predicted_variable = a_model.predicted_variable(@subjectid)
      feature = OpenTox::Feature.new File.join( uri, "predicted", "confidence")
      feature.add_metadata( {
        RDF.type => OT.ModelPrediction,
        OT.hasSource => uri,
        DC.creator => uri,
        DC.title => "#{URI.decode(File.basename( prediction_feature ))} confidence",
        OWL.sameAs => predicted_variable
      })
      feature
    end
    
    def metadata
      value_feature_uri = File.join( uri, "predicted", "value")
      confidence_feature_uri = File.join( uri, "predicted", "confidence")
      { DC.title => 'Supermodel',
        DC.creator => creator, 
        OT.trainingDataset => training_dataset_uri, 
        OT.dependentVariables => prediction_feature,
        OT.predictedVariables => [value_feature_uri, confidence_feature_uri]}
    end
    
    def to_rdf
      s = OpenTox::Serializer::Owl.new
      puts metadata.to_yaml
      s.add_model(uri,metadata)
      s.to_rdfxml
    end
    
    def build(waiting_task=nil)
      
      if @@create_features_with_fminer
        
        self.orig_training_dataset_uri = training_dataset_uri
        fminer = File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
        data_train = OpenTox::Dataset.find(training_dataset_uri)
        size = data_train.compounds.size
        self.feature_dataset_uri = OpenTox::RestClientWrapper.post(fminer,
          {:dataset_uri => training_dataset_uri, :prediction_feature => prediction_feature, :min_frequency => (size*0.05).to_i})
        #merge feature and training dataset
        data = OpenTox::Dataset.create
        data_feat = OpenTox::Dataset.find(feature_dataset_uri)
        [data_train, data_feat].each do |d|
          d.compounds.each{|c| data.add_compound(c)}
          d.features.each do |f,m|
            data.add_feature(f,m)
            d.compounds.each do |c|
              d.data_entries[c][f].each do |v|
                data.add(c,f,v)
              end if d.data_entries[c][f]
            end
          end
        end
        data.save
        self.training_dataset_uri = data.uri
      end
        
      algorithm = OpenTox::Algorithm::Generic.new(prediction_algorithm)
      params = { :dataset_uri => training_dataset_uri, :prediction_feature => prediction_feature, :subjectid => subjectid }
      params.merge!(split_params(prediction_algorithm_params)) if prediction_algorithm_params
      self.prediction_model = algorithm.run(params, OpenTox::SubTask.create(waiting_task, 0, 50))
      algorithm = OpenTox::Algorithm::Generic.new(ad_algorithm)
      params = { :dataset_uri => training_dataset_uri, :prediction_feature => prediction_feature, :subjectid => subjectid }
      params.merge!(split_params(ad_algorithm_params)) if ad_algorithm_params
      self.ad_model = algorithm.run(params, OpenTox::SubTask.create(waiting_task, 50, 100))
      self.save
      raise unless self.valid?
    end
    
    def apply(dataset_uri, waiting_task=nil)
      
      if @@create_features_with_fminer
        data_test = OpenTox::Dataset.find(dataset_uri)
        raise "not found: #{dataset_uri}" unless data_test
        fminer = File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
        test_feature_dataset_uri = OpenTox::RestClientWrapper.post(fminer,
                  {:feature_dataset_uri => self.feature_dataset_uri, :dataset_uri => dataset_uri})
        #merge feature and training dataset
        data = OpenTox::Dataset.create
        data_feat = OpenTox::Dataset.find(test_feature_dataset_uri)
        raise "not found: #{test_feature_dataset_uri}" unless data_feat
        [data_test, data_feat].each do |d|
          d.compounds.each{|c| data.add_compound(c)}
          d.features.each do |f,m|
            data.add_feature(f,m)
            d.compounds.each do |c|
              d.data_entries[c][f].each do |v|
                data.add(c,f,v)
              end if d.data_entries[c][f]
            end
          end
        end
        data.save
        dataset_uri = data.uri
      end
      
      model = OpenTox::Model::Generic.find(self.prediction_model, subjectid)
      prediction_dataset_uri = model.run( {:dataset_uri => dataset_uri, :subjectid => subjectid}, "text/uri-list",
        OpenTox::SubTask.create(waiting_task, 0, 33))
      predicted_variable = model.predicted_variable(subjectid)
      predicted_variable = prediction_feature if predicted_variable==nil
      prediction_dataset = OpenTox::Dataset.find(prediction_dataset_uri)
      raise "predicted_variable not found in prediction_dataset\n"+
          "predicted_variable '"+predicted_variable.to_s+"'\n"+
          "prediction_dataset: '"+prediction_dataset_uri.to_s+"'\n"+
          "available features are: "+prediction_dataset.features.inspect if 
            prediction_dataset.features.keys.index(predicted_variable)==nil and prediction_dataset.compounds.size>0
            
      a_model = OpenTox::Model::Generic.find(self.ad_model, subjectid)
      a_prediction_dataset_uri = a_model.run( {:dataset_uri => dataset_uri, :subjectid => subjectid}, "text/uri-list",
        OpenTox::SubTask.create(waiting_task, 33, 66))
      a_predicted_variable = a_model.predicted_variable(subjectid)
      a_predicted_variable = prediction_feature if a_predicted_variable==nil
      a_prediction_dataset = OpenTox::Dataset.find(a_prediction_dataset_uri)
      raise "predicted_variable not found in prediction_dataset\n"+
          "predicted_variable '"+a_predicted_variable.to_s+"'\n"+
          "prediction_dataset: '"+a_prediction_dataset_uri.to_s+"'\n"+
          "available features are: "+a_prediction_dataset.features.inspect if 
            a_prediction_dataset.features.keys.index(a_predicted_variable)==nil and a_prediction_dataset.compounds.size>0

      value_feature_uri = File.join( uri, "predicted", "value")
      confidence_feature_uri = File.join( uri, "predicted", "confidence")
                        
      combined_dataset = OpenTox::Dataset.create(subjectid)
      combined_dataset.add_feature(value_feature_uri)
      combined_dataset.add_feature(confidence_feature_uri)
      prediction_dataset.compounds.each do |c|
        combined_dataset.add_compound(c)
        #puts "add #{c} #{predicted_variable} #{prediction_dataset.data_entries[c][predicted_variable]}"
        
        raise if prediction_dataset.data_entries[c][predicted_variable].size!=1
        combined_dataset.add(c,value_feature_uri,prediction_dataset.data_entries[c][predicted_variable][0])
        
        combined_dataset.add(c,confidence_feature_uri,rand) #a_prediction_dataset.data_entries[c][a_predicted_variable])
      end
      combined_dataset.save(subjectid)
      combined_dataset.uri        
    end

  end
  
  
end