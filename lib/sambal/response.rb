module Sambal
  class Response

    attr_reader :message

    def initialize(message, success)
      @message = message.split("\r\n").find{|l| l=~/^NT_/} || message
      @success = success
    end

    def success?
      @success
    end

    def failure?
      !success?
    end
  end
end
