
module SuperService
  class FminerWrapper < Ohm::Model
      
    attribute :date
    attribute :algorithm_uri
    attribute :prediction_feature
    attribute :relative_min_frequency
    attribute :feature_dataset_uri
    attribute :dataset_uri
    attribute :fminer_dataset_uri
    attribute :combined_dataset_uri
    
    index :algorithm_uri
    index :dataset_uri
    index :prediction_feature
    index :relative_min_frequency
    index :feature_dataset_uri    
    
    def self.create(params={})
      params[:date] = Time.new
      model = super params
      model
    end
    
    def self.delete_large_results
      FminerWrapper.all.each do |f|
        d = nil
        size = -1
        begin
          d = OpenTox::Dataset.find(f.fminer_dataset_uri)
          size = d.features.size
          LOGGER.debug "fminer results datsaet size: #{size}"
        rescue => ex
          LOGGER.warn "fminer result dataset not found: #{f.fminer_dataset_uri}"
        end
        if (d==nil || size>1000)
          LOGGER.warn "deleting fminer result"
          [f.fminer_dataset_uri, f.combined_dataset_uri].each do |dataset|
            begin
              OpenTox::RestClientWrapper.delete dataset if dataset
            rescue => ex
              LOGGER.warn "could not delete #{dataset}"
            end
          end 
          f.delete
        end
      end
    end
    
    def self.find_or_create_wrapper(algorithm_uri, algorithm_params)
      p = {}
      algorithm_params.keys.each do |k|
        p[k.to_s.to_sym] = algorithm_params[k]
      end
      p[:algorithm_uri] = algorithm_uri
      set = FminerWrapper.find(p)
      if set.size>0
        #set.collect.last.delete
        #puts "delete last fminer wrapper result"
        #exit
        set.collect.last
      else
        FminerWrapper.new(p)
      end
    end
    
    def self.mine_and_combine(algorithm_uri, algorithm_params, waiting_task=nil)
      f = find_or_create_wrapper(algorithm_uri,algorithm_params)
      if f.fminer_dataset_uri and f.combined_dataset_uri
        LOGGER.info "fminer features already mined #{f.combined_dataset_uri}"
        f
      else
        data_train = OpenTox::Dataset.find(f.dataset_uri)
        size = data_train.compounds.size
        f.fminer_dataset_uri = OpenTox::RestClientWrapper.post(algorithm_uri,
          { :dataset_uri => f.dataset_uri, 
            :prediction_feature => f.prediction_feature, 
            :min_frequency => [1,(size*f.relative_min_frequency.to_f).to_i].max,
            :max_num_features => 1000},
          {},waiting_task).to_s
        #merge feature and training dataset
        combined_data = OpenTox::Dataset.create
        data_feat = OpenTox::Dataset.find(f.fminer_dataset_uri)
        LOGGER.debug "num features mined by fminer: #{data_feat.features.size}"
        {data_train => [f.prediction_feature], data_feat => data_feat.features.keys}.each do |d,features|
          d.compounds.each{|c| combined_data.add_compound(c)}
          features.each do |feat|
            combined_data.add_feature(feat,d.features[feat])
            d.compounds.each do |c|
              d.data_entries[c][feat].each do |v|
                combined_data.add(c,feat,v,true)
              end if d.data_entries[c] and d.data_entries[c][feat]
            end
          end
        end
        combined_data.save
        f.combined_dataset_uri = combined_data.uri
        f.save
        f
      end
    end
    
    def self.match(algorithm_uri, algorithm_params, waiting_task=nil)
      f = find_or_create_wrapper(algorithm_uri, algorithm_params)
      if f.fminer_dataset_uri
        LOGGER.info "fminer features already matched #{f.fminer_dataset_uri}"
        f
      else
        f.fminer_dataset_uri = OpenTox::RestClientWrapper.post(algorithm_uri,
          { :dataset_uri => f.dataset_uri, 
          :feature_dataset_uri => f.feature_dataset_uri},
          {},waiting_task).to_s
        f.save
        f
      end
    end
  end 
end