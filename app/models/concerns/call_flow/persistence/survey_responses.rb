class CallFlow::Persistence::SurveyResponses < CallFlow::Persistence
private
  def questions
    @questions ||= JSON.parse(call_data[:questions] || '{}')
  end

  def notes
    @notes ||= JSON.parse(call_data[:notes] || '{}')
  end

  def possible_responses_that_retry
    @possible_responses_that_retry ||= PossibleResponse.where(id: questions.values, retry: true)
  end

public
  def save(voter_record, call_attempt_record)
    if dialed_call.completed? and dialed_call.answered_by_human?
      save_answers(voter_record, call_attempt_record)
      save_notes(voter_record, call_attempt_record)
    end
  end

  def complete_lead?
    possible_responses_that_retry.count.zero?
  end

  def save_answers(voter_record, call_attempt_record)
    questions.each do |question_id, possible_response_id|
      Answer.create!({
        voter_id: voter_record.id,
        caller_id: caller_session.caller_id,
        call_attempt_id: call_attempt_record.id,
        campaign_id: campaign.id,
        possible_response_id: possible_response_id,
        question_id: question_id
      })
    end
  end

  def save_notes(voter_record, call_attempt_record)
    notes.each do |note_id, note_text|
      NoteResponse.create!({
        voter_id: voter_record.id,
        call_attempt_id: call_attempt_record.id,
        campaign_id: campaign.id,
        response: note_text,
        note_id: note_id
      })
    end
  end
end

