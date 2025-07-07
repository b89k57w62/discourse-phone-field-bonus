# frozen_string_literal: true

module PhoneFieldBonus
  class PhoneFieldChecker
    
    def self.check_and_award_points(user)
      return unless SiteSetting.phone_field_bonus_enabled
      return unless user&.id
      
      
      if already_awarded?(user)
        return
      end
      
      phone_value = get_phone_field_value(user)
      
      if phone_filled_and_valid?(phone_value)
        award_points(user)
        mark_as_awarded(user)
        
      end
    end
    
    private
    
    def self.get_phone_field_value(user)
      user_field = user.user_fields&.dig(SiteSetting.phone_field_bonus_field_id.to_s)
      return user_field if user_field.present?
      
      user.custom_fields&.dig("user_field_#{SiteSetting.phone_field_bonus_field_id}")
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
        UserCustomField.upsert(
        {
          user_id: user.id,
          name: 'phone_field_bonus_awarded',
          value: 'true',
          created_at: Time.zone.now,
          updated_at: Time.zone.now
        },
        unique_by: [:user_id, :name]
      )
    end
    
    def self.award_points(user)
      if defined?(DiscourseGamification)
        begin
          score_event = ::DiscourseGamification::GamificationScoreEvent.create!(
            user_id: user.id,
            description: "phone_field_completed",
            points: SiteSetting.phone_field_bonus_points,
            date: Date.current,
            created_at: Time.zone.now
          )
        rescue => e
        end
      else
      end
    end
    
    def self.diagnose_user(user_id)
      user = User.find(user_id)
    end
  end
end 