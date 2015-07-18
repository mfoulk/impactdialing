require 'rails_helper'

describe 'CallList::DisabledTrimmer' do
  include ListHelpers

  let(:campaign) do
    create(:preview)
  end
  let(:list_one) do
    create(:voter_list, campaign: campaign)
  end
  let(:list_two) do
    create(:voter_list, campaign: campaign)
  end
  let(:with_custom_id){ false }
  let(:households_one) do
    build_household_hashes(1, list_one, with_custom_id)
  end
  let(:households_two) do
    build_household_hashes(1, list_two, with_custom_id)
  end
  let(:parser) do
    double('CallList::Imports::Parser', {
      parse_file: nil
    })
  end
  let(:active_redis_key){ "dial_queue:#{campaign.id}:households:active:111" }
  let(:inactive_redis_key){ "dial_queue:#{campaign.id}:households:inactive:111" }
  let(:recycle_bin_key){ "dial_queue:#{campaign.id}:bin" }
  let(:available_key){ "dial_queue:#{campaign.id}:active" }
  let(:blocked_key){ "dial_queue:#{campaign.id}:blocked" }
  let(:completed_key){ "dial_queue:#{campaign.id}:completed" }
  let(:redis){ Redis.new }

  describe 'disabling leads' do
    subject{ CallList::DisabledTrimmer.new(list_one) }

    let(:phone){ households_one.keys.first }
    let(:score){ redis.zscore available_key, phone }

    context 'first time disabling given phone/household' do
      before do
        import_list(list_one, households_one)
        import_list(list_two, households_two)
        expect(households_one).to be_in_redis_households(campaign.id, 'active')
        expect(households_two).to be_in_redis_households(campaign.id, 'active')

        score # populate this :let after import
        stub_list_parser(parser, active_redis_key, households_one)
      end

      it 'moves leads associated w/ disabled list to "inactive" namespace' do
        subject.disable_leads
        expect(households_one).to be_in_redis_households(campaign.id, 'inactive')
        expect(households_one).to_not be_in_redis_households(campaign.id, 'active')
      end

      context 'phone has been dialed recently' do
        before do
          redis.zrem available_key, phone
          redis.zadd recycle_bin_key, score, phone
          subject.disable_leads
        end

        it 'stores current score (recycle bin zscore) of phone number' do
          house = Redis.new.hget inactive_redis_key.gsub('111', phone[0..-4]), phone[-3..-1]
          house = JSON.parse house
          expect(house['score'].to_f).to be_within(0.0000001).of score
        end
      end

      context 'phone has been dialed but not recently' do
        before do
          subject.disable_leads
        end

        it 'stores current score (available zscore) of phone number' do
          house = Redis.new.hget inactive_redis_key.gsub('111', phone[0..-4]), phone[-3..-1]
          house = JSON.parse house
          expect(house['score'].to_f).to be_within(0.0000001).of score
        end
      end

      context 'phone number has no active leads from other lists' do
        it 'is removed from available set' do
          expect(phone).to eq households_one.keys.first
          redis.zadd available_key, 1.1, phone
          subject.disable_leads
          expect(phone).to_not be_in_dial_queue_zset(campaign.id, 'active')
        end
        it 'is removed from recycle bin set' do
          redis.zrem available_key, phone
          redis.zadd recycle_bin_key, 1.1, phone
          subject.disable_leads
          expect(phone).to_not be_in_dial_queue_zset(campaign.id, 'bin')
        end
        it 'is removed from blocked set' do
          redis.zrem available_key, phone
          redis.zadd blocked_key, 1.0, phone
          subject.disable_leads
          expect(phone).to_not be_in_dial_queue_zset(campaign.id, 'blocked')
        end
        it 'is NOT removed from completed set' do
          redis.zrem available_key, phone
          redis.zadd completed_key, "#{Time.now.to_i}.000005", phone
          subject.disable_leads
          expect(phone).to be_in_dial_queue_zset(campaign.id, 'completed')
        end
      end

      context 'phone number has active leads from other lists' do
        let(:lead_from_another_list){ build_lead_hash(list_two, phone) }
        before do
          households_one[phone][:leads] << lead_from_another_list
          import_list(list_one, households_one)
          expect(households_one).to be_in_redis_households(campaign.id, 'active')
          stub_list_parser(parser, active_redis_key, households_one)
        end

        it 'is not removed from available set' do
          subject.disable_leads
          expect(phone).to be_in_dial_queue_zset(campaign.id, 'active')
        end
        it 'is not removed from recycle bin set' do
          redis.zrem available_key, phone
          redis.zadd recycle_bin_key, 1.1, phone
          subject.disable_leads
          expect(phone).to be_in_dial_queue_zset(campaign.id, 'bin')
        end
        it 'is not removed from blocked set' do
          redis.zrem available_key, phone
          redis.zadd blocked_key, 1.0, phone
          subject.disable_leads
          expect(phone).to be_in_dial_queue_zset(campaign.id, 'blocked')
        end
        it 'is not removed from completed set' do
          redis.zrem available_key, phone
          redis.zadd completed_key, 1.1, phone
          subject.disable_leads
          expect(phone).to be_in_dial_queue_zset(campaign.id, 'completed')
        end
      end
    end

    context 'inactive household already exists at same namespace (ie leads in household from other lists already disabled)' do
      context 'leads have custom ids' do
        let(:lead_from_another_list){ build_lead_hash(list_two, phone, 100) }
        let(:lead_from_same_list){ build_lead_hash(list_one, phone, 100) }
        let(:households_one){ build_household_hashes(1, list_one, true) }
        let(:households_two){ build_household_hashes(1, list_two, true) }
        let(:subject_two){ CallList::DisabledTrimmer.new(list_two) }

        before do
          # import then disable first list, storing lead_from_same_list in inactive
          households_one[phone][:leads] << lead_from_same_list
          stub_list_parser(list_one, active_redis_key, households_one)
          import_list(list_one, households_one)
          expect(households_one).to be_in_redis_households(campaign.id, 'active')
          subject.disable_leads # disables list one
          expect(households_one).to be_in_redis_households(campaign.id, 'inactive')

          # import then disable second list (still households_one + lead_from_another_list)
          hh_one                = households_one
          hh_one[phone][:leads] = [lead_from_another_list]
          stub_list_parser(list_one, active_redis_key, hh_one)
          import_list(list_two, hh_one)
          expect(hh_one).to be_in_redis_households(campaign.id, 'active')
          stub_list_parser(parser, active_redis_key, hh_one)
          subject_two.disable_leads
        end

        it 'updates matching inactive leads w/ data from active lead' do
          hh_one = households_one
          hh_one[phone][:leads] = [lead_from_another_list]
          expect(hh_one).to be_in_redis_households(campaign.id, 'inactive')
        end
        it 'does not duplicate leads w/ matching custom id' do
          inactive_households = redis.hgetall "#{inactive_redis_key.split(':')[0..-2].join(':')}:#{phone[0..-4]}"
          inactive_leads = []
          inactive_households.each{|ph,h| inactive_leads << h['leads']}
          total_inactive_leads = inactive_leads.size
          inactive_leads_with_custom_id = inactive_leads.map{|l| l['custom_id']}.uniq.size
          expect(total_inactive_leads).to eq inactive_leads_with_custom_id
        end
      end

      context 'leads do not have custom ids' do
        let(:lead_from_another_list){ build_lead_hash(list_two, phone) }
        let(:lead_from_same_list){ build_lead_hash(list_one, phone) }
        let(:households_one){ build_household_hashes(1, list_one) }
        let(:households_two){ build_household_hashes(1, list_two) }
        let(:subject_two){ CallList::DisabledTrimmer.new(list_two) }

        before do
          # import then disable first list, storing lead_from_same_list in inactive
          households_one[phone][:leads] << lead_from_same_list
          stub_list_parser(list_one, active_redis_key, households_one)
          import_list(list_one, households_one)
          expect(households_one).to be_in_redis_households(campaign.id, 'active')
          subject.disable_leads # disables list one
          expect(households_one).to be_in_redis_households(campaign.id, 'inactive')

          # import then disable second list (households_one + lead_from_another_list)
          hh_one                = households_one
          hh_one[phone][:leads] = [lead_from_another_list]
          stub_list_parser(list_one, active_redis_key, hh_one)
          import_list(list_two, hh_one)
          expect(hh_one).to be_in_redis_households(campaign.id, 'active')
          stub_list_parser(parser, active_redis_key, hh_one)
          subject_two.disable_leads
        end

        it 'adds leads to inactive household' do
          inactive_households = redis.hgetall "#{inactive_redis_key.split(':')[0..-2].join(':')}:#{phone[0..-4]}"
          inactive_leads = []
          inactive_households.each{|ph,h| inactive_leads << h['leads']}
          total_inactive_leads = inactive_leads.size
          expect(total_inactive_leads).to eq households_one[phone][:leads].size
        end
      end
    end
  end

  describe 'enabling leads' do
    it 'adds leads associated w/ enabled list'

    context 'phone number has leads active from other lists' do
      it 'is not moved from available set'
      it 'is not moved from recycle bin set'
      it 'is not moved from blocked set'
    end

    context 'phone number has no leads active from other lists' do
      context 'phone number is in completed set' do
        it 'is removed from completed set'
        
        context 'completed zscore indicates phone can be dialed right away' do
          it 'is added to availble set'
          it 'keeps the completed zscore'
        end
        context 'completed zscore indicates phone cannot be dialed right away' do
          it 'is added to recycle bin set'
          it 'keeps the completed zscore'
        end
      end

      context 'phone number was not completed before all leads were disabled' do
        context 'phone number zscore (saved to "inactive" namespace) indicates phone can be dialed right away' do
        end

        context 'phone number zscore indicates phone cannot be dialed right away' do
        end
      end
    end
  end
end

