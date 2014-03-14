module Markety
  def self.new_client(access_key, secret_key, end_point, api_version = '2_2')
    client = Savon.client do
      endpoint end_point
      wsdl "http://app.marketo.com/soap/mktows/#{api_version}?WSDL"
      env_namespace "SOAP-ENV"
      namespaces({"xmlns:ns1" => "http://www.marketo.com/mktows/"})
      pretty_print_xml true
    end
    
    Client.new(client, Markety::AuthenticationHeader.new(access_key, secret_key))
  end
  
  class Client
    def initialize(savon_client, authentication_header)
      @client = savon_client
      @header = authentication_header
    end

    public

    # set the logger
    def set_logger(logger)
      @logger = logger
    end

    # multiple lead functionality
    def get_multiple_leads_by_email(emails)
      if !emails.kind_of?(Array)
        emails = []
      end

      get_multiple_leads(MultiLeadsKey.new(LeadKeyType::EMAIL, emails))
    end

    # lead functionality
    def get_lead_by_idnum(idnum)
      get_lead(LeadKey.new(LeadKeyType::IDNUM, idnum))
    end

    def get_lead_by_email(email)
      get_lead(LeadKey.new(LeadKeyType::EMAIL, email))
    end

    def sync_lead(email, first, last, company, mobile)
      lead_record = LeadRecord.new(email)
      lead_record.set_attribute('FirstName', first)
      lead_record.set_attribute('LastName', last)
      lead_record.set_attribute('Email', email)
      lead_record.set_attribute('Company', company)
      lead_record.set_attribute('MobilePhone', mobile)
      sync_lead_record(lead_record)
    end

    def sync_lead_record(lead_record)
      begin
        attributes = []
        lead_record.each_attribute_pair do |name, value|
          attributes << {:attr_name => name, :attr_value => value, :attr_type => lead_record.get_attribute_type(name) }
        end

        response = send_request(:sync_lead, {
          :dedup_enabled => true,
          :lead_record => {
            :email => lead_record.email,
            :lead_attribute_list => {
              :attribute => attributes
            }
          }
        })
        return LeadRecord.from_hash(response[:success_sync_lead][:result][:lead_record])
      rescue Exception => e
        @logger.log(e) if @logger
        return nil
      end
    end

    def sync_multiple_lead_records(lead_records)
      lead_record_list = []

      begin
        for lead_record in lead_records
          attributes = []
          lead_record.each_attribute_pair do |name, value|
            attributes << {:attr_name => name, :attr_value => value, :attr_type => lead_record.get_attribute_type(name) }
          end

          lead_record_list << {
            :email => lead_record.email,
            :lead_attribute_list => {
              :attribute => attributes
            }
          }
        end

        response = send_request(:sync_multiple_leads, {
          :dedup_enabled => true,
          :lead_record_list => {:lead_record => lead_record_list}
        })
        return response[:success_sync_multiple_leads][:result][:sync_status_list]
      rescue Exception => e
        @logger.log(e) if @logger
        return nil
      end
    end

    def sync_lead_record_on_id(lead_record)
      idnum = lead_record.idnum
      raise 'lead record id not set' if idnum.nil?

      begin
        attributes = []
        lead_record.each_attribute_pair do |name, value|
          attributes << {:attr_name => name, :attr_value => value}
        end

        attributes << {:attr_name => 'Id', :attr_type => 'string', :attr_value => idnum.to_s}

        response = send_request(:sync_lead, {
          :return_lead => true,
          :lead_record =>
          {
            :lead_attribute_list => { :attribute => attributes},
            :id => idnum
          }
        })
        return LeadRecord.from_hash(response[:success_sync_lead][:result][:lead_record])
      rescue Exception => e
        @logger.log(e) if @logger
        return nil
      end
    end

    # list functionality
    def add_to_list(list_key, email)
      list_operation(list_key, ListOperationType::ADD_TO, email)
    end

    def remove_from_list(list_key, email)
      list_operation(list_key, ListOperationType::REMOVE_FROM, email)
    end

    def is_member_of_list?(list_key, email)
      list_operation(list_key, ListOperationType::IS_MEMBER_OF, email)
    end

    # MObject functionality
    def list_m_objects()
      begin
        response = send_request(:list_m_objects, {
          :params_list_mobjects => []
        })
        return response[:success_list_m_objects][:result]
      rescue Exception => e
        @logger.log(e) if @logger
        return nil
      end
    end

    private
      def list_operation(list_key, list_operation_type, email)
        begin
          response = send_request(:list_operation, {
            :list_operation   => list_operation_type,
            :list_key         => list_key,
            :strict           => 'false',
            :list_member_list => {
              :lead_key => [
              {:key_type => 'EMAIL', :key_value => email}
            ]
          }
        })
        return response
      rescue Exception => e
        @logger.log(e) if @logger
        return nil
      end
    end

    def get_lead(lead_key)
      begin
        response = send_request(:get_lead, {"leadKey" => lead_key.to_hash})
        return LeadRecord.from_hash(response[:success_get_lead][:result][:lead_record_list][:lead_record])
      rescue Exception => e
        @logger.log(e) if @logger
        return nil
      end
    end

    def get_multiple_leads(lead_key)
      begin
        response = send_request(:get_multiple_leads, {"leadKey" => lead_key.to_hash})
        return LeadRecord.from_hash_list(response[:success_get_multiple_leads][:result][:lead_record_list][:lead_record])
      rescue Exception => e
        @logger.log(e) if @logger
        return nil
      end
    end

    def send_request(namespace, message)
      @header.set_time(DateTime.now)
      response = request(namespace, message, @header.to_hash)
      response.to_hash
    end

    def request(namespace, message, header)
      @client.call(namespace, :message => message, :soap_header => header)
    end
  end
end
