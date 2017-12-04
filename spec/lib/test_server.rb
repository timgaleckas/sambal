# coding: UTF-8

require "erb"
require "fileutils"

module Sambal
  class TestServer

    class Document
      def initialize(template)
        @template = ERB.new(template)
      end

      def interpolate(replacements = {})
        object = Object.new
        object.instance_eval("def binding_for(#{replacements.keys.join(",")}) binding end")
        @template.result(object.binding_for(*replacements.values))
      end
    end

    attr_reader :port
    attr_reader :share_path
    attr_reader :root_path
    attr_reader :tmp_path
    attr_reader :private_dir
    attr_reader :cache_dir
    attr_reader :state_dir
    attr_reader :config_path
    attr_reader :share_name
    attr_reader :run_as
    attr_reader :host

    DEFAULT_OPTS = {
      share_name: 'sambal_test',
      run_as: ENV['USER'],
      logger: Logger.new('/dev/null')
    }

    def initialize(_opts={})
      opts = DEFAULT_OPTS.merge(_opts)

      @erb_path = "#{File.expand_path(File.dirname(__FILE__))}/smb.conf.erb"
      @host = "127.0.0.1" ## will always just be localhost
      @root_path = File.expand_path(File.dirname(File.dirname(File.dirname(__FILE__))))
      @tmp_path = "#{root_path}/spec_tmp"
      @share_path = "#{tmp_path}/share"
      @share_name = opts[:share_name]
      @config_path = "#{tmp_path}/smb.conf"
      @lock_path = "#{tmp_path}"
      @pid_dir = "#{tmp_path}"
      @cache_dir = "#{tmp_path}"
      @state_dir = "#{tmp_path}"
      @log_path = "#{tmp_path}"
      @private_dir = "#{tmp_path}"
      @ncalrpc_dir = "#{tmp_path}"
      @port = Random.new(Time.now.to_i).rand(2345..5678).to_i
      @run_as = opts[:run_as]
      @logger = opts[:logger]
      FileUtils.mkdir_p @share_path
      File.chmod 0777, @share_path
      write_config
    end

    def write_config
      File.open(@config_path, 'w') do |f|
        f << Document.new(IO.binread(@erb_path)).interpolate(samba_share: @share_path, local_user: @run_as, share_name: @share_name, log_path: @log_path, ncalrpc_dir: @ncalrpc_dir)
      end
    end

    def start
      command = "smbd -S -F -s #{@config_path} -p #{@port} " +
        "--option=\"lockdir\"=#{@lock_path} --option=\"pid directory\"=#{@pid_dir} " +
        "--option=\"private directory\"=#{@private_dir} --option=\"cache directory\"=#{@cache_dir} " +
        "--option=\"state directory\"=#{@state_dir}"
      @server = Amberletters::Process.new(command, transcript: @logger, logger: @logger)
      @server.start!
      @server.wait_for(:output, /ready to serve connections/)
    end

    def stop!
      @server.kill!
      FileUtils.rm_rf @tmp_path unless ENV.key?('KEEP_SMB_TMP')
    end
  end
end
