FactoryBot.define do
  factory :message do
    sequence(:number) { |n| n }
    body { Faker::Lorem.paragraph }
    association :chat
    association :creator, factory: :user
  end
end
