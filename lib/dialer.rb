require File.join(RAILS_ROOT, 'config/environment')

campaign_id = ARGV.first.to_i
campaign = Campaign.find(campaign_id)
puts "Starting to call campaign  #{campaign.id} #{campaign.name}"
Twilio.default_options[:ssl_ca_file] = File.join(RAILS_ROOT, 'cacert.pem')
Twilio.connect(TWILIO_ACCOUNT, TWILIO_AUTH)
campaign.dial
