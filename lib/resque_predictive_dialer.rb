RAILS_ROOT = File.expand_path('../..', __FILE__)
require File.join(RAILS_ROOT, 'config/environment')
DIALER_ROOT = ENV['DIALER_ROOT'] || File.expand_path('..', __FILE__)
FileUtils.mkdir_p(File.join(DIALER_ROOT, 'log'), :verbose => true)
ActiveRecord::Base.logger = Logger.new(File.open(File.join(DIALER_ROOT, 'log', "dialer_#{RAILS_ENV}.log"), 'a'))
require 'em-http-request'
require "em-synchrony"
require "em-synchrony/em-http"



loop do
  begin
    predictive_campaigns = RedisCampaign.running_campaigns
    predictive_campaigns.each do |c|
      campaign = Campaign.find(c["campaign_id"])
      if !Resque.redis.exists("dial:#{campaign.id}")
        campaign.dial_resque
      end
    end
  rescue Exception => e
    if e.class==SystemExit
      puts "============ EXITING  ============"
      exit 
    end
    puts "DIALER EXCEPTION Rescued - #{ e } (#{ e.class })!"
    puts "DIALER EXCEPTION Backtrace : #{e.backtrace}"
  end
end