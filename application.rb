require 'rubygems'
require 'opentox-ruby'

require 'superservice.rb'

post '/?' do
  LOGGER.info "creating supermodel #{params.inspect}"
  [:dataset_uri, :prediction_algorithm, :prediction_feature].each do |p|
    raise OpenTox::BadRequestError.new "#{p} missing" unless params[p].to_s.size>0
  end
  params[:training_dataset_uri] = params.delete("dataset_uri")
  task = OpenTox::Task.create( "Create Supermodel", url_for("/", :full) ) do |task|
    model = SuperService::SuperModel.create(params,@subjectid)
    model.build(task)
    LOGGER.info "supermodel created: #{model.uri}"
    model.uri
  end
  return_task(task)  
end

get '/?' do
  LOGGER.debug "get super-model list #{params.inspect}"
  uri_list = SuperService::SuperModel.all.sort.collect{|v| v.uri}.join("\n") + "\n"
  if request.env['HTTP_ACCEPT'] =~ /text\/html/
    description = 
      "A list of Super-Models.\n"+
      "Use the POST method to create a Super-Model."
    post_command = OpenTox::PostCommand.new request.url,"Create Super-Model"
    post_command.attributes << OpenTox::PostAttribute.new("dataset_uri")
    post_command.attributes << OpenTox::PostAttribute.new("prediction_feature")
    post_command.attributes << OpenTox::PostAttribute.new("prediction_algorithm")
    post_command.attributes << OpenTox::PostAttribute.new("prediction_algorithm_params",false,nil,"Params used for prediction model building, separate with ';', example: param1=v1;param2=v2")
    post_command.attributes << OpenTox::PostAttribute.new("ad_algorithm",false,nil)
    post_command.attributes << OpenTox::PostAttribute.new("ad_algorithm_params",false,nil,"Params used for ad model building, separate with ';', example: param1=v1;param2=v2")
    post_command.attributes << OpenTox::PostAttribute.new("create_bbrc_features",false,"false","Create bbrc-features using fminer webservice")
    content_type "text/html"
    OpenTox.text_to_html uri_list,@subjectid,nil,description,post_command
  else
    content_type "text/uri-list"
    uri_list
  end
end

get '/:id' do
  LOGGER.debug "get super-model with id "+params[:id].to_s
  model = SuperService::SuperModel.get(params[:id])
  raise OpenTox::NotFoundError.new "super-model '#{params[:id]}' not found." unless model
  model.subjectid = @subjectid
  case request.env['HTTP_ACCEPT'].to_s
  when "application/rdf+xml"
    content_type "application/rdf+xml"
    model.to_rdf
  when /text\/html/
    related_links =  
      "All Super-Models: "+url_for("/",:full)
    description = 
        "A Super-Model."
    content_type "text/html"
    model.inspect # to load all the stuff
    OpenTox.text_to_html({:metadata => model.metadata, :model => model}.to_yaml,@subjectid,related_links,description)
  else #/application\/x-yaml|\*\/\*/
    content_type "application/x-yaml"
    model.metadata.to_yaml
  end
end

get '/:id/predicted/:prop' do
  model = SuperService::SuperModel.get(params[:id])
  raise OpenTox::NotFoundError.new "super-model '#{params[:id]}' not found." unless model
  model.subjectid = @subjectid
  if params[:prop] == "value"
    feature = model.prediction_value_feature
  elsif params[:prop] == "confidence"
    feature = model.prediction_confidence_feature
  else
    raise OpenTox::BadRequestError.new "Unknown URI #{@uri}"
  end
  case @accept
  when /yaml/
    content_type "application/x-yaml"
    feature.metadata.to_yaml
  when /rdf/
    content_type "application/rdf+xml"
    feature.to_rdfxml
  when /html/
    content_type "text/html"
    OpenTox.text_to_html feature.metadata.to_yaml
  else
    raise OpenTox::BadRequestError.new "Unsupported MIME type '#{@accept}'"
  end
end

post '/:id' do
  LOGGER.info "apply super-model with id "+params[:id].to_s
  raise OpenTox::BadRequestError.new "dataset_uri missing" unless params[:dataset_uri].to_s.size>0
  model = SuperService::SuperModel.get(params[:id])
  raise OpenTox::NotFoundError.new "super-model '#{params[:id]}' not found." unless model
  model.subjectid = @subjectid
  task = OpenTox::Task.create( "Apply Super-Model", url_for("/", :full) ) do |task|
    res = model.apply(params[:dataset_uri],task)
    LOGGER.info "super-model prediction result: "+res.to_s
    res
  end
  return_task(task)  
end

delete '/:id' do
  model = SuperService::SuperModel.get(params[:id])
  raise OpenTox::NotFoundError.new "super-model '#{params[:id]}' not found." unless model
  LOGGER.info "deleting superservice model #{model.uri}"
  content_type "text/plain"
  model.delete_model
end


delete '/fminer_large_results' do
  SuperService::FminerWrapper.delete_large_results
end



  
