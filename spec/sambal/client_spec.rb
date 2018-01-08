# coding: UTF-8

require 'spec_helper'
require 'tempfile'

describe Sambal::Client do
  before(:each) do
    FileUtils.rm_rf($test_server.share_path)
    FileUtils.mkdir_p($test_server.share_path)
    sleep 0.1
  end

  after(:each) do
    @samba_client && @samba_client.close
  end

  let(:file_to_upload) do
    t = Tempfile.new('sambal-smbclient-spec')
    File.open(t.path,'w') do |f|
      f << "Hello from specs"
    end
    t
  end

  let(:samba_opts) do
    {
      host: $test_server.host,
      port: $test_server.port,
      share: $test_server.share_name,
      logger: $test_server.logger,
      transcript: $test_server.transcript,
      connection_timeout: 1
    }
  end

  let(:samba_client) { @samba_client=described_class.new(samba_opts) }

  def create_files(files)
    files.each do |file|
      file_parts = Pathname.new(file).split
      file_parts[0..-2].each{|d| samba_client.mkdir(d.to_s); samba_client.cd(d.to_s)}
      samba_client.put_content('test', file_parts.last.to_s)
      samba_client.cd("/")
    end
  end

  describe 'new' do
    it 'should raise an exception if the port is unreachable' do
      expect{ described_class.new(samba_opts.merge(port: $test_server.port + 1)) }.to raise_error('NT_STATUS_CONNECTION_REFUSED')
    end
    it 'should raise an exception if the port is unreachable' do
      expect{ described_class.new(samba_opts.merge(host: 'example.com')) }.to raise_error('Connection Timeout')
    end
    it 'should raise an exception if the share is unreachable' do
      expect{ described_class.new(samba_opts.merge(share: 'not_here')) }.to raise_error('NT_STATUS_BAD_NETWORK_NAME')
    end
  end

  describe 'ls' do
    it "should list files with spaces in their names" do
      directories_with_spaces = [
        'my dir with spaces in name',
        'my dir with   consecutive spaces in name'
      ]

      directories_with_spaces.each{|d| samba_client.mkdir(d) }

      result = samba_client.ls

      directories_with_spaces.each{|d| expect(result).to have_key(d) }
    end

    it "should list files on an smb server" do
      files = %w(testfile1.txt testfile2.txt testfile3.txt)
      create_files(files)

      result = samba_client.ls

      files.each{|f| expect(result).to have_key(f) }
    end

    it "should list files using a wildcard on an smb server" do
      files = %w(testfile1.txt testfile2.txt testfile3.txt testfile.exe)
      create_files(files)

      result = samba_client.ls '*.txt'
      expect(result).to have_key('testfile1.txt')
      expect(result).to have_key('testfile2.txt')
      expect(result).to_not have_key('testfile.exe')
    end
  end

  describe 'exists?' do
    it "returns true if a file or directory exists at a given path" do
      files = %w(testfile.txt subdir/testfile.txt)
      files.each{|file| expect(samba_client.exists?(file)).to eq(false) }
      create_files(files)
      expect(samba_client.exists?('subdir')).to eq(true)
      files.each{|file| expect(samba_client.exists?(file)).to eq(true) }
    end

    it "returns false if nothing exists at a given path" do
      %w(non_existing_file.txt non_existing_directory non_existing_directory/non_existing_file.txt).each do |f|
        expect(samba_client.exists?(f)).to eq(false)
      end
    end
  end

  describe 'mkdir' do
    it 'should create a new directory' do
      ['test', 'test test'].each do |dir|
        result = samba_client.mkdir(dir)
        expect(result).to be_successful
        expect(samba_client.ls).to have_key(dir)
      end
    end

    it 'should not create an invalid directory' do
      result = samba_client.mkdir('**')
      expect(result).to_not be_successful
    end

    it 'should not overwrite an existing directory' do
      expect(samba_client.mkdir('test')).to be_successful
      expect(samba_client.ls).to have_key('test')
      expect(samba_client.mkdir('test')).to_not be_successful
    end

    it 'should handle empty directory names' do
      expect(samba_client.mkdir('')).to_not be_successful
      expect(samba_client.mkdir('   ')).to_not be_successful
    end
  end

  it "should get files from an smb server" do
    files = [
      'testfile.txt',
      'subdir/testfile.txt',
      'space dir/testfile.txt',
      'subdir/space file.txt'
    ]

    create_files(files)

    files.each do |f|
      expect(samba_client.get(f, "/tmp/sambal_spec_testfile.txt")).to be_successful
      expect(File.exists?("/tmp/sambal_spec_testfile.txt")).to eq true
      expect(File.read("/tmp/sambal_spec_testfile.txt")).to eq 'test'
    end
  end

  it "should not be successful when getting a file from an smb server fails" do
    result = samba_client.get("non_existant_file.txt", "/tmp/sambal_spec_non_existant_file.txt")
    expect(result).to_not be_successful
    expect(result.message).to match(/^NT_.*$/)
    expect(result.message.split("\n").size).to eq 1
    expect(File.exists?("/tmp/sambal_spec_non_existant_file.txt")).to eq false
  end

  it "should upload files to an smb server" do
    expect(samba_client.ls).to_not have_key("uploaded_file.txt")
    expect(samba_client.put(file_to_upload.path, 'uploaded_file.txt')).to be_successful
    expect(samba_client.ls).to have_key("uploaded_file.txt")
  end

  it "should upload content to an smb server" do
    expect(samba_client.ls).to_not have_key("content_uploaded_file.txt")
    expect(samba_client.put_content("Content upload", 'content_uploaded_file.txt')).to be_successful
    expect(samba_client.ls).to have_key("content_uploaded_file.txt")
  end

  it "should delete files on an smb server" do
    create_files(%w(testfile.txt))
    expect(samba_client.del('testfile.txt')).to be_successful
    expect(samba_client.ls).to_not have_key('testfile.txt')
  end

  it "should not be successful when deleting a file from an smb server fails" do
    result = samba_client.del("non_existant_file.txt")
    expect(result).to_not be_successful
    expect(result.message).to match(/^NT_.*$/)
    expect(result.message.split("\n").size).to eq 1
  end

  it "should switch directory on an smb server" do
    samba_client.mkdir('subdir')
    expect(samba_client.put_content("testing directories", 'dirtest.txt')).to be_successful ## a bit stupid, but now we can check that this isn't listed when we switch dirs
    expect(samba_client.ls).to have_key('dirtest.txt')
    expect(samba_client.cd('subdir')).to be_successful
    expect(samba_client.ls).to_not have_key('dirtest.txt')
    expect(samba_client.put_content("in subdir", 'intestdir.txt')).to be_successful
    expect(samba_client.ls).to have_key('intestdir.txt')
    expect(samba_client.cd('..')).to be_successful
    expect(samba_client.ls).to_not have_key('intestdir.txt')
    expect(samba_client.ls).to have_key('dirtest.txt')
  end

  it "should be support directories at and above the column limit" do
    10.upto(200).each do |number|
      expect(samba_client.mkdir("\\#{'x' * number}")).to be_successful
      expect(samba_client.cd("\\#{'x' * number}")).to be_successful
      expect(samba_client.cd("\\")).to be_successful
    end
  end

  it "should delete files in subdirectory while in a higher level directory" do
    create_files(%w(testdir/file_to_delete))
    expect(samba_client.del("testdir/file_to_delete")).to be_successful
    expect(samba_client.exists?('testdir/file_to_delete')).to be false
  end

  it "should recursively delete a directory" do
    create_files(%w(testdire/file_to_delete))
    expect(samba_client.rmdir("testdire")).to be_successful
    expect(samba_client.ls).to_not have_key("testdire")
  end

  it "should not be successful when recursively deleting a nonexistant directory" do
    expect(samba_client.rmdir("this_doesnt_exist")).to_not be_successful
  end

  it "should not be successful when command fails" do
    expect(samba_client.put("jhfahsf iasifasifh", "jsfijsf ijidjag")).to_not be_successful
  end

  it 'should create commands with one wrapped filename' do
    expect(samba_client.send(:wrap_filenames, 'cmd','file1')).to eq('cmd "file1"')
  end

  it 'should create commands with more than one wrapped filename' do
    expect(samba_client.send(:wrap_filenames, 'cmd',['file1','file2'])).to eq('cmd "file1" "file2"')
  end

  it 'should create commands with pathnames instead of strings' do
    expect(samba_client.send(:wrap_filenames,'cmd',[Pathname.new('file1'), Pathname.new('file2')])).to eq('cmd "file1" "file2"')
  end

end
