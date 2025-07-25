# frozen_string_literal: true

module PhoneFieldBonus
  class PhoneFieldBonusJob < ApplicationJob
    queue_as :low
    
    retry_on StandardError, wait: :exponentially_longer, attempts: 5
    retry_on ActiveJob::DeserializationError, attempts: 3
    discard_on ActiveRecord::RecordNotFound do |job, error|
      Rails.logger.warn "PhoneFieldBonusJob: User #{job.arguments.first} not found, discarding job"
    end
    
    around_perform do |job, block|
      start_time = Time.current
      job_id = job.job_id
      user_id = job.arguments.first
      
      Rails.logger.info "PhoneFieldBonusJob[#{job_id}]: Starting for user #{user_id}"
      
      begin
        block.call
        duration = Time.current - start_time
        Rails.logger.info "PhoneFieldBonusJob[#{job_id}]: Completed successfully in #{duration.round(3)}s"
        
        increment_job_stats("success")
        
      rescue => error
        duration = Time.current - start_time
        Rails.logger.error "PhoneFieldBonusJob[#{job_id}]: Failed after #{duration.round(3)}s - #{error.message}"
        
        increment_job_stats("failure")
        
        raise error
      end
    end
    
    def perform(user_id)
      return unless SiteSetting.phone_field_bonus_enabled
      
      raise ArgumentError, "user_id cannot be nil" if user_id.nil?
      
      user = User.find_by(id: user_id)
      raise ActiveRecord::RecordNotFound, "User with id #{user_id} not found" unless user
      
      job_key = "phone_bonus_job_#{user_id}"
      lock_value = Discourse.redis.get(job_key)
      
      if lock_value && lock_value != "processing"
        Rails.logger.warn "PhoneFieldBonusJob: Job for user #{user_id} already completed"
        return
      end
      
      result = PhoneFieldBonus::PhoneFieldChecker.check_and_award_points_safely(user)
      
      if result
        Rails.logger.info "PhoneFieldBonusJob: Successfully processed user #{user_id}"
        increment_job_stats("processed")
      else
        Rails.logger.debug "PhoneFieldBonusJob: No action needed for user #{user_id}"
        increment_job_stats("skipped")
      end
      
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn "PhoneFieldBonusJob: User #{user_id} not found"
      raise
    rescue => e
      Rails.logger.error "PhoneFieldBonusJob failed for user #{user_id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      job_key = "phone_bonus_job_#{user_id}"
      Discourse.redis.del(job_key)
      
      raise e
    end
    
    private
    
    def increment_job_stats(type)
      key = "phone_field_bonus_job_stats_#{type}_#{Date.current.strftime('%Y%m%d')}"
      Discourse.redis.incr(key)
      Discourse.redis.expire(key, 7.days.to_i)
    rescue => e
      Rails.logger.debug "Failed to increment job stats: #{e.message}"
    end
    
    def self.get_job_stats(date = Date.current)
      date_str = date.strftime('%Y%m%d')
      stats = {}
      
      %w[success failure processed skipped].each do |type|
        key = "phone_field_bonus_job_stats_#{type}_#{date_str}"
        stats[type] = Discourse.redis.get(key).to_i
      end
      
      stats[:date] = date
      stats
    end
    
    def self.get_job_stats_range(start_date, end_date)
      (start_date..end_date).map do |date|
        get_job_stats(date)
      end
    end
    
    def self.cleanup_old_stats(days_to_keep = 7)
      cutoff_date = Date.current - days_to_keep.days
      
      keys_to_delete = []
      (cutoff_date - 30.days..cutoff_date).each do |date|
        date_str = date.strftime('%Y%m%d')
        %w[success failure processed skipped].each do |type|
          keys_to_delete << "phone_field_bonus_job_stats_#{type}_#{date_str}"
        end
      end
      
      deleted_count = 0
      keys_to_delete.each_slice(100) do |batch|
        existing_keys = Discourse.redis.exists(*batch)
        if existing_keys > 0
          Discourse.redis.del(*batch)
          deleted_count += existing_keys
        end
      end
      
      Rails.logger.info "PhoneFieldBonusJob: Cleaned up #{deleted_count} old statistics keys"
      deleted_count
    end
  end
end 