# frozen_string_literal: true

module PhoneFieldBonus
  class PhoneFieldChecker
    
    def self.check_and_award_points(user)
      return unless SiteSetting.phone_field_bonus_enabled
      return unless user&.id
      
      Rails.logger.info("Phone field bonus: Checking user #{user.id} for phone field completion")
      
      if already_awarded?(user)
        Rails.logger.info("Phone field bonus: User #{user.id} already awarded, skipping")
        return
      end
      
      phone_value = get_phone_field_value(user)
      Rails.logger.info("Phone field bonus: User #{user.id} phone value: #{phone_value.present? ? '[PRESENT]' : '[EMPTY]'}")
      
      if phone_filled_and_valid?(phone_value)
        award_points(user)
        mark_as_awarded(user)
        
        Rails.logger.info("Phone field bonus: Awarded #{SiteSetting.phone_field_bonus_points} points to user #{user.id} for completing phone field")
      else
        Rails.logger.info("Phone field bonus: User #{user.id} phone field not valid or empty")
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
      # Use direct SQL to avoid triggering any ActiveRecord callbacks or events
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
          score_event = ::DiscourseGamification::ScoreEvent.create!(
            user_id: user.id,
            event_name: "phone_field_completed",
            score: SiteSetting.phone_field_bonus_points,
            created_at: Time.zone.now
          )
          Rails.logger.info("Phone field bonus: Successfully created score event #{score_event.id} for user #{user.id}")
        rescue => e
          Rails.logger.error("Phone field bonus: Error awarding points to user #{user.id}: #{e.message}")
          Rails.logger.error("Phone field bonus: Error backtrace: #{e.backtrace.join("\n")}")
        end
      else
        Rails.logger.warn("Phone field bonus: DiscourseGamification constant not defined - Gamification plugin not available")
        
        # 檢查是否有其他 gamification 相關的類
        gamification_classes = []
        ObjectSpace.each_object(Module) do |mod|
          if mod.name && mod.name.downcase.include?('gamification')
            gamification_classes << mod.name
          end
        end
        
        if gamification_classes.any?
          Rails.logger.info("Phone field bonus: Found gamification-related classes: #{gamification_classes.join(', ')}")
        else
          Rails.logger.warn("Phone field bonus: No gamification-related classes found in system")
        end
      end
    end
    
    # 診斷方法 - 可以在 Rails console 中使用
    def self.diagnose_user(user_id)
      user = User.find(user_id)
      
      puts "=== Phone Field Bonus 診斷報告 ==="
      puts "用戶 ID: #{user.id}"
      puts "用戶名: #{user.username}"
      
      puts "\n--- 插件設置 ---"
      puts "插件已啟用: #{SiteSetting.phone_field_bonus_enabled}"
      puts "積分數量: #{SiteSetting.phone_field_bonus_points}"
      puts "字段 ID: #{SiteSetting.phone_field_bonus_field_id}"
      
      puts "\n--- 用戶字段 ---"
      phone_value = get_phone_field_value(user)
      puts "手機號碼值: #{phone_value.present? ? phone_value : '[空白]'}"
      puts "號碼有效性: #{phone_filled_and_valid?(phone_value)}"
      
      if phone_value.present?
        cleaned = phone_value.to_s.gsub(/[^\d]/, '')
        puts "清理後號碼: #{cleaned}"
        puts "號碼長度: #{cleaned.length}"
      end
      
      puts "\n--- 獎勵狀態 ---"
      already_awarded = already_awarded?(user)
      puts "已獲獎勵: #{already_awarded}"
      
      puts "\n--- Gamification 插件狀態 ---"
      if defined?(DiscourseGamification)
        puts "DiscourseGamification: 已安裝 ✓"
        
        begin
          score_count = ::DiscourseGamification::ScoreEvent.where(user_id: user.id).count
          puts "用戶總積分事件數: #{score_count}"
          
          phone_events = ::DiscourseGamification::ScoreEvent.where(
            user_id: user.id, 
            event_name: "phone_field_completed"
          ).count
          puts "手機完成事件數: #{phone_events}"
        rescue => e
          puts "查詢積分事件時發生錯誤: #{e.message}"
        end
      else
        puts "DiscourseGamification: 未安裝 ✗"
      end
      
      puts "\n--- 建議 ---"
      if !SiteSetting.phone_field_bonus_enabled
        puts "• 啟用插件設置"
      elsif phone_value.blank?
        puts "• 填寫手機號碼"
      elsif !phone_filled_and_valid?(phone_value)
        puts "• 確保手機號碼格式正確（8-15位數字）"
      elsif already_awarded
        puts "• 用戶已經獲得過獎勵"
      elsif !defined?(DiscourseGamification)
        puts "• 安裝並啟用 Discourse Gamification 插件"
      else
        puts "• 嘗試重新保存個人資料以觸發檢查"
      end
      
      puts "=== 診斷完成 ==="
    end
  end
end 