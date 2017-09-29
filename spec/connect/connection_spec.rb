require 'spec_helper'

describe SUSE::Connect::Connection do
  subject { SUSE::Connect::Connection }

  describe '.new' do
    let :secure_connection do
      subject.new('https://example.com')
    end

    it 'stores http object' do
      expect(secure_connection.http).to be_kind_of Net::HTTP
    end

    it 'parse passed endpoint to http port and host' do
      expect(secure_connection.http.port).to eq 443
      expect(secure_connection.http.address).to eq 'example.com'
    end

    context :proxy_detected do
      before do
        allow_any_instance_of(Net::HTTP).to receive(:proxy?).and_return(true)
        allow_any_instance_of(SUSE::Toolkit::CurlrcDotfile).to receive(:username).and_return('robot')
        allow_any_instance_of(SUSE::Toolkit::CurlrcDotfile).to receive(:password).and_return('gobot')
      end

      it 'sets proxy_user to curlrc extracted username' do
        expect(subject.new('https://example.com').http.proxy_user).to eq 'robot'
      end

      it 'sets proxy_pass to curlrc extracted password' do
        expect(subject.new('https://example.com').http.proxy_pass).to eq 'gobot'
      end
    end

    context :default_values do
      it 'set ssl to true by default' do
        expect(secure_connection.http.use_ssl?).to be true
      end

      it 'set insecure to false by default' do
        expect(secure_connection.http.verify_mode).to eq OpenSSL::SSL::VERIFY_PEER
      end

      it 'sets a default verify_callack' do
        expect(secure_connection.http.verify_callback).to be_a(Proc)
      end

      it 'logs the error in the default verify_callack and returns failure' do
        context = double
        expect(context).to receive(:error_string).and_return('ERROR')
        allow(context).to receive_message_chain(:current_cert, :issuer).and_return('ISSUER')
        allow(context).to receive_message_chain(:current_cert, :subject).and_return('SUBJECT')

        logger = double
        expect(logger).to receive(:error) do |msg|
          msg.match(/(ERROR|ISSUER|SUBJECT)/)
        end.exactly(3).times

        allow(secure_connection).to receive(:log).and_return(logger)

        # call the default callbak
        expect(secure_connection.http.verify_callback.call(false, context)).to be false
      end
    end

    context :passed_options do
      # just an empty lambda function
      let(:callback) { ->(_p1, _p2) {} }

      let :secure_connection do
        subject.new('https://example.com', :insecure => true, :verify_callback => callback)
      end

      it 'set ssl to true by default' do
        expect(secure_connection.http.use_ssl?).to be true
      end

      it 'set insecure to false by default' do
        expect(secure_connection.http.verify_mode).to eq OpenSSL::SSL::VERIFY_NONE
      end

      it 'sets the provided verify_callback' do
        expect(secure_connection.http.verify_callback).to be callback
      end
    end
  end

  describe '?json_request' do
    let :connection do
      subject.new('https://leg')
    end

    before do
      allow(connection.http).to receive(:request).and_return(OpenStruct.new(:body => 'bodyofostruct'))
      allow(JSON).to receive_messages(:parse => { '1' => '2' })
    end

    context :get_request do
      it 'takes Net::HTTP::Get class to build request' do
        expect(Net::HTTP::Get).to receive(:new).and_call_original
        connection.send(:json_request, :get, '/api/v1/megusta')
      end
    end

    context :post_request do
      it 'takes Net::HTTP::Post class to build request' do
        expect(Net::HTTP::Post).to receive(:new).and_call_original
        connection.send(:json_request, :post, '/api/v1/megusta')
      end
    end

    context :put_request do
      it 'takes Net::HTTP::Put class to build request' do
        expect(Net::HTTP::Put).to receive(:new).and_call_original
        connection.send(:json_request, :put, '/api/v1/megusta')
      end
    end

    context :delete_request do
      it 'takes Net::HTTP::Delete class to build request' do
        expect(Net::HTTP::Delete).to receive(:new).and_call_original
        connection.send(:json_request, :delete, '/api/v1/megusta')
      end
    end
  end

  context 'network error' do
    let :connection do
      subject.new('https://leg')
    end

    it 'provides a user-friendly error message' do
      expect(connection.http).to receive(:request).and_raise(Zlib::BufError)
      expect { connection.send(:json_request, :get, '/api/v1/megusta') }.to \
        raise_error(SUSE::Connect::NetworkError, 'Check your network connection and try again. If it keeps failing, report a bug.')
    end
  end

  describe '#post' do
    let :connection do
      subject.new('https://example.com')
    end

    before do
      stub_request(:post, 'https://example.com/api/v1/test')
        .with(:body => '', :headers => { 'Authorization' => 'Token token=zulu' })
        .to_return(:status => 200, :body => '{}', :headers => {})
    end

    it 'hits requested endpoint with parametrized request' do
      result = connection.post('/api/v1/test', :auth => 'Token token=zulu')
      expect(result.body).to eq({})
      expect(result.code).to eq 200
    end

    it 'sends Accept-Language header with specified language' do
      stub_request(:post, 'https://example.com/api/v1/test')
        .with(:body => '', :headers => { 'Authorization' => 'Token token=zulu', 'Accept-Language' => 'blabla' })
        .to_return(:status => 200, :body => '{}', :headers => {})

      connection = subject.new('https://example.com', :language => 'blabla')
      result = connection.post('/api/v1/test', :auth => 'Token token=zulu')
      expect(result.code).to eq 200
    end

    it 'sends Accept header with api versioning' do
      stub_request(:post, 'https://example.com/api/v1/test')
        .with(:body => '', :headers => { 'Authorization' => 'Token token=zulu', \
                                         'Accept' => 'application/json,application/vnd.scc.suse.com.v1+json' })
        .to_return(:status => 200, :body => '{}', :headers => {})

      connection = subject.new('https://example.com')
      result = connection.post('/api/v1/test', :auth => 'Token token=zulu')
      expect(result.code).to eq 200
    end

    it 'sends USER-AGENT header with SUSEConnect package version' do
      headers = {
        'Accept' => api_header_version,
        'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
        'Content-Type' => 'application/json',
        'User-Agent' => "SUSEConnect/#{SUSE::Connect::VERSION}"
      }

      stub_request(:post, 'https://example.com/api/v1/test')
        .with(headers: headers)
        .to_return(:status => 200, :body => '', :headers => {})

      connection = subject.new('https://example.com')
      result = connection.post('/api/v1/test')
      expect(result.code).to eq 200
    end

    it 'converts response into proper hash' do
      stub_request(:post, 'https://example.com/api/v1/test')
        .with(:body => '', :headers => { 'Authorization' => 'Token token=zulu' })
        .to_return(:status => 200, :body => "{\"keyyo\":\"vallue\"}", :headers => {})

      result = connection.post('/api/v1/test', :auth => 'Token token=zulu')
      expect(result.body).to eq('keyyo' => 'vallue')
      expect(result.code).to eq 200
    end

    it 'response includes API response headers' do
      api_version = SUSE::Connect::Api::VERSION

      stub_request(:post, 'https://example.com/api/v1/test')
        .with(:body => '', :headers => { 'Authorization' => 'Token token=zulu' })
        .to_return(:status => 200, :body => '{}', :headers => { 'scc-api-version' => api_version })

      connection = subject.new('https://example.com')
      result = connection.post('/api/v1/test', :auth => 'Token token=zulu')
      expect(result.headers['scc-api-version'].first).to eq api_version
      expect(result.code).to eq 200
    end

    it 'send params alongside with request' do
      stub_request(:post, 'https://example.com/api/v1/test')
        .with(:body => "{\"foo\":\"bar\",\"bar\":[1,3,4]}", :headers => { 'Authorization' => 'Token token=zulu' })
        .to_return(:status => 200, :body => "{\"keyyo\":\"vallue\"}", :headers => {})

      result = connection.post(
        '/api/v1/test',
        :auth => 'Token token=zulu',
        :params => { :foo => 'bar', :bar => [1, 3, 4] }
      )
      expect(result.body).to eq('keyyo' => 'vallue')
      expect(result.code).to eq 200
    end

    it 'accepts empty request body' do
      stub_request(:delete, 'https://example.com/api/v1/test')
        .with(:headers => { 'Authorization' => 'Token token=zulu' })
        .to_return(:status => 204, :body => nil, :headers => {})

      result = connection.delete(
        '/api/v1/test',
        :auth => 'Token token=zulu'
      )

      expect(result.body).to be_nil
      expect(result.code).to eq 204
    end

    it 'raise an ApiError if response code anything but 200' do
      stub_request(:post, 'https://example.com/api/v1/test')
        .with(
          :body => '',
          :headers => { 'Authorization' => 'Token token=zulu' }
        )
        .to_return(
          :status => 422,
          :body => '{}'
        )

      expect do
        connection.post(
          '/api/v1/test',
          :auth   => 'Token token=zulu',
          :params => {}
        )
      end.to raise_error ApiError
    end

    it 'raise an error with response from api if response code anything but 200' do
      parsed_output = OpenStruct.new(
        :code => 422,
        :body => { 'error' => 'These are not the droids you were looking for' }
      )

      expect(connection).to receive(:json_request).and_return parsed_output
      expect { connection.post('/api/v1/test', :auth   => 'Token token=zulu', :params => {}) }
        .to raise_error(ApiError) do |error|
        expect(error.code).to eq 422
        expect(error.response.body).to eq('error' => 'These are not the droids you were looking for')
      end
    end
  end
end
