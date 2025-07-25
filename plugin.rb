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
  require_relative "lib/phone_field_bonus/phone_field_bonus_job"
  
  module ::Jobs
    class PhoneFieldBonusJob < PhoneFieldBonus::PhoneFieldBonusJob
    end
  end
  
  
  DiscourseEvent.on(:user_updated) do |user|
    next unless SiteSetting.phone_field_bonus_enabled
    next unless user&.id
    
    debounce_key = "phone_field_bonus_debounce_#{user.id}"
    if Discourse.redis.exists(debounce_key) > 0
      Rails.logger.debug "PhoneFieldBonus: Skipping check for user #{user.id} due to debouncing"
      next
    end
    
    Discourse.redis.setex(debounce_key, 30, "checked")
    
    Jobs.enqueue_in(2.seconds, :phone_field_bonus_job, user_id: user.id)
  end
  
  class << PhoneFieldBonus::PhoneFieldChecker
    def recheck_user(user_id)
      user = User.find(user_id)
      check_and_award_points(user)
    end
    
    def recheck_all_users
      Rails.logger.warn "PhoneFieldBonus: recheck_all_users is deprecated. Use recheck_all_users_safely instead."
      recheck_all_users_safely
    end
    
    def get_rate_limit_stats(user_id = nil)
      rate_limit_key = PhoneFieldBonus::PhoneFieldChecker::RATE_LIMIT_KEY
      if user_id
        key = "#{rate_limit_key}_#{user_id}"
        count = Discourse.redis.get(key).to_i
        ttl = Discourse.redis.ttl(key)
        { user_id: user_id, current_checks: count, reset_in_seconds: ttl }
      else
        keys = Discourse.redis.keys("#{rate_limit_key}_*")
        keys.map do |key|
          user_id = key.split('_').last
          count = Discourse.redis.get(key).to_i
          ttl = Discourse.redis.ttl(key)
          { user_id: user_id, current_checks: count, reset_in_seconds: ttl }
        end
      end
    end
    
    def clear_rate_limits(user_id = nil)
      rate_limit_key = PhoneFieldBonus::PhoneFieldChecker::RATE_LIMIT_KEY
      if user_id
        key = "#{rate_limit_key}_#{user_id}"
        Discourse.redis.del(key)
        Rails.logger.info "PhoneFieldBonus: Cleared rate limit for user #{user_id}"
      else
        keys = Discourse.redis.keys("#{rate_limit_key}_*")
        Discourse.redis.del(*keys) if keys.any?
        Rails.logger.info "PhoneFieldBonus: Cleared all rate limits (#{keys.length} keys)"
      end
    end
    
    def health_check
      rate_limit_key = PhoneFieldBonus::PhoneFieldChecker::RATE_LIMIT_KEY
      stats = {
        enabled: SiteSetting.phone_field_bonus_enabled,
        field_id: SiteSetting.phone_field_bonus_field_id,
        points: SiteSetting.phone_field_bonus_points,
        active_rate_limits: Discourse.redis.keys("#{rate_limit_key}_*").length,
        active_job_locks: Discourse.redis.keys("phone_bonus_job_*").length,
        cache_entries: Discourse.redis.keys("phone_field_bonus_*").length - 
                      Discourse.redis.keys("#{rate_limit_key}_*").length -
                      Discourse.redis.keys("phone_bonus_job_*").length
      }
      
      Rails.logger.info "PhoneFieldBonus Health Check: #{stats.inspect}"
      stats
    end
  end
  
  if defined?(DiscoursePluginRegistry)
    add_admin_route 'phone_field_bonus.title', 'phone-field-bonus'
  end
end 