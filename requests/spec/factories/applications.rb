FactoryBot.define do
  factory :application do
    name { Faker::App.name }
    association :creator, factory: :user
  end
end
