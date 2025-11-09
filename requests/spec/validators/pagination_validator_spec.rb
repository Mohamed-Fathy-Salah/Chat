require 'rails_helper'

RSpec.describe PaginationValidator, type: :model do
  describe 'validation' do
    it 'is valid with valid page and limit' do
      validator = PaginationValidator.new(page: 1, limit: 10)
      expect(validator).to be_valid
    end

    it 'is valid without page and limit (nil values)' do
      validator = PaginationValidator.new({})
      expect(validator).to be_valid
    end

    it 'is invalid with negative page' do
      validator = PaginationValidator.new(page: -1, limit: 10)
      expect(validator).not_to be_valid
    end

    it 'is invalid with zero page' do
      validator = PaginationValidator.new(page: 0, limit: 10)
      expect(validator).not_to be_valid
    end

    it 'is invalid with limit greater than 100' do
      validator = PaginationValidator.new(page: 1, limit: 101)
      expect(validator).not_to be_valid
    end

    it 'is invalid with negative limit' do
      validator = PaginationValidator.new(page: 1, limit: -1)
      expect(validator).not_to be_valid
    end
  end

  describe 'page_value' do
    it 'returns default 1 when page is nil' do
      validator = PaginationValidator.new({})
      expect(validator.page_value).to eq(1)
    end

    it 'returns clamped value for negative page' do
      validator = PaginationValidator.new(page: -5)
      expect(validator.page_value).to eq(1)
    end

    it 'returns correct page value' do
      validator = PaginationValidator.new(page: 5)
      expect(validator.page_value).to eq(5)
    end
  end

  describe 'limit_value' do
    it 'returns default 10 when limit is nil' do
      validator = PaginationValidator.new({})
      expect(validator.limit_value).to eq(10)
    end

    it 'returns clamped value for limit greater than 100' do
      validator = PaginationValidator.new(limit: 200)
      expect(validator.limit_value).to eq(100)
    end

    it 'returns clamped value for negative limit' do
      validator = PaginationValidator.new(limit: -5)
      expect(validator.limit_value).to eq(1)
    end

    it 'returns correct limit value' do
      validator = PaginationValidator.new(limit: 25)
      expect(validator.limit_value).to eq(25)
    end
  end
end
