# frozen_string_literal: true

# name: discourse-phone-field-bonus
# about: A plugin that awards gamification points when users fill in their phone number
# meta_topic_id: 0
# version: 0.1.0
# authors: Jeffrey
# url: https://github.com/discourse/discourse-phone-field-bonus
# required_version: 2.7.0

enabled_site_setting :phone_field_bonus_enabled

register_asset "stylesheets/phone-field-bonus.scss"

after_initialize do
  # Load plugin classes
  require_relative "lib/phone_field_bonus/engine"
  require_relative "lib/phone_field_bonus/phone_field_checker"
  
  # Register custom events for gamification
  if defined?(DiscourseGamification)
    DiscourseGamification::GamificationScoreEvent.add_event(
      :phone_field_completed,
      event_name: 'phone_field_completed'
    )
  end
  
  # Hook into user profile updates
  DiscourseEvent.on(:user_updated) do |user|
    PhoneFieldBonus::PhoneFieldChecker.check_and_award_points(user)
  end
  
  # Also check when custom fields are updated
  DiscourseEvent.on(:user_custom_fields_updated) do |user|
    PhoneFieldBonus::PhoneFieldChecker.check_and_award_points(user)
  end
end 