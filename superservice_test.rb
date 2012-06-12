
require "rubygems"
require "sinatra"
before {
  request.env['HTTP_HOST']="local-ot/superservice"
  request.env["REQUEST_URI"]=request.env["PATH_INFO"]
}

require "uri"
require "yaml"
ENV['RACK_ENV'] = 'production'
require 'application.rb'
require 'test/unit'
require 'rack/test'

LOGGER = OTLogger.new(STDOUT)
LOGGER.datetime_format = "%Y-%m-%d %H:%M:%S "
LOGGER.formatter = Logger::Formatter.new

if AA_SERVER
  #TEST_USER = "mgtest"
  #TEST_PW = "mgpasswd"
  TEST_USER = "guest"
  TEST_PW = "guest"
  SUBJECTID = OpenTox::Authorization.authenticate(TEST_USER,TEST_PW)
  raise "could not log in" unless SUBJECTID
  puts "logged in: "+SUBJECTID.to_s
else
  puts "AA disabled"
  SUBJECTID = nil
end

#Rack::Test::DEFAULT_HOST = "local-ot" #"/validation"
module Sinatra
  
  set :raise_errors, false
  set :show_exceptions, false

  module UrlForHelper
    BASE = "http://local-ot/superservice"
    def url_for url_fragment, mode=:path_only
      case mode
      when :path_only
        raise "not impl"
      when :full
      end
      "#{BASE}#{url_fragment}"
    end
  end
end


module Lib
  # test utitily, to be included rack unit tests
  module TestUtil
    
    def wait_for_task(uri)
      return TestUtil.wait_for_task(uri)
    end
    
    def self.wait_for_task(uri)
      if uri.task_uri?
        task = OpenTox::Task.find(uri)
        task.wait_for_completion
        #raise "task failed: "+uri.to_s+", error is:\n"+task.description if task.error?
        LOGGER.error "task failed :\n"+task.to_yaml if task.error?
        uri = task.result_uri
      end
      return uri
    end
  end
end


class SuperserviceTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include Lib::TestUtil
  
  def test_it
    begin
      
      prediction_algorithm = "http://local-ot/weka/RandomForest"
      ad_algorithm = "http://local-ot/appdomain/EuclideanDistance"
      
      #kazius 250 ob
      #dataset_uri = "http://local-ot/dataset/1623"
      #prediction_feature = "http://local-ot/dataset/1623/feature/endpoint"
      #0.3 - 0.7 split
      #train_dataset_uri = "http://local-ot/dataset/48761"
      #test_dataset_uri = "http://local-ot/dataset/48762"
      #      anti kazius 0.3 - 0.7 split      
      #train_dataset_uri = "http://local-ot/dataset/48846"
      #test_dataset_uri = "http://local-ot/dataset/48847"
      #      anti kazius 0.5 - 0.5 split      
      #train_dataset_uri = "http://local-ot/dataset/48874"
      #test_dataset_uri = "http://local-ot/dataset/48875"
      
      # #hamster no features
      #dataset_uri = "http://local-ot/dataset/8998"
      #train_dataset_uri = "http://local-ot/dataset/9006"
      #test_dataset_uri = "http://local-ot/dataset/9007"
      #prediction_feature = "http://local-ot/dataset/8998/feature/Hamster%20Carcinogenicity"
       
      #kazius 250 no features
      dataset_uri = "http://local-ot/dataset/9264"
      train_dataset_uri = "http://local-ot/dataset/9299"
      test_dataset_uri = "http://local-ot/dataset/9300"
      prediction_feature = "http://local-ot/dataset/9264/feature/endpoint"

#      #build
#      params = {:dataset_uri=>train_dataset_uri, :prediction_feature => prediction_feature,
#        :prediction_algorithm => prediction_algorithm, 
#        :create_bbrc_features=>true, :ad_algorithm => ad_algorithm}
#      post "/",params
#      puts last_response.body
#      uri = last_response.body
#      rep = wait_for_task(uri)
#      puts rep
#      id = rep.split("/").last
#      
#      #apply
#      params = {:dataset_uri=>test_dataset_uri}
#       #puts OpenTox::RestClientWrapper.post("http://local-ot/superservice/55",params)
#      post "/"+id,params
#      puts last_response.body
#      uri = last_response.body
#      rep = wait_for_task(uri)
#      puts rep
#      exit
             
      host = "http://local-ot/"
#      host = "http://opentox.informatik.uni-freiburg.de/"
      superservice="#{host}superservice"
      params = {#:dataset_uri=>dataset_uri,#
        :training_dataset_uri=>train_dataset_uri, :test_dataset_uri=>test_dataset_uri,
        :prediction_feature => prediction_feature, :algorithm_uri=>superservice, 
        :algorithm_params=>"prediction_algorithm=#{prediction_algorithm};create_bbrc_features=true;ad_algorithm=#{ad_algorithm}"}
      validation = "#{host}validation/training_test_validation"
      OpenTox::RestClientWrapper.post(validation, params)  
      
    rescue => ex
      rep = OpenTox::ErrorReport.create(ex, "")
      puts rep.to_yaml
    ensure
      #OpenTox::Authorization.logout(SUBJECTID) if AA_SERVER
    end
  end

  def app
    Sinatra::Application
  end
end

