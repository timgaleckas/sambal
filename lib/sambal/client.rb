# encoding: UTF-8

module Sambal
  class Client
    class NullStream
      def self.<<(o); self; end
    end

    attr_reader :connected, :current_dir

    SAMBA_PROMPT = /(.*)smb: (.*\\)>/m

    DEFAULT_OPTIONS = {
      domain: 'WORKGROUP',
      host: '127.0.0.1',
      share: '',
      user: 'guest',
      port: 445,
      connection_timeout: 30,
      timeout: 60,
      logger: Logger.new('/dev/null'),
      transcript: NullStream
    }

    def initialize(options={})
      options = DEFAULT_OPTIONS.merge(options)

      password = options[:password] ? "'#{options[:password]}'" : "--no-pass"
      command = "LC_CTYPE=en_US.UTF-8 TERM=xterm-256color smbclient \"//#{options[:host]}/#{options[:share]}\" #{password}"
      command += " -W \"#{options[:domain]}\" -U \"#{options[:user]}\""
      command += " -I #{options[:ip_address]}" if options[:ip_address]
      command += " -p #{options[:port]} -s /dev/null"

      @smbclient = Amberletters::Process.new(command,
                                             timeout: [options[:timeout], options[:connection_timeout]].max,
                                             logger: options[:logger],
                                             transcript: options[:transcript])

      @smbclient.start!

      connection_timeout_trigger = @smbclient.on(:timeout, options[:connection_timeout]) do
        raise 'Connection Timeout'
      end

      @smbclient.wait_for(:output, /(#{SAMBA_PROMPT}|NT_[A-Z_]*)/) do |trigger, process, match_data|
        raise match_data[1] if match_data[1] =~ /NT_/
        @smbclient.remove_trigger(connection_timeout_trigger)
      end

      @current_dir = '\\'
    end

    def ls(qualifier = '*', opts={})
      parse_files(ask_wrapped('ls', qualifier, opts))
    end

    def exists?(path, opts={})
      ls(path, opts).key? File.basename(path)
    end

    def cd(dir, opts={})
      response = ask("cd \"#{dir}\"", opts)
      if response =~ /NT_STATUS_OBJECT_NAME_NOT_FOUND/
        Response.new(response, false)
      else
        Response.new(response, true)
      end
    end

    def get(filename, output, opts={})
      file_context(filename) do |file|
        response = ask_wrapped 'get', [file, output], opts
        if response =~ /^getting\sfile.*$/
          Response.new(response, true)
        else
          Response.new(response, false)
        end
      end
    end

    def put(file, destination, opts={})
      response = ask_wrapped 'put', [file, destination], opts
      if response =~ /^putting\sfile.*$/
        Response.new(response, true)
      else
        Response.new(response, false)
      end
    end

    def put_content(content, destination, opts={})
      t = Tempfile.new("upload-smb-content-#{destination}")
      File.open(t.path, 'w') do |f|
        f << content
      end
      response = ask_wrapped 'put', [t.path, destination], opts
      if response =~ /^putting\sfile.*$/
        Response.new(response, true)
      else
        Response.new(response, false)
      end
    ensure
      t.close
    end

    def mkdir(directory, opts={})
      return Response.new('directory name is empty', false) if directory.strip.empty?
      response = ask_wrapped('mkdir', directory, opts)
      if response =~ /NT_STATUS_OBJECT_NAME_(INVALID|COLLISION)/
        Response.new(response, false)
      else
        Response.new(response, true)
      end
    end

    def rmdir(dir, opts={})
      response = cd dir, opts
      return response if response.failure?
      ls('*', opts).reject{|name, meta| %w(. ..).include?(name) }.each do |name, meta|
        response = case meta[:type]
                   when :file
                     del name, opts
                   when :directory
                     rmdir name, opts
                   else
                     raise 'whoops'
                   end
        return response if response.failure?
      end
      response = cd '..', opts
      return response if response.failure?
      response = ask_wrapped 'rmdir', dir, opts
      Response.new(response, true)
    end

    def del(filename, opts={})
      file_context(filename) do |file|
        response = ask_wrapped 'del', file, opts
        case
        when response =~ /NT_STATUS_NO_SUCH_FILE/
          Response.new(response, false)
        else
          Response.new(response, true)
        end
      end
    end

    def close
      @smbclient.kill!
    end

    private

    def ask(cmd, opts)
      @smbclient << "#{cmd}\n"
      response = nil
      _m = nil

      command_timeout = cmd_timeout(@smbclient, opts[:timeout])

      @smbclient.wait_for(:output, SAMBA_PROMPT) do |trigger, process, match_data|
        @smbclient.remove_trigger(command_timeout)
        @current_dir = match_data[2]
        response = match_data[1]
      end
      response
    end

    def cmd_timeout(client, timeout)
      return unless timeout
      raise 'Command Timeout must not exceed client timeout' if timeout > client.timeout
      client.on(:timeout, timeout) do |trigger, process|
        process.remove_trigger(trigger)
        raise 'Command Timeout'
      end
    end

    def ask_wrapped(cmd,filenames, opts)
      ask wrap_filenames(cmd,filenames), opts
    end

    def file_context(path)
      if (path_parts = path.split('/')).length>1
        file = path_parts.pop
        subdirs = path_parts.length
        dir = path_parts.join('/')
        cd dir
      else
        file = path
      end
      begin
        yield(file)
      ensure
        unless subdirs.nil?
          subdirs.times { cd '..' }
        end
      end
    end

    # Parse output from Client#ls
    # Returns Hash of file names with meta information
    def parse_files(str)
      listing = str.each_line.inject({}) do |files, line|
        line.strip!
        name = line[/.*(?=\b\s+[ABDHNRS]+\s+\d+)/]
        name ||= line[/^\.\.|^\./]

        if name
          line.sub!(name, '')
          line.strip!

          type = line[0] == "D" ? :directory : :file
          size = line[/\d+/]

          date = line[/(?<=\d  )\D.*$/]
          modified = (Time.parse(date) rescue "!!#{date}")

          files[name] = {
            type: type,
            size: size,
            modified: modified
          }
        end
        files
      end
      Hash[listing.sort]
    end

    def wrap_filenames(cmd,filenames)
      filenames = [filenames] unless filenames.kind_of?(Array)
      filenames.map!{ |filename| "\"#{filename}\"" }
      [cmd,filenames].flatten.join(' ')
    end
  end
end
