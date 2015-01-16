require 'spec_helper'

describe 'CallFlow::Web::ContactFields' do
  let(:redis){ Redis.new }
  let(:instance){ double('InstanceWithID', {id: 42}) }
  let(:invalid_instance){ double('InvalidInstance', {name: 'Blah'}) }
  let(:fields){ ['name', 'email', 'address'] }

  subject{ CallFlow::Web::ContactFields.new(instance) }

  before do
    redis.flushall
  end

  describe 'instantiating' do
    it 'requires some object that responds to #id' do
      expect{ 
        CallFlow::Web::ContactFields.new(invalid_instance)
      }.to raise_error(ArgumentError)
    end

    it 'requires some object that returns a non-nil value for #id' do
      expect{
        CallFlow::Web::ContactFields.new(invalid_instance)
      }.to raise_error(ArgumentError)
    end
  end

  describe 'adding selected fields' do
    it 'stores given Array as JSON string' do
      subject.cache(fields)
      stored_fields = redis.hget "contact_fields", instance.id
      expect(stored_fields).to eq fields.to_json
    end
  end

  describe 'fetching fields for given object' do
    it 'returns the fields as an Array' do
      subject.cache(fields)
      expect(subject.data).to eq fields
    end

    it 'returns an empty Array when no fields are cached for the given object' do
      expect(subject.data).to eq []
    end
  end
end
