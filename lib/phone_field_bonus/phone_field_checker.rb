# frozen_string_literal: true

module PhoneFieldBonus
  class PhoneFieldChecker
    RATE_LIMIT_KEY = "phone_field_bonus_check"
    RATE_LIMIT_WINDOW = 300
    RATE_LIMIT_MAX_CHECKS = 50
    
    def self.check_and_award_points(user)
      return unless SiteSetting.phone_field_bonus_enabled
      return unless user&.id
      
      return if rate_limited?(user)
      
      if already_awarded?(user)
        return
      end
      
      phone_value = get_phone_field_value(user)
      
      if phone_filled_and_valid?(phone_value)
        job_key = "phone_bonus_job_#{user.id}"
        return if Discourse.redis.exists(job_key) > 0
        
        Discourse.redis.setex(job_key, 300, "processing")
        
        Jobs.enqueue(:phone_field_bonus_job, user_id: user.id)
      end
    end
    
    def self.check_and_award_points_safely(user)
      return unless SiteSetting.phone_field_bonus_enabled
      return unless user&.id
      
      if already_awarded?(user)
        Rails.logger.info "PhoneFieldBonus: User #{user.id} already awarded"
        return
      end
      
      phone_value = get_phone_field_value(user)
      
      if phone_filled_and_valid?(phone_value)
        success = award_points_safely(user)
        if success
          mark_as_awarded(user)
          Rails.logger.info "PhoneFieldBonus: Successfully awarded points to user #{user.id}"
          
          job_key = "phone_bonus_job_#{user.id}"
          Discourse.redis.del(job_key)
        else
          Rails.logger.warn "PhoneFieldBonus: Failed to award points to user #{user.id}"
        end
      else
        Rails.logger.debug "PhoneFieldBonus: User #{user.id} phone field invalid or empty"
      end
    end
    
    private
    
    def self.rate_limited?(user)
      key = "#{RATE_LIMIT_KEY}_#{user.id}"
      current_count = Discourse.redis.get(key).to_i
      
      if current_count >= RATE_LIMIT_MAX_CHECKS
        Rails.logger.warn "PhoneFieldBonus: Rate limited user #{user.id}"
        return true
      end
      
      if current_count == 0
        Discourse.redis.setex(key, RATE_LIMIT_WINDOW, 1)
      else
        Discourse.redis.incr(key)
      end
      
      false
    end
    
    def self.get_phone_field_value(user)
      cache_key = "phone_field_bonus_value_#{user.id}_#{user.updated_at.to_i}"
      
      cached_value = Discourse.cache.read(cache_key)
      return cached_value if cached_value
      
      user_field = user.user_fields&.dig(SiteSetting.phone_field_bonus_field_id.to_s)
      if user_field.present?
        value = user_field
      else
        value = user.custom_fields&.dig("user_field_#{SiteSetting.phone_field_bonus_field_id}")
      end
      
      Discourse.cache.write(cache_key, value, expires_in: 5.minutes) if value
      value
    end
    
    def self.phone_filled_and_valid?(phone_value)
      return false if phone_value.blank?
      phone_cleaned = phone_value.to_s.gsub(/[^\d]/, '')
      phone_cleaned.length >= 8 && phone_cleaned.length <= 15
    end
    
    def self.already_awarded?(user)
      cache_key = "phone_field_bonus_awarded_#{user.id}"
      cached_result = Discourse.cache.read(cache_key)
      return cached_result if cached_result == true || cached_result == false
      
      result = user.custom_fields&.dig('phone_field_bonus_awarded') == 'true'
      
      Discourse.cache.write(cache_key, result, expires_in: 1.hour)
      result
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
      
      cache_key = "phone_field_bonus_awarded_#{user.id}"
      Discourse.cache.delete(cache_key)
    end
    
    def self.award_points_safely(user)
      begin
        if defined?(DiscourseGamification)
          award_points_via_plugin(user)
        elsif respond_to_discourse_core_scoring?(user)
          award_points_via_core(user)
        else
          award_points_via_direct_update(user)
        end
        return true
      rescue => e
        Rails.logger.error "PhoneFieldBonus: Error awarding points to user #{user.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        return false
      end
    end
    
    def self.award_points(user)
      award_points_safely(user)
    end
    
    def self.respond_to_discourse_core_scoring?(user)
      defined?(UserStat) && user.user_stat.present? && user.user_stat.respond_to?(:custom_score)
    end
    
    def self.award_points_via_core(user)
      DiscourseEvent.trigger(:phone_field_bonus_awarded, user: user, points: SiteSetting.phone_field_bonus_points)
      
      if user.user_stat.respond_to?(:custom_score)
        user.user_stat.increment!(:custom_score, SiteSetting.phone_field_bonus_points)
      end
    end
    
    def self.award_points_via_plugin(user)
      ::DiscourseGamification::GamificationScoreEvent.create!(
        user_id: user.id,
        description: "phone_field_completed",
        points: SiteSetting.phone_field_bonus_points,
        date: Date.current,
        created_at: Time.zone.now
      )
    end
    
    def self.award_points_via_direct_update(user)
      UserCustomField.upsert(
        {
          user_id: user.id,
          name: 'phone_field_bonus_points',
          value: SiteSetting.phone_field_bonus_points.to_s,
          created_at: Time.zone.now,
          updated_at: Time.zone.now
        },
        unique_by: [:user_id, :name]
      )
    end
    
    def self.diagnose_user(user_id)
      user = User.find(user_id)
      Rails.logger.info "PhoneFieldBonus Diagnosis for User #{user_id}:"
      Rails.logger.info "- Already awarded: #{already_awarded?(user)}"
      Rails.logger.info "- Phone value: #{get_phone_field_value(user)}"
      Rails.logger.info "- Phone valid: #{phone_filled_and_valid?(get_phone_field_value(user))}"
    end

    def self.recheck_all_users_safely(batch_size: 100, delay_between_batches: 5.seconds)
      Rails.logger.info "PhoneFieldBonus: Starting safe batch recheck of all users"
      
      total_processed = 0
      
      User.joins("LEFT JOIN user_custom_fields ucf ON users.id = ucf.user_id AND ucf.name = 'phone_field_bonus_awarded'")
          .where("ucf.value IS NULL OR ucf.value != 'true'")
          .find_in_batches(batch_size: batch_size) do |batch|
            
        batch.each do |user|
          check_and_award_points(user)
          total_processed += 1
        end
        
        Rails.logger.info "PhoneFieldBonus: Processed #{total_processed} users..."
        
        sleep(delay_between_batches) if delay_between_batches > 0
      end
      
      Rails.logger.info "PhoneFieldBonus: Completed batch recheck. Total processed: #{total_processed}"
    end
  end
end 