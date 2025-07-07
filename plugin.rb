# frozen_string_literal: true

# name: discourse-phone-field-bonus
# about: A plugin that awards gamification points when users fill in their phone number
# meta_topic_id: 0
# version: 0.1.0
# authors: Jeffrey
# url: https://github.com/b89k57w62/discourse-phone-field-bonus
# required_version: 2.7.0

enabled_site_setting :phone_field_bonus_enabled

register_asset "stylesheets/phone-field-bonus.scss"

after_initialize do
  require_relative "lib/phone_field_bonus/engine"
  require_relative "lib/phone_field_bonus/phone_field_checker"
  
  DiscourseEvent.on(:user_updated) do |user|
    PhoneFieldBonus::PhoneFieldChecker.check_and_award_points(user)
  end
  
  class << PhoneFieldBonus::PhoneFieldChecker
    def recheck_user(user_id)
      user = User.find(user_id)
      check_and_award_points(user)
    end
    
    def recheck_all_users
      User.joins("LEFT JOIN user_custom_fields ucf ON users.id = ucf.user_id AND ucf.name = 'phone_field_bonus_awarded'")
          .where("ucf.value IS NULL OR ucf.value != 'true'")
          .find_each do |user|
        check_and_award_points(user)
      end
    end
  end
end 