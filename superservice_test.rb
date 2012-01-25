
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
      
      #multicell-call no feautres, 134 compounds
      dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/425254"
      prediction_feature = "http://apps.ideaconsult.net:8080/ambit2/feature/528321"
      prediction_algorithm = "http://apps.ideaconsult.net:8080/ambit2/algorithm/RandomForest"
      
#      #train
#      #dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/603204?pagesize=20&page=0"
#      #dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/603206?pagesize=10&page=0"
#      #prediction_feature = "http://apps.ideaconsult.net:8080/ambit2/feature/528321"
#      #ad_algorithm = "http://apps.ideaconsult.net:8080/ambit2/algorithm/leverage"
#      #ad_algorithm = "http://apps.ideaconsult.net:8080/ambit2/algorithm/distanceMahalanobis"
#      #ad_algorithm = "http://apps.ideaconsult.net:8080/ambit2/algorithm/pcaRanges"
#      #ad_algorithm = "http://apps.ideaconsult.net:8080/ambit2/algorithm/distanceEuclidean"
#      #ad_algorithm = "http://apps.ideaconsult.net:8080/ambit2/algorithm/RandomForest"
#      
#      params = {:dataset_uri=>dataset_uri, :prediction_feature => prediction_feature,
#        :prediction_algorithm => prediction_algorithm, :create_bbrc_features=>true}#, :ad_algorithm => ad_algorithm}
#      post "/",params
#      puts last_response.body
#      uri = last_response.body
#      rep = wait_for_task(uri)
#      puts rep
#     # puts OpenTox::RestClientWrapper.post("http://opentox.informatik.uni-freiburg.de/superservice",params)
      
#      #apply
#   #    dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/603204?pagesize=20&page=1"
##       dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/425254?max=10"
#       params = {:dataset_uri=>dataset_uri}
##       puts OpenTox::RestClientWrapper.post("http://opentox.informatik.uni-freiburg.de/superservice/4",params)
#       post "/18",params
#       puts last_response.body
#       uri = last_response.body
#       rep = wait_for_task(uri)
#       puts rep
      
            
#       #get rdf
#       get "/13",nil,'HTTP_ACCEPT' => "application/rdf+xml"
#       puts last_response.body
 
      #validate
      #dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/603206?pagesize=25&page=0"
      #test_dataset_uri = "http://apps.ideaconsult.net:8080/ambit2/dataset/603206?pagesize=25&page=1"
      #test_dataset_uri = dataset_uri
      #prediction_feature = "http://apps.ideaconsult.net:8080/ambit2/feature/528321"
      #prediction_feature = "http://apps.ideaconsult.net:8080/ambit2/feature/528402"
      #ad_algorithm = "http://apps.ideaconsult.net:8080/ambit2/algorithm/leverage"
      #ad_algorithm = "http://apps.ideaconsult.net:8080/ambit2/algorithm/distanceMahalanobis"
      #ad_algorithm = "http://apps.ideaconsult.net:8080/ambit2/algorithm/pcaRanges"
      #ad_algorithm = "http://apps.ideaconsult.net:8080/ambit2/algorithm/RandomForest"
      
      host = "http://local-ot/"
      #host = "http://opentox.informatik.uni-freiburg.de/"
      superservice="#{host}superservice"
      params = {:dataset_uri=>dataset_uri,#:training_dataset_uri=>dataset_uri, :test_dataset_uri=>test_dataset_uri,
        :prediction_feature => prediction_feature, :algorithm_uri=>superservice, 
        :algorithm_params=>"prediction_algorithm=#{prediction_algorithm};create_bbrc_features=true"} #;ad_algorithm=#{ad_algorithm}"}
      validation = "#{host}validation/training_test_split"
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

