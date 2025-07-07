# frozen_string_literal: true

module PhoneFieldBonus
  class PhoneFieldChecker
    PHONE_FIELD_ID = 1 
    POINTS_REWARD = 10
    
    def self.check_and_award_points(user)
      return unless SiteSetting.phone_field_bonus_enabled
      return unless user&.id
      
      return if already_awarded?(user)
      
      phone_value = get_phone_field_value(user)
      
      if phone_filled_and_valid?(phone_value)
        award_points(user)
        mark_as_awarded(user)
        
        Rails.logger.info("Phone field bonus: Awarded #{POINTS_REWARD} points to user #{user.id} for completing phone field")
      end
    end
    
    private
    
    def self.get_phone_field_value(user)
      user_field = user.user_fields&.dig(PHONE_FIELD_ID.to_s)
      return user_field if user_field.present?
      
      user.custom_fields&.dig("user_field_#{PHONE_FIELD_ID}")
    end
    
    def self.phone_filled_and_valid?(phone_value)
      return false if phone_value.blank?
      phone_cleaned = phone_value.to_s.gsub(/[^\d]/, '')
      phone_cleaned.length >= 8 && phone_cleaned.length <= 15
    end
    
    def self.already_awarded?(user)
      user.custom_fields&.dig('phone_field_bonus_awarded') == 'true'
    end
    
    def self.mark_as_awarded(user)
      user.custom_fields ||= {}
      user.custom_fields['phone_field_bonus_awarded'] = 'true'
      user.save_custom_fields
    end
    
    def self.award_points(user)
      if defined?(DiscourseGamification)
        begin
          DiscourseGamification::GamificationScoreEvent.track_event(
            :phone_field_completed,
            user_id: user.id,
            category_id: nil,
            topic_id: nil,
            post_id: nil
          )
          
          DiscourseGamification.add_score_to_user(user.id, POINTS_REWARD, 'phone_field_completed')
        rescue => e
          Rails.logger.error("Phone field bonus: Error awarding points to user #{user.id}: #{e.message}")
        end
      else
        Rails.logger.warn("Phone field bonus: Gamification plugin not found, cannot award points")
      end
    end
  end
end 