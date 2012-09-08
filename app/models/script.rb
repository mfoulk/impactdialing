class Script < ActiveRecord::Base

  include Deletable
  validates_presence_of :name
  validate :no_campaign_using_on_deletion
  belongs_to :account
  has_many :script_texts, :inverse_of => :script
  has_many :questions, :inverse_of => :script
  has_many :notes, :inverse_of => :script
  has_many :transfers
  has_many :campaigns
  accepts_nested_attributes_for :campaigns
  accepts_nested_attributes_for :script_texts, :allow_destroy => true
  accepts_nested_attributes_for :questions, :allow_destroy => true
  accepts_nested_attributes_for :notes, :allow_destroy => true
  accepts_nested_attributes_for :transfers, :allow_destroy => true

  scope :active, {:conditions => {:active => 1}}

  cattr_reader :per_page
  @@per_page = 25



  def selected_fields
    JSON.parse(voter_fields).select{ |field| VoterList::VOTER_DATA_COLUMNS.values.include?(field) } if voter_fields
  end

  def selected_custom_fields
    JSON.parse(voter_fields).select{ |field| !VoterList::VOTER_DATA_COLUMNS.values.include?(field) } if voter_fields
  end

  def selected_fields_json
    result = Hash.new
    selected_fields.try(:each) do |x|
      result[x+"_flag"] = true
    end
    result
  end


    def self.default_script(account)
      possible_responses = []
      possible_responses << PossibleResponse.new(keypad: 1, value:"It's great.", retry: false)
      possible_responses << PossibleResponse.new(keypad: 2, value: "It's amazing!", retry: false)
      possible_responses << PossibleResponse.new(keypad: 3, value: "I'm a bit confused, so I'm going to call Support.", retry: false)
      possible_responses << PossibleResponse.new(keypad: 4, value: "How did I get here? I'm so lost.", retry: false)
      question = Question.new(text: "How do you like the predictive dialer so far?")
      question.possible_responses = possible_responses
      Script.new(name: 'Demo script',  active: 1, account_id: account.id).tap do |script|
        script.voter_fields='["FirstName","LastName","Phone"]'
        script.notes << Note.new(note:"What's your favorite feature?")
        script.questions << question
        script.script = <<-EOS
  Hi, I'm calling to tell you about how great Impact Dialing is.
        EOS
      end
    end

    def questions_and_responses
      questions.all(:include => [:possible_responses]).inject({}) do |acc, question|
        acc[question.text] = question.possible_responses.map(&:value)
        acc
      end
    end

  def no_campaign_using_on_deletion
    if active_change == [true, false] && !campaigns.empty?
      errors.add(:base, I18n.t(:script_cannot_be_deleted))
    end
  end

end
