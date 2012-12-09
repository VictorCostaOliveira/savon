require "spec_helper"
require "integration/support/server"

describe "NewClient Options" do

  before :all do
    @server = IntegrationServer.run
  end

  after :all do
    @server.stop
  end

  context "global: endpoint" do
    it "sets the SOAP endpoint to use to allow requests without a WSDL document" do
      client = new_client(:endpoint => @server.url)
      response = client.call(:authenticate)
      expect(response.http.body).to eq("post")
    end
  end

  context "global :proxy" do
    it "sets the proxy server to use" do
      proxy_url = "http://example.com"
      client = new_client(:endpoint => @server.url, :proxy => proxy_url)

      # TODO: find a way to integration test this [dh, 2012-12-08]
      HTTPI::Request.any_instance.expects(:proxy=).with(proxy_url)

      response = client.call(:authenticate)
    end
  end

  context "global :headers" do
    it "sets the HTTP headers for the next request" do
      repeat_header_url = @server.url(:repeat_header)
      client = new_client(:endpoint => repeat_header_url, :headers => { "Repeat-Header" => "savon" })

      response = client.call(:authenticate)
      expect(response.http.body).to eq("savon")
    end
  end

  context "global :open_timeout" do
    it "makes the client timeout after n seconds" do
      non_routable_ip = "http://10.255.255.1"
      client = new_client(:endpoint => non_routable_ip, :open_timeout => 1)

      # TODO: make HTTPI tag timeout errors, then depend on HTTPI::TimeoutError instead of a specific client error [dh, 2012-12-08]
      expect { client.call(:authenticate) }.to raise_error(HTTPClient::ConnectTimeoutError)
    end
  end

  context "global :read_timeout" do
    it "makes the client timeout after n seconds" do
      timeout_url = @server.url(:timeout)
      client = new_client(:endpoint => timeout_url, :open_timeout => 1, :read_timeout => 1)

      expect { client.call(:authenticate) }.to raise_error(HTTPClient::ReceiveTimeoutError)
    end
  end

  context "global :encoding" do
    it "changes the XML instruction" do
      client = new_client(:endpoint => @server.url(:repeat), :encoding => "UTF-16")
      response = client.call(:authenticate)

      expect(response.http.body).to match(/<\?xml version="1\.0" encoding="UTF-16"\?>/)
    end

    it "changes the Content-Type header" do
      inspect_header_url = @server.url(:inspect_header)
      client = new_client(:endpoint => inspect_header_url, :encoding => "UTF-16",
                          :headers => { "Inspect" => "CONTENT_TYPE" })

      response = client.call(:authenticate)
      expect(response.http.body).to eq("text/xml;charset=UTF-16")
    end
  end

  context "global :element_form_default" do
    it "specifies whether elements should be :qualified or :unqualified" do
      # qualified
      client = new_client(:endpoint => @server.url(:repeat), :element_form_default => :qualified)

      response = client.call(:authenticate, :message => { :user => "luke", :password => "secret" })
      expect(response.http.body).to include("<ins0:user>luke</ins0:user><ins0:password>secret</ins0:password>")

      # unqualified
      client = new_client(:endpoint => @server.url(:repeat), :element_form_default => :unqualified)

      response = client.call(:authenticate, :message => { :user => "lea", :password => "top-secret" })
      expect(response.http.body).to include("<user>lea</user><password>top-secret</password>")
    end

    it "allows overwriting the SOAPAction HTTP header" do
      inspect_header_url = @server.url(:inspect_header)
      client = new_client(:endpoint => inspect_header_url,
                          :headers => { "Inspect" => "HTTP_SOAPACTION" })

      response = client.call(:authenticate)
      expect(response.http.body).to eq('"authenticate"')
    end
  end

  context "global :env_namespace" do
    it "when set, replaces the default namespace identifier for the SOAP envelope" do
      client = new_client(:endpoint => @server.url(:repeat), :env_namespace => "soapenv")
      response = client.call(:authenticate)

      expect(response.http.body).to include("<soapenv:Envelope")
    end

    it "when not set, Savon defaults to use :env as the namespace identifier for the SOAP envelope" do
      client = new_client(:endpoint => @server.url(:repeat))
      response = client.call(:authenticate)

      expect(response.http.body).to include("<env:Envelope")
    end
  end

  context "global :soap_version" do
    it "it uses the correct SOAP 1.1 namespace" do
      client = new_client(:endpoint => @server.url(:repeat), :soap_version => 1)
      response = client.call(:authenticate)

      expect(response.http.body).to include('xmlns:env="http://schemas.xmlsoap.org/soap/envelope/"')
    end

    it "it uses the correct SOAP 1.2 namespace" do
      client = new_client(:endpoint => @server.url(:repeat), :soap_version => 2)
      response = client.call(:authenticate)

      expect(response.http.body).to include('xmlns:env="http://www.w3.org/2003/05/soap-envelope"')
    end
  end

  context "global: raise_errors" do
    it "when true, instructs Savon to raise SOAP fault errors" do
      client = new_client(:endpoint => @server.url(:repeat), :raise_errors => true)

      expect { client.call(:authenticate, :xml => Fixture.response(:soap_fault)) }.
        to raise_error(Savon::SOAP::Fault)
    end

    it "when true, instructs Savon to raise HTTP errors" do
      client = new_client(:endpoint => @server.url(404), :raise_errors => true)
      expect { client.call(:authenticate) }.to raise_error(Savon::HTTP::Error)
    end

    it "when false, instructs Savon to not raise SOAP fault errors" do
      client = new_client(:endpoint => @server.url(:repeat), :raise_errors => false)
      response = client.call(:authenticate, :xml => Fixture.response(:soap_fault))

      expect(response).to_not be_successful
      expect(response).to be_a_soap_fault
    end

    it "when false, instructs Savon to not raise HTTP errors" do
      client = new_client(:endpoint => @server.url(404), :raise_errors => false)
      response = client.call(:authenticate)

      expect(response).to_not be_successful
      expect(response).to be_a_http_error
    end
  end

  context "global :logger" do
    it "defaults to an instance of Savon::Logger" do
      logger = new_client.options.logger
      expect(logger).to be_a(Savon::Logger)
    end

    it "can be replaced by an object that responds to #log" do
      duck_logger = Class.new {

        def self.logs
          @logs ||= []
        end

        def log(message, options = {})
          self.class.logs << message
        end

      }

      client = new_client(:logger => duck_logger.new)
      client.call(:authenticate)

      expect(duck_logger.logs).to include("SOAP request: http://example.com/validation/1.0/AuthenticationService")
    end
  end

  context "global :pretty_print_xml" do
    it "is a nice but expensive way to debug XML messages" do
      duck_logger = Class.new {

        def self.logs
          @logs ||= []
        end

        def log(message, options = {})
          # TODO: probably not the best way to test this, since it repeats the loggers behavior,
          #       but it's currently not possible to easily access the log messages. [dh, 2012-12-09]
          self.class.logs << Savon::LogMessage.new(message, [], options).to_s
        end

      }

      client = new_client(:logger => duck_logger.new, :pretty_print_xml => true)
      client.call(:authenticate)

      xml = unindent <<-xml
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <env:Envelope xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:tns=\"http://v1_0.ws.auth.order.example.com/\" xmlns:env=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:ins0=\"http://v1_0.ws.auth.order.example.com/\">
          <env:Body>
            <ins0:authenticate/>
          </env:Body>
        </env:Envelope>
       xml

      expect(duck_logger.logs[2]).to eq(xml)
    end

    def unindent(string)
      string.gsub(/^#{string[/\A\s*/]}/, '')
    end

  end

  context "request :message" do
    it "accepts a Hash which is passed to Gyoku to be converted to XML" do
      repeat_url = @server.url(:repeat)
      response = new_client(:endpoint => repeat_url).call(:authenticate, :message => { :user => "luke", :password => "secret" })
      expect(response.http.body).to include("<ins0:authenticate><user>luke</user><password>secret</password></ins0:authenticate>")
    end

    it "also accepts a String of raw XML" do
      repeat_url = @server.url(:repeat)
      response = new_client(:endpoint => repeat_url).call(:authenticate, :message => "<user>lea</user><password>top-secret</password>")
      expect(response.http.body).to include("<ins0:authenticate><user>lea</user><password>top-secret</password></ins0:authenticate>")
    end
  end

  context "request :xml" do
    it "accepts a String of raw XML" do
      repeat_url = @server.url(:repeat)
      response = new_client(:endpoint => repeat_url).call(:authenticate, :xml => "<soap>request</soap>")
      expect(response.http.body).to eq("<soap>request</soap>")
    end
  end

  def new_client(options = {})
    Savon.new_client(Fixture.wsdl(:authentication), options)
  end

end