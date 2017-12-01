# coding: UTF-8

ENV['PATH']=ENV['PATH']+':/usr/local/bin/:/usr/local/sbin'

require 'bundler/setup'

lib_path = File.expand_path('../lib', File.dirname(__FILE__))
$:.unshift(lib_path)

spec_lib_path = File.expand_path('./lib', File.dirname(__FILE__))
$:.unshift(spec_lib_path)

require 'sambal'
require 'test_server'
require 'rspec/expectations'

RSpec::Matchers.define :be_successful do
  match do |actual|
    actual.success? == true
  end
end

RSpec.configure do |config|
  # == Mock Framework
  #
  # If you prefer to use mocha, flexmock or RR, uncomment the appropriate line:
  #
  # config.mock_with :mocha
  # config.mock_with :flexmock
  # config.mock_with :rr
  config.mock_with :rspec

  ## perhaps this should be removed as well
  ## and done in Rakefile?
  config.color = true
  ## dont do this, do it in Rakefile instead
  #config.formatter = 'd'

  config.before(:suite) do
    $logger = Logger.new('/dev/null')
    $logger.level = Logger::DEBUG
    $test_server = Sambal::TestServer.new(logger: $logger)
    $test_server.start
  end

  config.after(:suite) do
    $test_server.stop! ## removes any created directories
  end
end
