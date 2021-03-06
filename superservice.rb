
require "fminer_wrapper.rb"

class String
  def to_boolean
    return true if self == true || self =~ (/(true|t|yes|y|1)$/i)
    return false if self == false || self.nil? || self =~ (/(false|f|no|n|0)$/i)
    raise ArgumentError.new("invalid value for Boolean: '#{self}'")
  end
end

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
    attribute :ad_algorithm_weighted
    attribute :ad_algorithm_params
    attribute :ad_model
    attribute :training_dataset_uri
    attribute :prediction_feature
    attribute :independent_features_yaml
    
    attribute :create_bbrc_features_string
    attribute :combined_training_dataset_uri
    attribute :feature_dataset_uri
    
    attribute :use_all_features_string
            
    attr_accessor :subjectid
    
    def delete_model
      begin
        OpenTox::RestClientWrapper.delete(prediction_model)
      rescue => ex
        LOGGER.warn "could not delete prediction model #{prediction_model}"
      end
      begin
        OpenTox::RestClientWrapper.delete(ad_model) if ad_model
      rescue => ex
        LOGGER.warn "could not delete prediction model #{ad_model}"
      end
      res = self.uri
      self.delete
      "deleted model #{res}\n"
    end
    
    def independent_features
      self.independent_features_yaml ? YAML.load(self.independent_features_yaml) : []
    end
    
    def independent_features=(array)
      self.independent_features_yaml = array.to_yaml
    end
    
    def create_bbrc_features
      self.create_bbrc_features_string =~ /true/
    end

    def relative_min_frequency
      if self.create_bbrc_features_string =~ /_rf/ 
        match = self.create_bbrc_features_string.scan(/_rf([0-9]+)/).join("")
        rf = "0.#{match}".to_f
        raise "register new relative-frequency (just to make sure this hack works): '#{rf}'" unless [0.025, 0.05].include?(rf)
        rf
      else
        0.05
      end
    end
    
    def min_chisq_significance
      if self.create_bbrc_features_string =~ /_cs/ 
        match = self.create_bbrc_features_string.scan(/_cs([0-9]+)/).join("")
        cs = "0.#{match}".to_f
        raise "register new chisq-significance (just to make sure this hack works): '#{cs}'" unless [0.85, 0.95].include?(cs)
        cs
      else
        0.95
      end      
    end
    
    def create_bbrc_features=(string)
      self.create_bbrc_features_string = string.to_s
    end
    
    def use_all_features
      self.use_all_features_string.to_boolean
    end

    def use_all_features=(bool)
      self.use_all_features_string = bool.to_s
    end
        
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
      params[:use_all_features] = true
      ["splat","captures"].each{|k| params.delete(k)}
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
        OWL.sameAs => predicted_variable,
      })
      feature
    end
    
    def prediction_confidence_feature
      if ad_algorithm
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
      else
        #feature = OpenTox::Feature.new File.join( uri, "predicted", "confidence")
        #feature.add_metadata( {
        #  RDF.type => OT.ModelPrediction,
        #  OT.hasSource => uri,
        #  DC.creator => uri,
        #  DC.title => "EuclDistanceAD confidence",
        #})
        #feature
      end
    end
    
    def metadata
      value_feature_uri = File.join( uri, "predicted", "value")
      features = [value_feature_uri]
      features << File.join( uri, "predicted", "confidence") if ad_algorithm
      { DC.title => 'Supermodel',
        DC.creator => creator, 
        OT.trainingDataset => training_dataset_uri, 
        OT.dependentVariables => prediction_feature,
        OT.predictedVariables => features,
        OT.independentVariables => independent_features,
        OT.featureDataset => feature_dataset_uri,
      }
    end
    
    def to_rdf
      s = OpenTox::Serializer::Owl.new
      #puts metadata.to_yaml
      s.add_model(uri,metadata)
      s.to_rdfxml
    end
    
    def build(waiting_task=nil)
      
      if create_bbrc_features
        algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc")
        algorithm_params = { :dataset_uri => self.training_dataset_uri, :prediction_feature => self.prediction_feature,
          :relative_min_frequency => relative_min_frequency(), :min_chisq_significance => min_chisq_significance() }
        LOGGER.debug "mining bbrc features #{algorithm_params.inspect}"
        f = FminerWrapper.mine_and_combine(algorithm_uri, algorithm_params)
        self.feature_dataset_uri = f.fminer_dataset_uri
        self.combined_training_dataset_uri = f.combined_dataset_uri
      else
        self.combined_training_dataset_uri = training_dataset_uri
        self.feature_dataset_uri = training_dataset_uri
      end
        
      algorithm = OpenTox::Algorithm::Generic.new(prediction_algorithm)
      params = { :dataset_uri => combined_training_dataset_uri, :prediction_feature => prediction_feature, :subjectid => subjectid }
      params.merge!(SuperService::split_params(prediction_algorithm_params)) if prediction_algorithm_params
      self.prediction_model = algorithm.run(params, OpenTox::SubTask.create(waiting_task, 33, 66))
        
      if self.use_all_features
        data_feat = OpenTox::Dataset.find(feature_dataset_uri) unless data_feat
        self.independent_features = data_feat.features.keys - [ prediction_feature ]
      else
        model = OpenTox::Model::Generic.find(self.prediction_model, subjectid)
        indep_features = []
        model.metadata[OT.independentVariables].each do |f|
          if combined_data.features.keys.include?(f)
            indep_features << f
          else  
            sameAs = OpenTox::Feature.find(f).metadata[OWL.sameAs]
            raise "feature:\n#{f}\nand sameAs:\n#{sameAs}\nnot found in feature list\n#{combined_data.features.keys.join("\n")}" if 
              sameAs==nil || !combined_data.features.keys.include?(sameAs)
            indep_features << sameAs
          end
        end
        self.independent_features = indep_features
      end
      

      if (ad_algorithm)
        algorithm = OpenTox::Algorithm::Generic.new(ad_algorithm)
        params = { :dataset_uri => combined_training_dataset_uri, :prediction_feature => prediction_feature, 
          :subjectid => subjectid} #, :independent_variables => independent_features.join("\n") }
        params[:weight_model_uri]=self.prediction_model if self.ad_algorithm_weighted=="true" 
        params.merge!(SuperService::split_params(ad_algorithm_params)) if ad_algorithm_params
        self.ad_model = algorithm.run(params, OpenTox::SubTask.create(waiting_task, 66, 100))
      end
      self.save
      raise unless self.valid?
    end
    
    def test_dataset_features(dataset_uri, waiting_task=nil)
      unless create_bbrc_features
        nil
      else
        algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc/match")
        algorithm_params = { :dataset_uri => dataset_uri, :feature_dataset_uri => self.feature_dataset_uri }
        LOGGER.debug "matching bbrc features #{algorithm_params.inspect}"
        f = FminerWrapper.match(algorithm_uri, algorithm_params)
        dataset_uri = f.fminer_dataset_uri
      end
    end
    
    def apply(dataset_uri, waiting_task=nil)
      
      if create_bbrc_features
        algorithm_uri = File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc/match")
        algorithm_params = { :dataset_uri => dataset_uri, :feature_dataset_uri => self.feature_dataset_uri }
        LOGGER.debug "matching bbrc features #{algorithm_params.inspect}"
        f = FminerWrapper.match(algorithm_uri, algorithm_params)
        dataset_uri = f.fminer_dataset_uri
      end
      
      #puts "num compounds in input dataset #{OpenTox::Dataset.find(dataset_uri).compounds.size}"
      
      model = OpenTox::Model::Generic.find(self.prediction_model, subjectid)
      prediction_dataset_uri = model.run( {:dataset_uri => dataset_uri, :subjectid => subjectid}, "text/uri-list",
        OpenTox::SubTask.create(waiting_task, 25, 50))
      predicted_variable = model.predicted_variable(subjectid)
      predicted_variable = prediction_feature if predicted_variable==nil
      prediction_dataset = OpenTox::Dataset.find(prediction_dataset_uri)
      raise "predicted_variable not found in prediction_dataset\n"+
          "predicted_variable '"+predicted_variable.to_s+"'\n"+
          "prediction_dataset: '"+prediction_dataset_uri.to_s+"'\n"+
          "available features are: "+prediction_dataset.features.inspect if 
            prediction_dataset.features.keys.index(predicted_variable)==nil and prediction_dataset.compounds.size>0
      value_feature_uri = File.join( uri, "predicted", "value")
      
      #puts "num compounds in prediction dataset #{prediction_dataset.compounds.size}"
      
      if ad_algorithm
        a_model = OpenTox::Model::Generic.find(self.ad_model, subjectid)
        a_prediction_dataset_uri = a_model.run( {:dataset_uri => dataset_uri, :subjectid => subjectid}, "text/uri-list",
          OpenTox::SubTask.create(waiting_task, 50, 75))
        a_predicted_variable = a_model.predicted_variable(subjectid)
        a_predicted_variable = prediction_feature if a_predicted_variable==nil
        a_prediction_dataset = OpenTox::Dataset.find(a_prediction_dataset_uri)
        raise "predicted_variable not found in prediction_dataset\n"+
            "predicted_variable '"+a_predicted_variable.to_s+"'\n"+
            "prediction_dataset: '"+a_prediction_dataset_uri.to_s+"'\n"+
            "available features are: "+a_prediction_dataset.features.inspect if 
              a_prediction_dataset.features.keys.index(a_predicted_variable)==nil and a_prediction_dataset.compounds.size>0
      else
        #data_train = OpenTox::Dataset.find(training_dataset_uri)
        #if (training_dataset_uri==feature_dataset_uri)
        #  data_feat = data_train
        #else
        #  data_feat = OpenTox::Dataset.find(feature_dataset_uri)
        #end 
        #euclAD = OpenTox::EuclDistanceAD.new(data_train,data_feat,independent_features)
        #data_test = OpenTox::Dataset.find(dataset_uri) unless data_test
      end
      confidence_feature_uri = File.join( uri, "predicted", "confidence")
      
      combined_dataset = OpenTox::Dataset.create(subjectid)
      combined_dataset.add_feature(value_feature_uri)
      combined_dataset.add_feature(confidence_feature_uri) if ad_algorithm
      prediction_dataset.compounds.each do |c|
        combined_dataset.add_compound(c)
        #puts "add #{c} #{predicted_variable} #{prediction_dataset.data_entries[c][predicted_variable]}"
        
        #raise "not 1 value for #{c} and #{predicted_variable} in #{prediction_dataset.uri} :"+
        #  " #{prediction_dataset.data_entries[c][predicted_variable].inspect} (class: #{prediction_dataset.data_entries[c][predicted_variable].class})" if 
        #    prediction_dataset.data_entries[c][predicted_variable].size!=1
        predicted = prediction_dataset.data_entries[c][predicted_variable]
        predicted.each do |v|
          combined_dataset.add(c,value_feature_uri,v,true)
        end
        
        if ad_algorithm
          #raise if a_prediction_dataset.data_entries[c][a_predicted_variable].size!=1
          predicted_ad = a_prediction_dataset.data_entries[c][a_predicted_variable]
          predicted_ad *= predicted.size if predicted.size>1 and predicted_ad.size==1
          raise unless predicted.size==predicted_ad.size
          predicted_ad.each do |v|
            combined_dataset.add(c,confidence_feature_uri,v,true)
          end
        else
          #combined_dataset.add(c,confidence_feature_uri,euclAD.ad(c,data_test))
        end 
      end
      combined_dataset.save(subjectid)
      
      #delete temporary resources
#      prediction_dataset.delete
      #a_prediction_dataset.delete if ad_algorithm
      #OpenTox::RestClientWrapper.delete dataset_uri if create_bbrc_features
      
      combined_dataset.uri        
    end

  end
  
  
end