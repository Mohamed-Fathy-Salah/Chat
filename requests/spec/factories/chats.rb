FactoryBot.define do
  factory :chat do
    sequence(:number) { |n| n }
    association :application
    association :creator, factory: :user
  end
end
