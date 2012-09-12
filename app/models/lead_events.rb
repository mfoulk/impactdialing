module LeadEvents
  
  module ClassMethods
  end
  
  module InstanceMethods
    
    def publish_incoming_call
      MonitorEvent.incoming_call_request(campaign)
    end
    
    def publish_voter_connected      
      unless caller_session.nil?
        EM.synchrony {
          if !caller_session.caller.is_phones_only? && !voter.caller_session.nil?
            event_hash = campaign.voter_connected_event(self.call)        
            caller_deferrable = Pusher[caller_session.session_key].trigger_async(event_hash[:event], event_hash[:data].merge!(:dialer => campaign.type))
            caller_deferrable.callback {}
            caller_deferrable.errback { |error| }
          end
        }      
      MonitorEvent.create_caller_notification(campaign.id, caller_session.id, status)  
      end
      MonitorEvent.voter_connected(campaign)      
    end    
    
    def publish_voter_disconnected
      unless caller_session.nil?
        EM.synchrony {
          unless caller_session.caller.is_phones_only?      
            caller_deferrable = Pusher[caller_session.session_key].trigger_async("voter_disconnected", {})
            caller_deferrable.callback {}
            caller_deferrable.errback { |error| puts error.inspect}
          end          
        }   
      MonitorEvent.create_caller_notification(campaign.id, caller_session.id, status)  
      end
      MonitorEvent.voter_disconnected(campaign)
    end
    
    def publish_moderator_response_submited
      MonitorEvent.voter_response_submitted(campaign)
      MonitorEvent.create_caller_notification(campaign.id, caller_session.id, "On hold")  
    end
    
  end
  
  def self.included(receiver)
    receiver.extend         ClassMethods
    receiver.send :include, InstanceMethods
  end
  
end